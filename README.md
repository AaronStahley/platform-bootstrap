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
- A GitHub token saved to `.secrets/github_token`. See [GitHub token](#github-token).
- A cgroup v2 Docker host. Current kind node images refuse to start the kubelet on
  cgroup v1. On WSL2 with Docker Desktop, add `kernelCommandLine = cgroup_no_v1=all`
  under `[wsl2]` in `%USERPROFILE%\.wslconfig`, run `wsl --shutdown` and restart
  Docker Desktop. `docker info | grep Cgroup` should report version 2.

The operator itself is not a bootstrap dependency. `platform-gitops` deploys it and
pins its image tag; bootstrap only waits for it to become healthy along with the rest
of the platform apps.

## GitHub token

Argo CD and Kargo both authenticate to GitHub with one token, read from
`.secrets/github_token`. The `.secrets/` folder is gitignored; never commit the token.

Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new)
with:

**Repository access**: `platform-gitops`, `payments-gitops`, `orders-gitops` and
`webapi-operator` (or all repositories).

**Repository permissions**:

| Permission | Access | Why |
|---|---|---|
| Contents | Read and write | Argo CD clones the repos to render manifests (read). Kargo promotes by committing rendered manifests to the `stage/<env>` branches of `platform-gitops` and the `<domain>-gitops` repos (write). |
| Metadata | Read-only | Required by GitHub for every fine-grained token; selected automatically. |

No other permissions are needed. Promotions are plain commits and pushes, not pull
requests, and the images (`webapi-operator`, podinfo) are public on GHCR, so no
Packages access is required.

Save it with:

```bash
mkdir -p .secrets && chmod 700 .secrets
(umask 077; echo -n '<token>' > .secrets/github_token)
```

If Argo CD shows `authorization failed: Write access to repository not granted`, the
token is missing **Contents** access to that repo. GitHub returns this message for
reads too.

The bootstrap copies the token into Kubernetes Secrets: one per repo in `argocd` for
Argo CD, and per Kargo project namespace for Git writes and image discovery. They are
base64, not encrypted, which is acceptable for a local kind cluster only. A production
setup would use a GitHub App with per-consumer scopes and an external secret store.

## Quick Start

Run the complete setup with a single command:

```bash
make all
```

This will:
1. Create a kind cluster with 3 nodes (1 control-plane, 2 workers)
2. Install ArgoCD
3. Configure repository and Kargo credentials from your GitHub token
4. Bootstrap the two app-of-apps (platform first, then domains), waiting until every
   Argo CD application is Synced and Healthy
5. Deploy platform applications from the platform-gitops repository

The qa and prod domain apps track `stage/qa` and `stage/prod` branches that Kargo
creates on the first promotion into those stages. Until then they show sync status
`Unknown`, and the bootstrap lists them as awaiting promotion rather than failing.

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
