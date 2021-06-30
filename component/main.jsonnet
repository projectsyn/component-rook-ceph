local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local cephcluster = import 'cephcluster.libsonnet';

{
  '00_namespaces': [
    kube.Namespace(params.namespace),
    kube.Namespace(params.ceph_cluster.namespace),
  ],
  '10_cephcluster_rbac': cephcluster.rbac,
  '10_cephcluster_configoverride': cephcluster.configmap,
  '10_cephcluster_cluster': cephcluster.cluster,
  '10_cephcluster_toolbox': cephcluster.toolbox,
}
