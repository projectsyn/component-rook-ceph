local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local serviceaccounts = {
  [std.strReplace(suffix, '-', '_')]: kube.ServiceAccount('%s-%s' % [ params.ceph_cluster.name, suffix ]) {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
  }
  for suffix in [ 'osd', 'mgr', 'cmd-reporter' ]
};

local roles =
  if params.ceph_cluster.namespace != params.namespace then {
    osd: kube.Role('%s-osd' % params.ceph_cluster.name) {
      rules: [
        {
          apiGroups: [ '' ],
          resources: [ 'configmaps' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'update', 'delete' ],
        },
        {
          apiGroups: [ 'ceph.rook.io' ],
          resources: [ 'cephclusters', 'cephclusters/finalizers' ],
          verbs: [ 'get', 'list', 'create', 'update', 'delete' ],
        },
      ],
    },
    mgr: kube.Role('%s-mgr' % params.ceph_cluster.name) {
      rules: [
        {
          apiGroups: [ '' ],
          resources: [ 'pods', 'services', 'pods/log' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'update', 'delete' ],
        },
        {
          apiGroups: [ 'batch' ],
          resources: [ 'jobs' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'update', 'delete' ],
        },
        {
          apiGroups: [ 'ceph.rook.io' ],
          resources: [ '*' ],
          verbs: [ '*' ],
        },
      ],
    },
    cmd_reporter: kube.Role('%s-cmd-reporter' % params.ceph_cluster.name) {
      rules: [
        {
          apiGroups: [ '' ],
          resources: [ 'pods', 'configmaps' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'update', 'delete' ],
        },
      ],
    },
    monitoring: kube.Role('%s-monitoring' % params.ceph_cluster.name) {
      rules: [
        {
          apiGroups: [ 'monitoring.coreos.com' ],
          resources: [ 'servicemonitors', 'prometheusrules' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'update', 'delete' ],
        },
      ],
    },
  }
  else
    {};

local rolebindings = [
  // allow the operator to create resource in the cluster's namespace
  kube.RoleBinding('%s-cluster-mgmt' % params.ceph_cluster.name) {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'rook-ceph-cluster-mgmt',
    },
    subjects: [ {
      kind: 'ServiceAccount',
      name: 'rook-ceph-system',
      namespace: params.namespace,
    } ],
  },
  // allow the osd pods in the namespace to work with configmaps
  kube.RoleBinding('%s-osd' % params.ceph_cluster.name) {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    roleRef_:: roles.osd,
    subjects_:: [ serviceaccounts.osd ],
  },
  // Allow the ceph mgr to access the cluster-specific resources necessary for the mgr modules
  kube.RoleBinding('%s-mgr' % params.ceph_cluster.name) {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    roleRef_:: roles.mgr,
    subjects_:: [ serviceaccounts.mgr ],
  },
  // Allow the ceph mgr to access the rook system resources necessary for the mgr modules
  kube.RoleBinding('rook-ceph-mgr-system-%s' % params.ceph_cluster.name) {
    metadata+: {
      namespace: params.namespace,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'rook-ceph-mgr-system',
    },
    subjects_:: [ serviceaccounts.mgr ],
  },
  kube.RoleBinding('%s-cmd-reporter' % params.ceph_cluster.name) {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    roleRef_:: roles.cmd_reporter,
    subjects_:: [ serviceaccounts.cmd_reporter ],
  },
  // monitoring
  kube.RoleBinding('%s-monitoring' % params.ceph_cluster.name) {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    roleRef_:: roles.monitoring,
    subjects: [ {
      kind: 'ServiceAccount',
      name: 'rook-ceph-system',
      namespace: params.namespace,
    } ],
  },
];

local clusterrolebindings = [
  kube.ClusterRoleBinding('rook-ceph-mgr-cluster-%s' % params.ceph_cluster.name) {
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'rook-ceph-mgr-cluster',
    },
    subjects_:: [ serviceaccounts.mgr ],
  },
  kube.ClusterRoleBinding('rook-ceph-osd-%s' % params.ceph_cluster.name) {
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'rook-ceph-osd',
    },
    subjects_:: [ serviceaccounts.osd ],
  },
];

local objValues(o) = [ o[it] for it in std.objectFields(o) ];

local rbac =
  objValues(serviceaccounts) +
  objValues(roles) +
  rolebindings +
  clusterrolebindings;

local nodeAffinity = {
  nodeAffinity+: {
    requiredDuringSchedulingIgnoredDuringExecution+: {
      nodeSelectorTerms+: [ {
        matchExpressions+: [
          {
            key: label,
            operator: 'Exists',
          }
          for label in std.objectFields(params.node_selector)
        ],
      } ],
    },
  },
};

local cephcluster =
  kube._Object('ceph.rook.io/v1', 'CephCluster', params.ceph_cluster.name)
  {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    spec:
      {
        placement: {
          all: nodeAffinity,
        },
      }
      + com.makeMergeable(params.cephClusterSpec),
  };

local configmap =
  kube.ConfigMap('rook-config-override') {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    data: {
      // TODO
      config: '',
    },
  };

local toolbox =
  kube.Deployment('rook-ceph-tools')
  {
    metadata+: {
      namespace: params.ceph_cluster.namespace,
    },
    spec+: {
      template+: {
        spec+: {
          containers_:: {
            rook_ceph_tools: kube.Container('rook-ceph-tools') {
              image: '%(registry)s/%(image)s:%(tag)s' % params.toolbox.image,
              command: [ '/tini' ],
              args: [ '-g', '--', '/usr/local/bin/toolbox.sh' ],
              imagePullPolicy: 'IfNotPresent',
              env_:: {
                ROOK_CEPH_USERNAME: {
                  secretKeyRef: {
                    name: 'rook-ceph-mon',
                    key: 'ceph-username',
                  },
                },
                ROOK_CEPH_SECRET: {
                  secretKeyRef: {
                    name: 'rook-ceph-mon',
                    key: 'ceph-secret',
                  },
                },
              },
              volumeMounts_:: {
                ceph_config: { mountPath: '/etc/ceph' },
                mon_endpoint_volume: { mountPath: '/etc/rook' },
              },
            },
          },
          volumes_:: {
            mon_endpoint_volume: {
              configMap: {
                name: 'rook-ceph-mon-endpoints',
                items: [ {
                  key: 'data',
                  path: 'mon-endpoints',
                } ],
              },
            },
            ceph_config: {
              emptyDir: {},
            },
          },
          tolerations: params.tolerations,
          affinity: nodeAffinity,
        },
      },
    },
  };

{
  rbac: rbac,
  configmap: configmap,
  cluster: cephcluster,
  toolbox: toolbox,
}
