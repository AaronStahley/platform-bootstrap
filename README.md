# platform-bootstrap

Day 0 bootstrap for Kubernetes cluster setup with ArgoCD and GitOps foundation.

## Overview

This repository provides automated setup for a local GitOps environment using:
- Kind (Kubernetes in Docker) for local cluster creation
- ArgoCD for GitOps continuous delivery
- App-of-apps pattern for managing infrastructure applications

## Prerequisites

- Docker (for kind)
- kubectl
- kind
- Git
- GNU Make
- A GitHub personal access token that can read and write `platform-gitops` and the
  `<domain>-gitops` repositories (Kargo pushes promotions to them), saved to
  `.secrets/github_token` (gitignored)
- A published, public `ghcr.io/<owner>/webapi-operator` image at the tag pinned in
  `platform-gitops`. Until the operator repo has cut a release, the operator pods
  cannot pull and `make bootstrap` will time out waiting for them.

## Quick Start

Run the complete setup with a single command:

```bash
make all
```

This will:
1. Create a kind cluster with 3 nodes (1 control-plane, 2 workers)
2. Install ArgoCD
3. Configure repository and Kargo credentials from your GitHub token
4. Bootstrap the two app-of-apps (platform first, then domains)
5. Deploy platform applications from the platform-gitops repository

## Individual Commands

For step-by-step execution or troubleshooting:

```bash
# Create the kind cluster
make cluster

# Install ArgoCD
make argocd

# Bootstrap GitOps applications
make bootstrap

# Destroy the cluster
make clean
```

## Repository Structure

```
platform-bootstrap/
├── .secrets/                      # GitHub token for ArgoCD and Kargo (gitignored)
│   └── github_token
├── argocd/
│   └── applications/
│       ├── infra-app-of-apps.yaml   # Root app: platform services
│       └── domains-app-of-apps.yaml # Root app: domain AppProjects and apps
├── scripts/
│   ├── create-cluster-kind.sh     # Kind cluster creation
│   ├── install-argocd.sh          # ArgoCD installation
│   └── bootstrap.sh               # GitOps bootstrap
└── makefile                       # Orchestration
```

## Access Information

### ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080

Username: `admin`

Password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

### Grafana UI

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
```

Open http://localhost:3000

Username: `admin`
Password: `admin`
