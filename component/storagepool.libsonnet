local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local helpers = import 'helpers.libsonnet';
local load_manifest = helpers.load_manifest;

local load_storageclass(type) =
  // load yaml
  local manifest = load_manifest('%s-storageclass' % type);
  assert std.length(manifest) >= 1;
  // find storageclass manifest in loaded yaml
  local sc = std.prune([
    if it.kind == 'StorageClass' then it
    for it in manifest
  ]);
  assert std.length(sc) == 1;
  // return storageclass
  sc[0];

local get_sc_config(type, pool) =
  assert std.objectHas(params.ceph_cluster.storage_pools, type);
  assert std.objectHas(
    params.ceph_cluster.storage_pools[type], pool
  );
  com.makeMergeable(com.getValueOrDefault(
    params.ceph_cluster.storage_pools[type][pool],
    'storage_class_config',
    {}
  ));

// subpool used for CephFS
local configure_sc(type, pool, subpool=null) =
  local obj = load_storageclass(type);
  local sc_config = get_sc_config(type, pool);
  com.makeMergeable(obj) +
  sc.storageClass(
    '%s-%s-%s' % [ type, pool, params.ceph_cluster.name ]
  ) +
  sc_config +
  {
    provisioner: '%s.%s.csi.ceph.com' % [ params.namespace, type ],
    parameters+: {
      clusterID: params.ceph_cluster.namespace,
      pool:
        if subpool != null then
          subpool
        else
          pool,
      'csi.storage.k8s.io/provisioner-secret-namespace':
        params.ceph_cluster.namespace,
      'csi.storage.k8s.io/controller-expand-secret-namespace':
        params.ceph_cluster.namespace,
      'csi.storage.k8s.io/node-stage-secret-namespace':
        params.ceph_cluster.namespace,
    },
  };


local load_snapclass(type) =
  local manifest = load_manifest('%s-snapshotclass' % type);
  assert std.length(manifest) == 1;
  manifest[0];

local configure_snapclass(type) =
  local name = if type == 'rbd' then
    'rook-ceph-rbd-%s' % params.ceph_cluster.name
  else if type == 'cephfs' then
    'rook-cephfs-%s' % params.ceph_cluster.name
  else
    error "unknown snapshotclass type '%s'" % type;

  local obj = load_snapclass(type);
  obj {
    metadata+: {
      name: name,
    },
    driver: '%s.%s.csi.ceph.com' % [ params.namespace, type ],
    parameters+: {
      clusterID: params.ceph_cluster.namespace,
      'csi.storage.k8s.io/snapshotter-secret-namespace': params.ceph_cluster.namespace,
    },
  };


{
  configure_storageclass: configure_sc,
  configure_snapshotclass: configure_snapclass,
}
