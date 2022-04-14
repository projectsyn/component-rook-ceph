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

// Function to process an array which supports removing previously added
// elements by prefixing them with ~
local render_array(arr) =
  // extract real value of array entry
  local realval(v) = std.lstripChars(v, '~');
  // Compute whether each element should be included by keeping track of
  // whether its last occurrence in the input array was prefixed with ~ or
  // not.
  local val_state = std.foldl(
    function(a, it) a + it,
    [
      { [realval(v)]: !std.startsWith(v, '~') }
      for v in arr
    ],
    {}
  );
  // Return filtered array containing only elements whose last occurrence
  // wasn't prefixed by ~.
  std.filter(
    function(val) val_state[val],
    std.objectFields(val_state)
  );

// Keep only alerts from params.ceph_cluster.ignore_alerts for which the last
// array entry wasn't prefixed with `~`.
local user_ignore_alerts = render_array(params.ceph_cluster.ignore_alerts);

// Upstream alerts to ignore
local ignore_alerts = std.set(
  [
    // Drop CephMgrIsMissingReplicas since we're not running multiple MGR
    // replicas at the moment, and the actual problem of the Mgr pod missing is
    // covered by `CephMgrIsAbsent`.
    'CephMgrIsMissingReplicas',
  ] +
  // Add set of upstream alerts that should be ignored from processed value of
  // `params.ceph_cluster.ignore_alerts`
  user_ignore_alerts
);

local runbook(alertname) =
  'https://hub.syn.tools/rook-ceph/runbooks/%s.html' % alertname;

/* FROM HERE: should be provided as library function by
 * rancher-/openshift4-monitoring */
// We shouldn't be expected to care how rancher-/openshift4-monitoring
// implement alert managmement and patching, instead we should be able to
// reuse their functionality as a black box to make sure our alerts work
// correctly in the environment into which we're deploying.

local on_openshift =
  inv.parameters.facts.distribution == 'openshift4';

local global_alert_params =
  if on_openshift then
    inv.parameters.openshift4_monitoring.alerts
  else
    inv.parameters.rancher_monitoring.alerts;

local filter_patch_rules(g) =
  // combine our set of alerts to ignore with the monitoring component's
  // set of ignoreNames.
  local ignore_set = std.set(global_alert_params.ignoreNames + ignore_alerts);
  g {
    rules: std.map(
      // Patch rules to make sure they match the requirements.
      function(rule)
        local rulepatch = com.makeMergeable(
          com.getValueOrDefault(
            params.alerts.patchRules,
            rule.alert,
            {}
          )
        );
        local runbook_url = runbook(rule.alert);
        rule {
          // Change alert names so we don't get multiple alerts with the same
          // name, as the rook-ceph operator deploys its own copy of these
          // rules.
          alert: 'SYN_%s' % super.alert,
          // add customAnnotations configured for all alerts on cluster
          annotations+: global_alert_params.customAnnotations {
            runbook_url: runbook_url,
          },
          labels+: {
            // ensure the alerts are not silenced on OCP4
            // TODO: figure out how to ensure we don't get duplicate alerts on
            // not-OCP4
            syn: 'true',
            // mark alert as belonging to rook-ceph
            // can be used for inhibition rules
            syn_component: 'rook-ceph',
          },
        } + rulepatch,
      std.filter(
        // Filter out unwanted rules
        function(rule)
          // only create duplicates of alert rules, we can use the recording
          // rules which are deployed anyway when we enable monitoring on the
          // CephCluster resource.
          std.objectHas(rule, 'alert') &&
          // Drop rules which are in the ignore_set
          !std.member(ignore_set, rule.alert),
        super.rules
      ),
    ),
  };

/* TO HERE */

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
      {
        alert: 'SYN_RookCephOperatorScaledDown',
        expr: 'kube_deployment_spec_replicas{deployment="rook-ceph-operator", namespace="%s"} == 0' % params.namespace,
        annotations: global_alert_params.customAnnotations {
          summary: 'rook-ceph operator scaled to 0 for more than 1 hour.',
          description: 'TODO',
          runbook_url: runbook('RookCephOperatorScaledDown'),
        },
        labels: {
          severity: 'warning',
          syn_component: 'rook-ceph',
          syn: 'true',
        },
        'for': '1h',
      },
    ],
  },
];

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
          local r = filter_patch_rules(g);
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
