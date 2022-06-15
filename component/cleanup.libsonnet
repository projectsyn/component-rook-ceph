local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local name = 'cleanup-alertrules';
local namespace = params.ceph_cluster.namespace;

local ruleToClean = 'prometheus-ceph-v16-rules';

local role = kube.Role(name) {
  metadata+: { namespace: namespace },
  rules: [
    {
      apiGroups: [ 'monitoring.coreos.com' ],
      resources: [ 'prometheusrules' ],
      verbs: [ 'delete' ],
    },
  ],
};

local serviceAccount = kube.ServiceAccount(name) {
  metadata+: { namespace: namespace },
};

local roleBinding = kube.RoleBinding(name) {
  metadata+: { namespace: namespace },
  subjects_: [ serviceAccount ],
  roleRef_: role,
};

local job = kube.Job(name) {
  metadata+: {
    namespace: namespace,
    annotations+: {
      'argocd.argoproj.io/hook': 'Sync',
      'argocd.argoproj.io/hook-delete-policy': 'HookSucceeded',
    },
  },
  spec+: {
    template+: {
      spec+: {
        serviceAccountName: serviceAccount.metadata.name,
        containers_+: {
          patch_crds: kube.Container(name) {
            image: '%(registry)s/%(image)s:%(tag)s' % params.images.kubectl,
            workingDir: '/home',
            command: [ 'kubectl' ],
            args: [
              '-n',
              namespace,
              'delete',
              '--ignore-not-found',
              'prometheusrules.monitoring.coreos.com',
              ruleToClean,
            ],
            env: [
              { name: 'HOME', value: '/home' },
            ],
            volumeMounts: [
              { name: 'home', mountPath: '/home' },
            ],
          },
        },
        volumes+: [
          { name: 'home', emptyDir: {} },
        ],
      },
    },
  },
};

[ role, serviceAccount, roleBinding, job ]
