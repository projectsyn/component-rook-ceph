local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local helpers = import 'helpers.libsonnet';

local ocp_role = helpers.metrics_role(params.namespace);

local rbac =
  if helpers.on_openshift then [
    ocp_role,
    helpers.ocp_metrics_rolebinding(
      params.namespace,
      ocp_role
    ),
  ]
  else
    [];

local sm_manifest = helpers.load_manifest('csi-metrics-service-monitor');
assert std.length(sm_manifest) >= 1;
local sm = std.filter(
  function(it) it.kind == 'ServiceMonitor',
  sm_manifest
);
assert std.length(sm) > 0;

local wantGrpcMetrics =
  params.operator_helm_values.csi.enableGrpcMetrics;

local servicemonitor = [
  sm[0] {
    metadata+: {
      namespace: params.namespace,
    },
    spec+: {
      namespaceSelector: {
        matchNames: [ params.namespace ],
      },
      endpoints: std.filter(
        function(it) it != null,
        [
          // keep endpoints entries if either they don't refer to grpc
          // metrics or we want grpc metrics.
          if (ep.port != 'csi-grpc-metrics' || wantGrpcMetrics) then
            ep
          else
            null
          for ep in sm[0].spec.endpoints
        ]
      ),
    },
  },
];

{
  rbac: rbac,
  servicemonitor: servicemonitor,
}
