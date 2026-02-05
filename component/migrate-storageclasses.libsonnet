local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local name = 'migrate-rook-ceph-storageclasses';

local sa = kube.ServiceAccount(name) {
  metadata+: {
    namespace: params.namespace,
    annotations+: {
      'argocd.argoproj.io/hook': 'PreSync',
    },
  },
};

local clusterrole = kube.ClusterRole(name) {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/hook': 'PreSync',
    },
  },
  rules: [
    {
      apiGroups: [ 'storage.k8s.io' ],
      resources: [ 'storageclasses' ],
      verbs: [ 'get', 'list', 'watch', 'delete' ],
    },
  ],
};

local clusterrolebinding = kube.ClusterRoleBinding(name) {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/hook': 'PreSync',
    },
  },
  subjects_: [ sa ],
  roleRef_: clusterrole,
};

local job(scnames) = kube.Job(name) {
  metadata+: {
    namespace: params.namespace,
    annotations+: {
      'argocd.argoproj.io/hook': 'PreSync',
      'argocd.argoproj.io/hook-delete-policy': 'HookSucceeded',
    },
  },
  spec+: {
    template+: {
      spec+: {
        serviceAccountName: sa.metadata.name,
        containers_+: {
          patch_crds: kube.Container(name) {
            image: '%(registry)s/%(repository)s:%(tag)s' % params.images.oc,
            workingDir: '/home',
            command: [ 'bash', '-e', '-c' ],
            args: [
              |||
                for sc in $(jq -nr --argjson sc "${STORAGECLASSES}" '$sc[]'); do
                  sc_has_new_field=$(kubectl get storageclass "$sc" -oyaml | \
                    yq '.parameters|has("csi.storage.k8s.io/controller-publish-secret-name")')
                  if [ "$sc_has_new_field" == "false" ]; then
                    kubectl delete storageclass "$sc" --ignore-not-found=true;
                  fi
                done
              |||,
            ],
            env: [
              { name: 'HOME', value: '/home' },
              { name: 'STORAGECLASSES', value: std.manifestJsonMinified(scnames) },
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

local manifests(storageclasses) = [
  sa,
  clusterrole,
  clusterrolebinding,
  job(std.map(function(sc) sc.metadata.name, storageclasses)),
];

{
  manifests: manifests,
}
