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
      // objectbuckets are cluster-scoped, see below
    ],
  },
];

local verbs = {
  'rook-ceph-view': [
    'get',
    'list',
    'watch',
  ],
  'rook-ceph-edit': [
    'create',
    'delete',
    'deletecollection',
    'patch',
    'update',
  ],
};

local cluster_roles =
  [
    kube.ClusterRole(name) {
      metadata+: {
        labels+:
          {
            'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
            'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
          } +
          if name == 'rook-ceph-view' then
            {
              'rbac.authorization.k8s.io/aggregate-to-view': 'true',
            }
          else {},
      },
      rules: [
        cr {
          verbs: verbs[name],
        }
        for cr in custom_resources
      ],
    }
    for name in [ 'rook-ceph-view', 'rook-ceph-edit' ]
  ] +
  [
    // Only aggregate view permissions for objectbuckets which are
    // cluster-scoped to cluster-reader.
    // This may not work out of the box on K8s distributions other than
    // OpenShift 4.
    kube.ClusterRole('rook-ceph-cluster-reader') {
      metadata+: {
        labels+: {
          'rbac.authorization.k8s.io/aggregate-to-cluster-reader': 'true',
        },
      },
      rules: [
        {
          apiGroups: [ 'objectbucket.io' ],
          resources: [ 'objectbuckets' ],
          verbs: verbs['rook-ceph-view'],
        },
      ],
    },
  ];


{
  cluster_roles: cluster_roles,
}
