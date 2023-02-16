rook_ver=$(shell yq -e '.parameters.rook_ceph.images.rook.tag' ../../class/defaults.yml)

generate:
	mkdir -p out
	go run . ../../manifests/$(rook_ver)/prometheus-ceph-rules.yaml out
