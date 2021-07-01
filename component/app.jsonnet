local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rook_ceph;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('rook-ceph', params.namespace);

{
  'rook-ceph': app,
}
