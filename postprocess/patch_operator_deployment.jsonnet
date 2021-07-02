local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.rook_ceph;

local deployment_file = std.extVar('output_path') + '/deployment.yaml';

local deployment = com.yaml_load(deployment_file) + {
  spec+: {
    template+: {
      spec+: {
        containers: [
          if c.name == 'rook-ceph-operator' then
            c {
              env: [
                if e.name == 'ROOK_CSI_ENABLE_RBD' then
                  e {
                    value: '%s' % params.ceph_cluster.rbd_enabled,
                  }
                else if e.name == 'ROOK_CSI_ENABLE_CEPHFS' then
                  e {
                    value: '%s' % params.ceph_cluster.cephfs_enabled,
                  }
                else
                  e
                for e in super.env
              ],
              volumeMounts+: [
                {
                  mountPath: '/var/lib/rook',
                  name: 'rook-config',
                },
                {
                  mountPath: '/etc/ceph',
                  name: 'default-config-dir',
                },
              ],
            }
          else
            c
          for c in super.containers
        ],
        volumes+: [
          {
            name: 'rook-config',
            emptyDir: {},
          },
          {
            name: 'default-config-dir',
            emptyDir: {},
          },
        ],
      },
    },
  },
};


{
  deployment: deployment,
}
