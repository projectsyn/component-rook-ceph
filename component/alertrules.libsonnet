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

local on_openshift =
  inv.parameters.facts.distribution == 'openshift4';
local alertpatching =
  if on_openshift then
    import 'lib/alert-patching.libsonnet'
  else
    local patchRule(rule) =
      if !std.objectHas(rule, 'alert') then
        rule
      else
        rule {
          alert: 'SYN_%s' % super.alert,
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

local additional_rules = [
  {
    name: 'syn-rook-ceph-additional.alerts',
    rules: [
      alertpatching.patchRule(
        {
          alert: 'RookCephOperatorScaledDown',
          expr: 'kube_deployment_spec_replicas{deployment="rook-ceph-operator", namespace="%s"} == 0' % params.namespace,
          annotations: {
            summary: 'rook-ceph operator scaled to 0 for more than 1 hour.',
            description: 'TODO',
            runbook_url: runbook('RookCephOperatorScaledDown'),
          },
          labels: {
            severity: 'warning',
          },
          'for': '1h',
        },
      ),
    ],
  },
];

local add_runbook_url = {
  rules: [
    r {
      annotations+: {
        runbook_url: runbook(r.alert),
      },
    }
    for r in super.rules
  ],
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
      ) + additional_rules,
    },
  }
  for rule_manifest in alert_rules_manifests
];

{
  rules: alert_rules,
}
