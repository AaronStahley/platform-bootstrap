# CLAUDE.md: platform-bootstrap

Day-0 setup for the local platform. It creates a kind cluster, installs Argo CD, registers repo and Kargo credentials, adds custom health checks (`WebApi`, `Deployment`) and applies the two root app-of-apps (`infra-apps` first, then `domains-apps`). Everything after that is owned by `platform-gitops`.

## Layout

- `makefile`: `cluster`, `argocd`, `bootstrap`, `all`, `clean` (`CLUSTER_NAME`, default `platform-demo`).
- `scripts/create-cluster-kind.sh`, `scripts/install-argocd.sh`, `scripts/bootstrap.sh`.
- `argocd/applications/`: the two root Applications.
- `.secrets/github_token` (gitignored): PAT with read/write to `platform-gitops` and the `<domain>-gitops` repos. Never commit it or echo it in logs.

## Build, test, run

Requires Docker on a cgroup v2 host, kind, kubectl, make, and `.secrets/github_token` (fine-grained PAT, Contents read/write on the four platform repos; see README "GitHub token").

```bash
make all        # cluster + Argo CD + bootstrap (~10-15 min)
make clean      # delete the kind cluster
kubectl get applications -n argocd
```

`GITHUB_USER` overrides the repo owner for forks. Validate script changes with `bash -n` and `shellcheck` when available, then run `make clean all` end to end.

## The five-repo platform

| Repo | Role |
|---|---|
| `webapi-operator` | Go/kubebuilder operator. Owns the `WebApi` CRD (`platform.aaronstahley.dev/v1alpha1`) and reconciles it into a Deployment and Service. Ships a Helm chart and a GHCR image. |
| `platform-gitops` | Platform team repo. Argo CD app-of-apps (`apps/infrastructure`, `apps/domains`), AppProjects as tenant boundaries, namespaces, Kargo, operator instances per env, docs. |
| `platform-bootstrap` | Day-0: kind cluster, Argo CD install, credentials, root app-of-apps. `make all`. |
| `payments-gitops` | Domain repo: podinfo as a `WebApi`, Kustomize overlays per env, Kargo warehouse and stages. |
| `orders-gitops` | Same shape as payments, for the orders domain. |

Flow: a developer changes a `WebApi` in a domain repo on Git. Kargo turns the change into Freight and promotes dev -> qa -> prod by rendering into `stage/<env>` branches. Argo CD syncs each env from its branch, and the operator reconciles the `WebApi`.

## Conventions (all repos)

- Commit as `Aaron Stahley <AaronStahley@users.noreply.github.com>` (set via local `git config`).
- Keep commits small and meaningful.
- Never hand-edit generated files (deepcopy, CRDs, RBAC). In webapi-operator run `make manifests generate`, then refresh the Helm chart's CRD copy in `helm/webapi-operator/crds/`.
- Demo workload is podinfo: `ghcr.io/stefanprodan/podinfo` `6.15.0`, port `9898`, liveness `/healthz`, readiness `/readyz`.
- Domains are `payments` and `orders`. CRD group/version is `platform.aaronstahley.dev/v1alpha1`.
- These repos are public. No secrets, tokens or personal email addresses.
- Run tests and the build after changes, and only commit/push when they pass.
