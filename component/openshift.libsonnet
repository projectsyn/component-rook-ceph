local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local sccServiceAccountList(accts, namespace) =
  [
    'system:serviceaccount:%s:%s' % [ namespace, sa ]
    for sa in accts
  ];

local helpers = import 'helpers.libsonnet';
local load_manifest = helpers.load_manifest;

local ocpOperatorManifests = load_manifest('operator-openshift');
local sccManifests = std.filter(
  function(it) it != null,
  [
    if m.kind == 'SecurityContextConstraints' then m
    for m in ocpOperatorManifests
  ]
);

local patches = {
  'rook-ceph': {
    // Allow hostNetwork and hostPorts since we run the OSDs in host
    // networking mode.
    allowHostNetwork: true,
    allowHostPorts: true,
    users:
      [
        'system:serviceaccount:%s:rook-ceph-system' % params.namespace,
      ] +
      sccServiceAccountList([
        'default',
        'rook-ceph-default',
        'rook-ceph-mgr',
        'rook-ceph-osd',
      ], params.ceph_cluster.namespace),
  },
  'rook-ceph-csi': {
    users:
      sccServiceAccountList([
        'rook-csi-rbd-plugin-sa',
        'rook-csi-rbd-provisioner-sa',
        'rook-csi-cephfs-plugin-sa',
        'rook-csi-cephfs-provisioner-sa',
        'ceph-csi-cephfs-ctrlplugin-sa',
        'ceph-csi-cephfs-nodeplugin-sa',
        'ceph-csi-rbd-ctrlplugin-sa',
        'ceph-csi-rbd-nodeplugin-sa',
        // Rook v1.9 adds "holder" DaemonSets for the CSI plugins which run
        // with the default serviceaccount, so we need to also allow the
        // default serviceaccount in the namespace access to the rook-ceph-csi
        // SCC.
        'default',
      ], params.namespace),
  },
};

{
  sccs: std.map(
    function(scc) scc + patches[scc.metadata.name] + {
      // Otherwise ArgoCD may get confused because the volume list is getting
      // sorted after the manifests are applied.
      volumes: std.sort(super.volumes),
    },
    sccManifests
  ),
}
