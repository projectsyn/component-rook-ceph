#!/bin/bash

if [[ $(command -v docker) ]]; then
	cmd=$(command -v docker)
	userns=""
elif [[ $(command -v podman) ]]; then
	cmd=$(command -v podman)
	userns='--userns=keep-id'
else
	echo 'Require the command `docker` or `podman`. Neither found.' >&2
	exit 1
fi

name=$(basename "${PWD}")
args="run --rm -u $(id -u):$(id -g) ${userns} -w /${name} -e HOME=/${name} -v ${PWD}:/${name} --network ${name}"

${cmd} network create ${name}

${cmd} ${args} --name proxy bitnami/kubectl --server=https://api.cloudscale-lpg-2.appuio.cloud:6443 --token="${KUBE_TOKEN}" --as=cluster-admin -n openshift-monitoring port-forward --address 0.0.0.0 pod/prometheus-k8s-0 9090 &

${cmd} ${args} ghcr.io/cloudflare/pint:0.22.2 pint lint tests/golden
result=$?

${cmd} kill proxy
${cmd} network rm ${name}

exit ${result}
