local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local sp = import 'storagepool.libsonnet';

local rbd_blockpool =
  kube._Object('ceph.rook.io/v1', 'CephBlockPool', 'storagepool') {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    spec: {
      failureDomain: 'host',
      replicated: {
        size: 3,
        requireSafeReplicaSize: true,
      },
    },
  };

local rbd_storageclass =
  sp.configure_storageclass('rbd', rbd_blockpool.metadata.name);
local rbd_snapclass =
  sp.configure_snapshotclass('rbd');

if params.ceph_cluster.storage_classes.rbd.enabled then {
  storagepool: rbd_blockpool,
  storageclass: rbd_storageclass,
  snapshotclass: rbd_snapclass,
} else {
  storagepool: null,
  storageclass: null,
  snapshotclass: null,
}
