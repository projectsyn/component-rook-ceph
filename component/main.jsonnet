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

local namespaces =
  [
    kube.Namespace(params.namespace) + ns_config,
  ] +
  if params.ceph_cluster.namespace != params.namespace then
    [
      kube.Namespace(params.ceph_cluster.namespace) + ns_config,
    ]
  else [];

{
  '00_namespaces': namespaces,
  [if on_openshift then '02_openshift_sccs']: ocp_config.sccs,
  '10_cephcluster_rbac': cephcluster.rbac,
  '10_cephcluster_configoverride': cephcluster.configmap,
  '10_cephcluster_cluster': cephcluster.cluster,
  [if params.toolbox.enabled then '10_cephcluster_toolbox']: cephcluster.toolbox,
  '20_storagepools':
    rbd_config.storagepools +
    cephfs_config.storagepools,
  '30_storageclasses':
    rbd_config.storageclasses +
    cephfs_config.storageclasses,
  '30_snapshotclasses':
    rbd_config.snapshotclasses +
    cephfs_config.snapshotclasses,
}
