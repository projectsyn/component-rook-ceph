local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local on_openshift =
  inv.parameters.facts.distribution == 'openshift4';

local cephcluster = import 'cephcluster.libsonnet';

local ns_config = {
  metadata+: {
    annotations+: {
      // allow all nodes -> CSI plugins need to run everywhere
      'openshift.io/node-selector': '',
    },
  },
};

local ocp_config = import 'openshift.libsonnet';

{
  '00_namespaces': [
    kube.Namespace(params.namespace) + ns_config,
    kube.Namespace(params.ceph_cluster.namespace) + ns_config,
  ],
  [if on_openshift then '02_openshift_sccs']: ocp_config.sccs,
  '10_cephcluster_rbac': cephcluster.rbac,
  '10_cephcluster_configoverride': cephcluster.configmap,
  '10_cephcluster_cluster': cephcluster.cluster,
  '10_cephcluster_toolbox': cephcluster.toolbox,
}
