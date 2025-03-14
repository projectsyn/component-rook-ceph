local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.rook_ceph;

// Automatically set ROOK_HOSTPATH_REQUIRES_PRIVILEGED=true on OCP4
// TODO: this should be set to true whenever SElinux is enabled on the
// cluster hosts.
// Respect user-provided configuration via `operator_helm_values` on
// distributions other than OCP4.
local hostpath_requires_privileged =
  if std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution) then
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
                if e.name == 'ROOK_HOSTPATH_REQUIRES_PRIVILEGED' then
                  e {
                    value: '%s' % hostpath_requires_privileged,
                  }
                else
                  e
                for e in super.env
              ],
            }
          else
            c
          for c in super.containers
        ],
      },
    },
  },
};


{
  deployment: deployment,
}
