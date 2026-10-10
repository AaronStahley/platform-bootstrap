#!/bin/bash
set -e

# Owner of the platform repositories. Override to run this against your own fork:
#   GITHUB_USER=my-user ./scripts/bootstrap.sh
GITHUB_USER="${GITHUB_USER:-AaronStahley}"
GHCR_OWNER=$(echo "$GITHUB_USER" | tr '[:upper:]' '[:lower:]')

# Business domains. Each has its own GitOps repo ("<domain>-gitops") and Kargo project.
DOMAINS="payments orders"

echo "=== Bootstrapping GitOps ==="
echo ""

# 1. Verify ArgoCD is ready
echo "Checking ArgoCD readiness..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

echo "ArgoCD is ready"
echo ""

# 2. Configure repository credentials
echo "Configuring repository credentials..."
GITHUB_TOKEN_PATH=".secrets/github_token"

if [ ! -f "$GITHUB_TOKEN_PATH" ]; then
  echo "ERROR: GitHub token not found at $GITHUB_TOKEN_PATH"
  echo "Create a GitHub Personal Access Token that can read and write the"
  echo "platform-gitops and <domain>-gitops repositories (Kargo pushes promotions"
  echo "to them), then save it to: $GITHUB_TOKEN_PATH"
  exit 1
fi

GITHUB_TOKEN=$(cat "$GITHUB_TOKEN_PATH")

# Register a repository with ArgoCD.
#   $1 = repository name
create_argocd_repo_secret() {
  kubectl create secret generic "repo-$1" \
    --from-literal=type=git \
    --from-literal=url="https://github.com/${GITHUB_USER}/$1.git" \
    --from-literal=username="$GITHUB_USER" \
    --from-literal=password="$GITHUB_TOKEN" \
    -n argocd \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl label secret "repo-$1" \
    argocd.argoproj.io/secret-type=repository \
    -n argocd --overwrite

  echo "$1 credentials configured"
}

create_argocd_repo_secret platform-gitops
for DOMAIN in $DOMAINS; do
  create_argocd_repo_secret "${DOMAIN}-gitops"
done
create_argocd_repo_secret webapi-operator

echo "Repository credentials configured"
echo ""

# Configure Kargo Git write access and image discovery.
# A Kargo project is a labeled namespace. We pre-create and label each one here so
# credentials are in place before ArgoCD deploys the Kargo resources; the Kargo
# Project resource then adopts the namespace and manages it from there.
#   $1 = Kargo project namespace
#   $2 = GitOps repository Kargo pushes promotions to
#   $3 = image repository (or registry) Kargo's Warehouse discovers tags from
setup_kargo_project() {
  kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace "$1" kargo.akuity.io/project=true --overwrite

  kubectl create secret generic "$2-creds" \
    --from-literal=repoURL="https://github.com/${GITHUB_USER}/$2.git" \
    --from-literal=username="$GITHUB_USER" \
    --from-literal=password="$GITHUB_TOKEN" \
    -n "$1" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl label secret "$2-creds" \
    kargo.akuity.io/cred-type=git \
    -n "$1" --overwrite

  kubectl create secret generic ghcr-kargo-creds \
    --from-literal=repoURL="$3" \
    --from-literal=username="$GITHUB_USER" \
    --from-literal=password="$GITHUB_TOKEN" \
    -n "$1" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl label secret ghcr-kargo-creds \
    kargo.akuity.io/cred-type=image \
    -n "$1" --overwrite

  echo "Kargo project '$1' configured"
}

echo "Configuring Kargo credentials..."
echo "Note: Kargo uses the same GitHub token as ArgoCD"

# Platform project: promotes the webapi-operator image through dev -> qa -> prod
setup_kargo_project infrastructure platform-gitops "ghcr.io/${GHCR_OWNER}/webapi-operator"

# One project per domain
for DOMAIN in $DOMAINS; do
  setup_kargo_project "$DOMAIN" "${DOMAIN}-gitops" "ghcr.io"
done

echo "Kargo credentials configured"
echo ""
echo "NOTE: The GitHub token is used by both ArgoCD and Kargo for:"
echo "  - https://github.com/${GITHUB_USER}/platform-gitops (ArgoCD read + Kargo write)"
for DOMAIN in $DOMAINS; do
  echo "  - https://github.com/${GITHUB_USER}/${DOMAIN}-gitops (ArgoCD read + Kargo write)"
done
echo "  - https://github.com/${GITHUB_USER}/webapi-operator (ArgoCD read)"
echo ""

# Configure ArgoCD custom health checks
echo "Configuring ArgoCD custom health checks..."

