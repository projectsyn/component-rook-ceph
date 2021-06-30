local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local load_manifest(name) =
  std.parseJson(kap.yaml_load_stream(
    'rook-ceph/manifests/%s/%s.yaml' % [ params.images.rook.tag, name ]
  ));

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

local get_sc_config(type) =
  local cfg = com.getValueOrDefault(
    params.ceph_cluster.storage_classes,
    type,
    {}
  );
  com.makeMergeable(com.getValueOrDefault(cfg, 'config', {}));

local configure_sc(type, pool) =
  local obj = load_storageclass(type);
  local sc_config = get_sc_config(type);
  com.makeMergeable(obj) +
  sc.storageClass('%s-%s' % [ params.ceph_cluster.name, type ]) +
  sc_config +
  {
    provisioner: '%s.rbd.csi.ceph.com' % params.namespace,
    parameters+: {
      clusterID: params.ceph_cluster.namespace,
      pool: pool,
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
  local obj = load_snapclass(type);
  obj {
    parameters+: {
      clusterID: params.ceph_cluster.namespace,
      'csi.storage.k8s.io/snapshotter-secret-namespace': params.ceph_cluster.namespace,
    },
  };


{
  configure_storageclass: configure_sc,
  configure_snapshotclass: configure_snapclass,
}
