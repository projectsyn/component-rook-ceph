local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local sccServiceAccountList(accts, namespace) =
  [
    'system:serviceaccount:%s:%s' % [ namespace, sa ]
    for sa in accts
  ];

local sccs = [
  kube._Object(
    'security.openshift.io/v1',
    'SecurityContextConstraints',
    'rook-ceph'
  )
  {
    allowPrivilegedContainer: true,
    allowHostNetwork: true,
    allowHostDirVolumePlugin: true,
    allowedCapabilities: [],
    allowHostPorts: true,
    allowHostPID: true,
    allowHostIPC: true,
    readOnlyRootFilesystem: false,
    requiredDropCapabilities: [],
    defaultAddCapabilities: [],
    runAsUser: {
      type: 'RunAsAny',
    },
    seLinuxContext: {
      type: 'MustRunAs',
    },
    fsGroup: {
      type: 'MustRunAs',
    },
    supplementalGroups: {
      type: 'RunAsAny',
    },
    allowedFlexVolumes: [
      { driver: 'ceph.rook.io/rook' },
      { driver: 'ceph.rook.io/rook-ceph' },
    ],
    volumes: [
      'configMap',
      'downwardAPI',
      'emptyDir',
      'flexVolume',
      'hostPath',
      'persistentVolumeClaim',
      'projected',
      'secret',
    ],
    users:
      [
        'system:serviceaccount:%s:rook-ceph-system' % params.namespace,
      ] +
      sccServiceAccountList([
        'default',
        'rook-ceph-mgr',
        'rook-ceph-osd',
      ], params.ceph_cluster.namespace),
  },
  kube._Object(
    'security.openshift.io/v1',
    'SecurityContextConstraints',
    'rook-ceph-csi'
  )
  {
    allowPrivilegedContainer: true,
    allowHostNetwork: true,
    allowHostDirVolumePlugin: true,
    allowedCapabilities: [ '*' ],
    allowHostPorts: true,
    allowHostPID: true,
    allowHostIPC: true,
    readOnlyRootFilesystem: false,
    requiredDropCapabilities: [],
    defaultAddCapabilities: [],
    runAsUser: {
      type: 'RunAsAny',
    },
    seLinuxContext: {
      type: 'RunAsAny',
    },
    fsGroup: {
      type: 'RunAsAny',
    },
    supplementalGroups: {
      type: 'RunAsAny',
    },
    allowedFlexVolumes: [
      { driver: 'ceph.rook.io/rook' },
      { driver: 'ceph.rook.io/rook-ceph' },
    ],
    volumes: [ '*' ],
    users: sccServiceAccountList([
      'rook-csi-rbd-plugin-sa',
      'rook-csi-rbd-provisioner-sa',
      'rook-csi-cephfs-plugin-sa',
      'rook-csi-cephfs-provisioner-sa',
    ], params.namespace),
  },
];

{
  sccs: sccs,
}
