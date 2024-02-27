local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local serviceaccount = kube.ServiceAccount('holder-updater') {
  metadata+: {
    namespace: params.namespace,
  },
};

local rbac = [
  serviceaccount,
  kube.RoleBinding('holder-updater-admin') {
    metadata+: {
      namespace: params.namespace,
    },
    roleRef: {
      kind: 'ClusterRole',
      name: 'admin',
    },
    subjects_: [ serviceaccount ],
  },
  kube.ClusterRoleBinding('syn:rook-ceph:holder-updater-cluster-reader') {
    roleRef: {
      kind: 'ClusterRole',
      name: 'cluster-reader',
    },
    subjects_: [ serviceaccount ],
  },
];

local script = |||
  #!/bin/sh
  trap : TERM INT
  sleep infinity &

  while true; do
    # assumption: holder plugin daemonset is called
    # `csi-cephfsplugin-holder-${cephcluster:name}`
    # note: we don't care about the value of the variable if the daemonset
    # isn't there, since we'll check for pods in a K8s `List` which will
    # simply be empty if the plugin isn't enabled.
    cephfs_holder_wanted_gen=$(kubectl get ds csi-cephfsplugin-holder-%(cephcluster_name)s -ojsonpath='{.metadata.generation}' 2>/dev/null)
    rbd_holder_wanted_gen=$(kubectl get ds csi-rbdplugin-holder-%(cephcluster_name)s -ojsonpath='{.metadata.generation}' 2>/dev/null)
    needs_update=$( (\
      kubectl get pods -l app=csi-cephfsplugin-holder --field-selector spec.nodeName=${NODE_NAME} -ojson |\
        jq --arg wanted_gen ${cephfs_holder_wanted_gen} \
          -r '.items[] | select(.metadata.labels."pod-template-generation" != $wanted_gen) | .metadata.name'
      kubectl get pods -l app=csi-rbdplugin-holder --field-selector spec.nodeName=${NODE_NAME} -ojson |\
        jq --arg wanted_gen ${rbd_holder_wanted_gen} \
          -r '.items[] | select(.metadata.labels."pod-template-generation" != $wanted_gen) | .metadata.name'
    ) | wc -l)
    if [ $needs_update -eq 0 ]; then
      echo "No holder pods with outdated pod generation, nothing to do"
      break
    fi
    non_ds_pods=$(kubectl get pods -A --field-selector spec.nodeName=${NODE_NAME} -ojson | \
      jq -r '.items[] | select(.metadata.ownerReferences[0].kind!="DaemonSet") | .metadata.name' | wc -l)
    if [ $non_ds_pods -eq 0 ]; then
      echo "node ${NODE_NAME} drained, deleting Ceph CSI holder pods"
      kubectl delete pods -l app=csi-cephfsplugin-holder --field-selector=spec.nodeName=${NODE_NAME}
      kubectl delete pods -l app=csi-rbdplugin-holder --field-selector=spec.nodeName=${NODE_NAME}
      break
    else
      echo "${non_ds_pods} non-daemonset pods still on node ${NODE_NAME}, sleeping for 5s"
    fi
    sleep 5
  done
  echo "script completed, sleeping"
  wait
||| % { cephcluster_name: params.ceph_cluster.name };

local configmap = kube.ConfigMap('holder-restart-script') {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    'wait-and-delete-holder-pods.sh': script,
  },
};

local daemonset = kube.DaemonSet('syn-holder-updater') {
  metadata+: {
    annotations+: {
      'syn.tools/description':
        'DaemonSet which waits for node to be drained (by waiting until no ' +
        'non-daemonset pods are running on the node) and then deletes any ' +
        'outdated csi holder pods. Outdated holder pods are identified by ' +
        'comparing the DaemonSet generation with the pod generation.',
      // set sync wave 10 for the daemonset to ensure that the ConfigMap is
      // updated first.
      'argocd.argoproj.io/sync-wave': '10',
    },
    namespace: params.namespace,
  },
  spec+: {
    template+: {
      metadata+: {
        annotations+: {
          'script-checksum': std.md5(script),
        },
      },
      spec+: {
        serviceAccountName: serviceaccount.metadata.name,
        containers_: {
          update: kube.Container('update') {
            image: '%(registry)s/%(image)s:%(tag)s' % params.images.kubectl,
            command: [ '/scripts/wait-and-delete-holder-pods.sh' ],
            env_: {
              NODE_NAME: {
                fieldRef: {
                  fieldPath: 'spec.nodeName',
                },
              },
            },
            // The script doesn't consume any resources once it's determined
            // that nothing is left to do, but before then, we do consume a
            // bit of resources. We're setting modest requests, and no limits
            // to avoid running into issues because the script gets throttled
            // due to CPU limits.
            resources: {
              requests: {
                cpu: '5m',
                memory: '20Mi',
              },
            },
            volumeMounts_: {
              scripts: {
                mountPath: '/scripts',
              },
            },
          },
        },
        volumes_: {
          scripts: {
            configMap: {
              name: configmap.metadata.name,
              defaultMode: 504,  // 0770
            },
          },
        },
      },
    },
  },
};

rbac + [
  configmap,
  daemonset,
]
