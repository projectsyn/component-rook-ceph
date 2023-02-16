local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local load_manifest(name) =
  std.parseJson(kap.yaml_load_stream(
    '%s/manifests/%s/%s.yaml' % [
      inv.parameters._base_directory,
      params.images.rook.tag,
      name,
    ]
  ));

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

local nodeAffinity = {
  nodeAffinity+: {
    requiredDuringSchedulingIgnoredDuringExecution+: {
      nodeSelectorTerms+: [ {
        matchExpressions+: [
          {
            key: label,
            operator: 'Exists',
          }
          for label in std.objectFields(params.node_selector)
        ],
      } ],
    },
  },
};

{
  load_manifest: load_manifest,
  metrics_role: metrics_role,
  ocp_metrics_rolebinding: ocp_metrics_rolebinding,
  nodeAffinity: nodeAffinity,
}
