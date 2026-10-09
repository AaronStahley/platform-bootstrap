.PHONY: cluster argocd bootstrap all clean

export CLUSTER_NAME ?= platform-demo

cluster:
	bash scripts/create-cluster-kind.sh

argocd:
	bash scripts/install-argocd.sh

bootstrap:
	./scripts/bootstrap.sh

all: cluster argocd bootstrap

clean:
	kind delete cluster --name $(CLUSTER_NAME)