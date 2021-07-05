local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.rook_ceph;

// Automatically set ROOK_HOSTPATH_REQUIRES_PRIVILEGED=true on OCP4
// TODO: this should be set to true whenever SElinux is enabled on the
// cluster hosts.
// Respect user-provided configuration via `operator_helm_values` on
// distributions other than OCP4.
local hostpath_requires_privileged =
  if inv.parameters.facts.distribution == 'openshift4' then
    true
  else
    com.getValueOrDefault(
      params.operator_helm_values,
      'hostpathRequiresPrivileged',
      false,
    );

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
                else if e.name == 'ROOK_HOSTPATH_REQUIRES_PRIVILEGED' then
                  e {
                    value: '%s' % hostpath_requires_privileged,
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
