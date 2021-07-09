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

// Upstream alerts to ignore
local ignore_alerts = [
  // Drop CephNodeDown alert, we already have plenty of alerts for
  // unresponsive nodes.
  'CephNodeDown',
];

// Alert rule patches.
// Provide partial objects for alert rules that need to be tuned compared to
// upstream. The keys in this object correspond to the `alert` field of the
// rule for which the patch is intended.
local patch_alerts = {
  CephClusterWarningState: {
    'for': '15m',
  },
  CephOSDDiskNotResponding: {
    'for': '5m',
  },
};

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
  local ignore_set = std.set(global_alert_params.ignoreNames + ignore_alerts);
  g {
    rules: std.map(
      // Patch rules to make sure they match the requirements.
      function(rule)
        local rulepatch = com.getValueOrDefault(patch_alerts, rule.alert, {});
        rule {
          // Change alert names so we don't get multiple alerts with the same
          // name, as the rook-ceph operator deploys its own copy of these
          // rules.
          alert: 'SYN_%s' % super.alert,
          // add customAnnotations configured for all alerts on cluster
          annotations+: global_alert_params.customAnnotations,
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
