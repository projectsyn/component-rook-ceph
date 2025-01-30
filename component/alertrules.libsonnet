local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local helpers = import 'helpers.libsonnet';

assert
  std.member(inv.applications, 'rancher-monitoring') ||
  std.member(inv.applications, 'openshift4-monitoring')
  : 'Neither rancher-monitoring nor openshift4-monitoring is available';

// Keep only alerts from params.ceph_cluster.ignore_alerts for which the last
// array entry wasn't prefixed with `~`.
local user_ignore_alerts =
  local legacyIgnores =
    if std.objectHas(params.ceph_cluster, 'ignore_alerts') then
      std.trace(
        'Parameter `ceph_cluster.ignore_alerts` is deprecated, please '
        + 'migrate your config to use parameter `alerts.ignoreNames` instead',
        params.ceph_cluster.ignore_alerts
      )
    else
      [];
  com.renderArray(
    legacyIgnores + params.alerts.ignoreNames
  );

// Upstream alerts to ignore
local ignore_alerts = std.set(
  [
    // Drop CephMgrIsMissingReplicas since we're not running multiple MGR
    // replicas at the moment, and the actual problem of the Mgr pod missing is
    // covered by `CephMgrIsAbsent`.
    'CephMgrIsMissingReplicas',
  ] +
  (
    // Drop CephOSDDownHigh for installations with < 10 nodes, since the alert
    // fires if more than 10% of OSDs are down (i.e. 1 node/OSD for small
    // clusters). The assumption here is that for clusters with >= 10 nodes,
    // the likelyhood of running >1 OSD per node is significant.
    if params.ceph_cluster.node_count < 10 then
      [ 'CephOSDDownHigh' ]
    else
      []
  ) +
  // Add set of upstream alerts that should be ignored from processed value of
  // `params.alerts.ignoreNames`
  user_ignore_alerts
);

local runbook(alertname) =
  'https://hub.syn.tools/rook-ceph/runbooks/%s.html' % alertname;

local alertpatching =
  if helpers.on_openshift then
    import 'lib/alert-patching.libsonnet'
  else
    local patchRule(rule, patches={}, patch_name=true) =
      if !std.objectHas(rule, 'alert') then
        rule
      else
        rule {
          alert:
            if patch_name then
              'SYN_%s' % super.alert
            else
              super.alert,
          labels+: {
            syn: 'true',
            syn_component: inv.parameters._instance,
          },
        };
    std.trace(
      'Alert patching library not available on non-OCP4, alerts may be configured incorrectly',
      {
        patchRule: patchRule,
        filterPatchRules(group, ignoreNames, patches):
          group {
            rules: [
              patchRule(r)
              for r in super.rules
              if !std.member(ignoreNames, r.alert)
            ],
          },
      }
    );

local prom =
  if helpers.on_openshift then
    import 'lib/prom.libsonnet'
  else
    std.trace(
      'Prometheus object helper library not available on non-OCP4, additional rules may be configured incorrectly',
      {
        generateRules(name, rules): {
          spec: {
            groups: [
              {
                name: group_name,
                rules: [
                  local keyparts = std.splitLimit(rulekey, ':', 1);
                  alertpatching.patchRule(
                    rules[group_name][rulekey] {
                      [keyparts[0]]: keyparts[1],
                    },
                    patches={},
                    patch_name=false,
                  )
                  for rulekey in std.objectFields(rules[group_name])
                ],
              }
              for group_name in std.objectFields(rules)
            ],
          },
        },
      }
    );

local alert_rules_raw = helpers.load_manifest('prometheus-ceph-rules');
assert std.length(alert_rules_raw) >= 1;
local alert_rules_manifests = std.filter(
  function(it) it != null,
  [
    if it.kind == 'PrometheusRule' then it
    for it in alert_rules_raw
  ]
);

local ignore_groups = std.set([
  // We don't need duplicate alerts for PVs that run full
  'persistent-volume-alert.rules',
  // We don't need duplicate alerts for storage nodes
  'ceph-node-alert.rules',
]);

local add_runbook_url = {
  rules: [
    if std.objectHas(r, 'alert') then
      local a =
        if r.alert == 'CephPGUnavilableBlockingIO' then
          r { alert: 'CephPGUnavailableBlockingIO' }
        else
          r;
      a {
        annotations+: {
          [if !std.objectHas(r.annotations, 'runbook_url') then 'runbook_url']:
            runbook(a.alert),
        },
      }
    else
      r
    for r in super.rules
  ],
};

local additional_rules =
  prom.generateRules(
    'additional-rules',
    // Adjust input to match expected format of `generateRules`
    {
      'syn-rook-ceph-additional.rules': params.alerts.additionalRules,
    }
  ) {
    spec+: {
      groups: [
        g + add_runbook_url
        for g in super.groups
      ],
    },
  };

local alert_rules = [
  local gs = std.filter(
    function(it) !std.member(ignore_groups, it.name),
    rule_manifest.spec.groups
  );
  rule_manifest {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
      name: 'syn-prometheus-ceph-rules',
    },
    spec: {
      groups: std.filter(
        function(it) it != null,
        [
          local r = alertpatching.filterPatchRules(
            g + add_runbook_url,
            ignore_alerts,
            params.alerts.patchRules,
          );
          if std.length(r.rules) > 0 then r
          for g in gs
        ]
      ) + additional_rules.spec.groups,
    },
  }
  for rule_manifest in alert_rules_manifests
];

{
  rules: alert_rules,
}