kubectl patch configmap argocd-cm -n argocd --type merge -p '
data:
  resource.customizations.health.platform.aaronstahley.dev_WebApi: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "Ready" then
            if condition.status == "True" then
              hs.status = "Healthy"
              hs.message = condition.message
              return hs
            elseif condition.status == "False" then
              hs.status = "Degraded"
              hs.message = condition.message
              return hs
            else
              hs.status = "Progressing"
              hs.message = condition.message
              return hs
            end
          end
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for WebApi status"
    return hs
  resource.customizations.health.apps_Deployment: |
    hs = {}
    if obj.status ~= nil then
      local replicas = obj.status.replicas or 0
      local ready = obj.status.readyReplicas or 0
      local updated = obj.status.updatedReplicas or 0
      local available = obj.status.availableReplicas or 0
      if obj.metadata.generation == obj.status.observedGeneration
          and updated == replicas
          and ready == replicas
          and available == replicas then
        hs.status = "Healthy"
        hs.message = "Deployment is healthy"
        return hs
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for deployment rollout"
    return hs
'

echo "ArgoCD custom health checks configured"
echo ""

# Wait until every Argo CD Application is Synced and Healthy.
# A parent app-of-apps reports Healthy even when its children are not, and an app
# that cannot load its source (bad credentials, missing path) also reports Healthy
# with sync status Unknown, so checking the root app alone proves nothing.
# Apps that track a stage/<env> branch Kargo has not created yet are skipped: that
# branch appears on the first promotion into the stage.
#   $1 = timeout in seconds
wait_for_apps() {
  local deadline=$((SECONDS + $1))
  while true; do
    local apps errors awaiting pending
    apps=$(kubectl get applications -n argocd \
      -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{"\n"}{end}')
    errors=$(kubectl get applications -n argocd \
      -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.conditions[*].message}{"\n"}{end}' |
      grep -v ': $' || true)
    awaiting=$(echo "$errors" | grep "unable to resolve 'stage/" | cut -d: -f1 || true)
    pending=$(echo "$apps" | awk -v skip="$awaiting" '
      BEGIN { n = split(skip, s, "\n"); for (i = 1; i <= n; i++) skipped[s[i]] = 1 }
      NF && !($1 in skipped) && !($2 == "Synced" && $3 == "Healthy")')
    if [ -z "$pending" ]; then
      if [ -n "$awaiting" ]; then
        echo "Awaiting first Kargo promotion (stage branch not created yet):"
        echo "$awaiting" | sed 's/^/  /'
      fi
      return 0
    fi
    if [ $SECONDS -ge $deadline ]; then
      echo "ERROR: Argo CD applications not Synced/Healthy after $1s:"
      echo "$pending"
      [ -n "$errors" ] && echo "$errors"
      return 1
    fi
    sleep 10
  done
}

# 3. Apply infra app-of-apps and wait for it to be healthy before applying domains.
# This ensures the webapi-operator CRD and controller are running before the domain
# apps try to create WebApi resources, avoiding a sync race condition.
echo "Applying infrastructure app-of-apps..."
kubectl apply -f argocd/applications/infra-app-of-apps.yaml

echo "Waiting for infrastructure apps to sync and become healthy..."
echo "(This includes Kargo, the webapi-operator instances, and Kargo resources - may take ~10 min)"
wait_for_apps 900

echo "Infrastructure apps are synced and healthy"
echo ""

# 4. Now apply domains app-of-apps - operator CRD is guaranteed to exist
echo "Applying domains app-of-apps..."
kubectl apply -f argocd/applications/domains-app-of-apps.yaml

echo "Waiting for domain apps to sync and become healthy..."
wait_for_apps 600

echo "Domain apps are synced and healthy"
echo ""

# Wait for Kargo to be ready
echo "Waiting for Kargo to be ready..."
if kubectl wait --for=condition=available --timeout=300s \
  deployment/kargo-controller -n kargo 2>/dev/null; then
  echo "Kargo is ready"
else
  echo "Kargo deployment not found (will be installed on next sync)"
fi
echo ""

# 5. Show results
echo "=== ArgoCD Applications ==="
kubectl get applications -n argocd
echo ""

echo "Bootstrap complete! GitOps is active."
echo ""
echo "=== Access Information ==="
echo ""
echo "ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  URL: https://localhost:8080"
echo "  Username: admin"
echo "  Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo "Grafana UI (after deployment):"
echo "  kubectl port-forward -n monitoring svc/grafana 3000:80"
echo "  URL: http://localhost:3000"
echo "  Username: admin"
echo "  Password: admin   (demo only)"
echo ""
echo "Kargo UI (after deployment):"
echo "  kubectl port-forward -n kargo svc/kargo-api 8081:443"
echo "  URL: https://localhost:8081"
echo "  Username: admin"
echo "  Password: admin   (demo only)"
echo ""
