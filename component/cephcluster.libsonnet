local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;

local helpers = import 'helpers.libsonnet';

local on_openshift = inv.parameters.facts.distribution == 'openshift4';

local serviceaccounts =
  if params.ceph_cluster.namespace != params.namespace then {
    [std.strReplace(suffix, '-', '_')]: kube.ServiceAccount('rook-ceph-%s' % suffix) {
      metadata+: {
        namespace: params.ceph_cluster.namespace,
      },
    }
    for suffix in [ 'osd', 'mgr', 'cmd-reporter' ]
  }
  else {};

local roles =
  // the following roles are created by the operator helm chart in the
  // operator namespace. However, if we create the Ceph cluster in a different
  // namespace, we need to create them in that namespace instead.
  if params.ceph_cluster.namespace != params.namespace then {
    // For OCP4 we need the metrics discovery role in the cluster
    // namespace, if it differs from the operator namespace.
    [if on_openshift then 'metrics']:
      helpers.metrics_role(params.ceph_cluster.namespace),
    osd: kube.Role('rook-ceph-osd') {
      metadata+: {
        namespace: params.ceph_cluster.namespace,
      },
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
    mgr: kube.Role('rook-ceph-mgr') {
      metadata+: {
        namespace: params.ceph_cluster.namespace,
      },
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
    cmd_reporter: kube.Role('rook-ceph-cmd-reporter') {
      metadata+: {
        namespace: params.ceph_cluster.namespace,
      },
      rules: [
        {
          apiGroups: [ '' ],
          resources: [ 'pods', 'configmaps' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'update', 'delete' ],
        },
      ],
    },
    monitoring: kube.Role('rook-ceph-monitoring') {
      metadata+: {
        namespace: params.ceph_cluster.namespace,
      },
      rules: [
        {
          apiGroups: [ 'monitoring.coreos.com' ],
          resources: [ 'servicemonitors', 'prometheusrules' ],
          verbs: [ 'get', 'list', 'watch', 'create', 'update', 'delete' ],
        },
      ],
    },
  }
  else {};

local rolebindings =
  // Rolebindings in general are only required if cluster namespace
  // differs from operator namespace.
  if params.ceph_cluster.namespace != params.namespace then
    (
      // For OCP4, we need the metrics discovery rolebinding
      if on_openshift then [
        helpers.ocp_metrics_rolebinding(
          params.ceph_cluster.namespace,
          roles.metrics,
        ),
      ]
      else []
    ) +
    [
      // allow the operator to create resource in the cluster's namespace
      kube.RoleBinding('rook-ceph-cluster-mgmt') {
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
      kube.RoleBinding('rook-ceph-osd') {
        metadata+: {
          namespace: params.ceph_cluster.namespace,
        },
        roleRef_:: roles.osd,
        subjects_:: [ serviceaccounts.osd ],
      },
      // Allow the ceph mgr to access the cluster-specific resources necessary for the mgr modules
      kube.RoleBinding('rook-ceph-mgr') {
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
      kube.RoleBinding('rook-ceph-cmd-reporter') {
        metadata+: {
          namespace: params.ceph_cluster.namespace,
        },
        roleRef_:: roles.cmd_reporter,
        subjects_:: [ serviceaccounts.cmd_reporter ],
      },
      // monitoring
      kube.RoleBinding('rook-ceph-monitoring') {
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
    ]
  else [];

local clusterrolebindings =
  if params.ceph_cluster.namespace != params.namespace then [
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
  ]
  else [];


local objValues(o) = [ o[it] for it in std.objectFields(o) ];

local rbac =
  objValues(serviceaccounts) +
  objValues(roles) +
  rolebindings +
  clusterrolebindings;


local devicesets = params.ceph_cluster.storageClassDeviceSets;
local getDeviceset(name) =
  if devicesets[name] != null then
    devicesets[name] {
      name: name,
      volumeClaimTemplates: std.objectValues(devicesets[name].volumeClaimTemplates),
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
          all: helpers.nodeAffinity,
        },
        disruptionManagement: {
          manageMachineDisruptionBudgets: on_openshift,
          machineDisruptionBudgetNamespace: 'openshift-machine-api',
        },
        storage+: {
          storageClassDeviceSets: std.filter(
            function(it) it != null,
            [ getDeviceset(name) for name in std.objectFields(devicesets) ]
          ),
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
      config: std.manifestIni({
        sections: params.ceph_cluster.config_override,
      }),
    },
  };

local toolboxManifest = helpers.load_manifest('toolbox');

local toolbox =
  assert
    std.length(toolboxManifest) == 1 :
    'More than one object in upstream toolbox YAML, make sure to update the component logic.';
  toolboxManifest[0] {
    local deployment = self,
    metadata+: {
      labels: std.prune(toolboxManifest[0].metadata.labels {
        app: null,
        name: super.app,
      }),
      namespace: params.ceph_cluster.namespace,
    },
    spec+: {
      selector: {
        matchLabels: deployment.metadata.labels,
      },
      strategy: {
        rollingUpdate: {
          maxSurge: '25%',
          maxUnavailable: '25%',
        },
        type: 'RollingUpdate',
      },
      template+: {
        metadata+: {
          labels: deployment.metadata.labels,
        },
        spec+: {
          containers:
            assert std.length(super.containers) == 1;
            [
              super.containers[0] {
                image: '%(registry)s/%(image)s:%(tag)s' % params.images.rook,
                // Remove securityContext config on OCP4
                [if on_openshift then 'securityContext']: {},
              },
            ],
          tolerations: params.tolerations,
          affinity: helpers.nodeAffinity,
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
