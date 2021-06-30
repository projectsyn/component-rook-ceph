local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local sc = import 'lib/storageclass.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local sp = import 'storagepool.libsonnet';

local cephfs_pool =
  kube._Object(
    'ceph.rook.io/v1',
    'CephFilesystem',
    '%s-cephfs' % params.ceph_cluster.name
  ) {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    spec: {
      metadataPool: {
        replicated: {
          size: 3,
          requireSafeReplicaSize: true,
        },
      },
      parameters: {
        compression_mode: 'none',
      },
      dataPools: [ {
        failureDomain: 'host',
        replicated: {
          size: 3,
          requireSafeReplicaSize: true,
        },
        parameters: {
          compression_mode: 'none',
        },
      } ],
      preserveFilesystemOnDelete: true,
      metadataServer: {
        activeCount: 1,
        activeStandby: true,
        placement: {
          podAntiAffinity: {
            requiredDuringSchedulingIgnoredDuringExecution: [ {
              labelSelector: [ {
                matchExpressions: [ {
                  key: 'app',
                  operator: 'In',
                  values: [ 'rook-ceph-mds' ],
                } ],
              } ],
              topologyKey: 'kubernetes.io/hostname',
            } ],
            preferredDuringSchedulingIgnoredDuringExecution: [ {
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
      mirroring: {
        enabled: false,
      },
    },
  };

local cephfs_storageclass =
  sp.configure_storageclass('cephfs', cephfs_pool.metadata.name);
local cephfs_snapclass =
  sp.configure_snapshotclass('cephfs');

{
  storagepool: cephfs_pool,
  storageclass: cephfs_storageclass,
  snapshotclass: cephfs_snapclass,
}
