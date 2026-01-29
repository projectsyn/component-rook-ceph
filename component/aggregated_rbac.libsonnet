local kube = import 'lib/kube.libjsonnet';

local custom_resources = [
  {
    apiGroups: [ 'ceph.rook.io' ],
    resources: [
      'cephblockpoolradosnamespaces',
      'cephblockpools',
      'cephbucketnotifications',
      'cephbuckettopics',
      'cephclients',
      'cephclusters',
      'cephfilesystemmirrors',
      'cephfilesystems',
      'cephfilesystemsubvolumegroups',
      'cephnfss',
      'cephobjectrealms',
      'cephobjectstores',
      'cephobjectstoreusers',
      'cephobjectzonegroups',
      'cephobjectzones',
      'cephrbdmirrors',
    ],
  },
  {
    apiGroups: [ 'objectbucket.io' ],
    resources: [
      'objectbucketclaims',
      'objectbuckets',
    ],
  },
];

local cluster_roles = [
  // Only aggregate Rook CRD permissions to cluster-reader. We don't really
  // want regular users to have permissions to create any Rook CRDs in their
  // namespaces. This may not work out of the box on K8s distributions other
  // than OpenShift 4.
  // We don't need to worry about aggregating write permissions, since the
  // cluster-admin-style ClusterRoles usually grant blanket permissions on
  // all resources (apiGroups=['*'],resources=['*'],verbs=['*']).
  kube.ClusterRole('rook-ceph-cluster-reader') {
    metadata+: {
      labels+: {
        'rbac.authorization.k8s.io/aggregate-to-cluster-reader': 'true',
      },
    },
    rules: [
      cr {
        verbs: [
          'get',
          'list',
          'watch',
        ],
      }
      for cr in custom_resources
    ],
  },
];


{
  cluster_roles: cluster_roles,
}
