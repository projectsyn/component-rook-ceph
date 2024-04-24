local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local on_openshift =
  inv.parameters.facts.distribution == 'openshift4';

local cephcluster = import 'cephcluster.libsonnet';

local ns_config =
  if on_openshift then {
    metadata+: {
      annotations+: {
        // set node selector to allow pods to be scheduled on all nodes -> CSI
        // plugins need to run everywhere
        'openshift.io/node-selector': '',
      },
      labels+: {
        // Configure the namespaces so that the OCP4 cluster-monitoring
        // Prometheus can find the servicemonitors and rules.
        'openshift.io/cluster-monitoring': 'true',
      },
    },
  }
  else
    {};

local ocp_config = import 'openshift.libsonnet';

local rbd_config = import 'rbd.libsonnet';
local cephfs_config = import 'cephfs.libsonnet';

local csi_metrics = import 'csi_metrics.libsonnet';

local alert_rules = import 'alertrules.libsonnet';

local aggregated_rbac = import 'aggregated_rbac.libsonnet';

local namespaces =
  [
    kube.Namespace(params.namespace) + ns_config,
  ] +
  if params.ceph_cluster.namespace != params.namespace then
    [
      kube.Namespace(params.ceph_cluster.namespace) + ns_config,
    ]
  else [];

local common_labels(name) = {
  'app.kubernetes.io/name': std.strReplace(name, ':', '-'),
  'app.kubernetes.io/managed-by': 'commodore',
  'app.kubernetes.io/component': 'rook-ceph',
};

// This is required for Rook 1.10.0-1.10.11, cf.
// https://github.com/rook/rook/pull/11697
// NOTE(sg): We keep the workaround for now even though we default to Rook
// 1.10.13 which fixes the permissions, to allow users to stay on lower 1.10
// versions for the moment.
local cephfs_rbac_fix =
  local cephfs_additional_role =
    kube.ClusterRole('syn-rook-ceph-cephfs-provisioner-fix') {
      rules: [
        {
          apiGroups: [ '' ],
          resources: [ 'nodes' ],
          verbs: [ 'get' ],
        },
      ],
    };
  [
    cephfs_additional_role,
    kube.ClusterRoleBinding('syn-rook-ceph-cephfs-provisioner-fix') {
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'rook-csi-cephfs-provisioner-sa',
          namespace: params.namespace,
        },
      ],
      roleRef_:: cephfs_additional_role,
    },
  ];

local add_labels(manifests) = [
  manifest {
    metadata+: {
      labels+: common_labels(super.name),
    },
  }
  for manifest in manifests
];


std.mapWithKey(
  function(field, value)
    if std.isArray(value) then
      add_labels(value)
    else
      value {
        metadata+: {
          labels+: common_labels(super.name),
        },
      },
  {
    '00_namespaces': namespaces,
    '01_aggregated_rbac': aggregated_rbac.cluster_roles,
    [if on_openshift then '02_openshift_sccs']: ocp_config.sccs,
    '03_rbac_fixes': cephfs_rbac_fix,
    '10_cephcluster_rbac': cephcluster.rbac,
    '10_cephcluster_configoverride': cephcluster.configmap,
    '10_cephcluster_cluster': cephcluster.cluster,
    [if params.toolbox.enabled then '10_cephcluster_toolbox']:
      cephcluster.toolbox,
    '20_storagepools':
      rbd_config.storagepools +
      cephfs_config.storagepools,
    '30_storageclasses':
      rbd_config.storageclasses +
      cephfs_config.storageclasses,
    '30_snapshotclasses':
      rbd_config.snapshotclass +
      cephfs_config.snapshotclass,
    '40_csi_driver_metrics':
      csi_metrics.rbac +
      csi_metrics.servicemonitor,
    [if params.ceph_cluster.monitoring_enabled then '40_alertrules']:
      alert_rules.rules,
    '99_cleanup': (import 'cleanup.libsonnet'),
  }
)
