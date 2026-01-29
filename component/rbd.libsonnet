local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local sp = import 'storagepool.libsonnet';

local rbd_params = params.ceph_cluster.storage_pools.rbd;

local rbd_blockpools = std.prune([
  kube._Object('ceph.rook.io/v1', 'CephBlockPool', name) {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    spec: com.makeMergeable(
      com.getValueOrDefault(
        params.ceph_cluster.storage_pools.rbd[name],
        'config',
        {}
      )
    ),
  }
  for name in std.objectFields(rbd_params)
]);

local rbd_storageclasses = [
  sp.configure_storageclass('rbd', name)
  for name in std.objectFields(rbd_params)
] + [
  sp.configure_storageclass('rbd', name, suffix=suffix)
  for name in std.objectFields(rbd_params)
  for suffix in std.objectFields(
    std.get(rbd_params[name], 'extra_storage_classes', {})
  )
];

local rbd_snapclass = [
  sp.configure_snapshotclass('rbd'),
];

if params.ceph_cluster.rbd_enabled then {
  storagepools: rbd_blockpools,
  storageclasses: rbd_storageclasses,
  snapshotclass: rbd_snapclass,
} else {
  storagepools: [],
  storageclasses: [],
  snapshotclass: [],
}
