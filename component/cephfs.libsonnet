local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local sp = import 'storagepool.libsonnet';

local cephfs_params = params.ceph_cluster.storage_pools.cephfs;

local metadataServerPlacement = {
  spec+: {
    metadataServer+: {
      placement+: {
        podAntiAffinity+: {
          requiredDuringSchedulingIgnoredDuringExecution+: [ {
            labelSelector: [ {
              matchExpressions: [ {
                key: 'app',
                operator: 'In',
                values: [ 'rook-ceph-mds' ],
              } ],
            } ],
            topologyKey: 'kubernetes.io/hostname',
          } ],
          preferredDuringSchedulingIgnoredDuringExecution+: [ {
            weight: 100,
            podAffinityTerm: {
              labelSelector: {
                matchExpressions: [ {
                  key: 'app',
                  operator: 'In',
                  values: [ 'rook-ceph-mds' ],
                } ],
                topologyKey: 'topology.kubernetes.io/zone',
              },
            },
          } ],
        },
      },
    },
  },
};

// Users are responsible for providing working cephfs configs, we don't
// verify them here
local cephfs_pools = [
  kube._Object(
    'ceph.rook.io/v1',
    'CephFilesystem',
    '%s-cephfs' % params.ceph_cluster.name
  ) {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
  } +
  metadataServerPlacement +
  {
    spec+:
      com.makeMergeable(
        com.getValueOrDefault(
          cephfs_params[pool],
          'config',
          {}
        )
      ),
  } +
  {
    spec+: {
      // overwrite datapools setup by user -> documentation clearly states
      // to configure dataPools in params.data_pools.
      dataPools: [
        cephfs_params[pool].data_pools[pn]
        for pn in std.objectFields(cephfs_params[pool].data_pools)
      ],
    },
  }
  for pool in std.objectFields(cephfs_params)
];

local cephfs_storageclasses = [
  sp.configure_storageclass('cephfs', pool)
  for pool in std.objectFields(cephfs_params)
];
local cephfs_snapclasses = [
  sp.configure_snapshotclass('cephfs', pool)
  for pool in std.objectFields(cephfs_params)
];

if params.ceph_cluster.cephfs_enabled then {
  storagepools: cephfs_pools,
  storageclasses: cephfs_storageclasses,
  snapshotclasses: cephfs_snapclasses,
} else {
  storagepools: [],
  storageclasses: [],
  snapshotclasses: [],
}
