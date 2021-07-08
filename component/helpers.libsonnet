local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local metrics_role(namespace) =
  kube.Role('rook-ceph-metrics') {
    metadata+: {
      namespace: namespace,
    },
    rules: [
      {
        apiGroups: [ '' ],
        resources: [ 'services', 'endpoints', 'pods' ],
        verbs: [ 'get', 'list', 'watch' ],
      },
    ],
  };

local ocp_metrics_rolebinding(namespace, metrics_role) =
  kube.RoleBinding('rook-ceph-metrics') {
    metadata+: {
      namespace: namespace,
    },
    roleRef_:: metrics_role,
    subjects: [ {
      kind: 'ServiceAccount',
      name: 'prometheus-k8s',
      namespace: 'openshift-monitoring',
    } ],
  };

{
  metrics_role: metrics_role,
  ocp_metrics_rolebinding: ocp_metrics_rolebinding,
}
