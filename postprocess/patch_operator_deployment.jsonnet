local com = import 'lib/commodore.libjsonnet';

local deployment_file = std.extVar('output_path') + '/deployment.yaml';

local deployment = com.yaml_load(deployment_file) + {
  spec+: {
    template+: {
      spec+: {
        containers: [
          if c.name == 'rook-ceph-operator' then
            c {
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
