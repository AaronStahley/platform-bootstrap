#!/bin/bash

set -e  # Exit on any error

echo "========================================="
echo "Installing ArgoCD"
echo "========================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    echo "Please install kubectl first"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "Please ensure your cluster is running and kubeconfig is set"
    exit 1
fi

echo "SUCCESS: Kubernetes cluster is accessible"
echo ""

# Create ArgoCD namespace
echo "Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "SUCCESS: Namespace created"
echo ""

# Install ArgoCD
echo "Installing ArgoCD (this may take a minute)..."
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo ""
echo "Waiting for ArgoCD to be ready..."
echo "(This usually takes 1-2 minutes)"
echo ""

# Wait for deployments to be available
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo ""
echo "SUCCESS: ArgoCD installed successfully!"
echo ""

# Get the admin password
echo "========================================="
echo "ArgoCD Access Information"
echo "========================================="
echo ""
echo "Admin Password:"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo "$ARGOCD_PASSWORD"
echo ""
echo "WARNING: Save this password! You'll need it to log in."
echo ""

echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Access ArgoCD UI:"
echo "   Terminal 1: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Terminal 2: Open https://localhost:8080"
echo "   Username: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""
echo "2. (Optional) Install ArgoCD CLI:"
echo "   curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
echo "   sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd"
echo "   rm argocd-linux-amd64"
echo ""
echo "3. Bootstrap GitOps:"
echo "   ./scripts/bootstrap.sh"
echo ""
echo "========================================="
echo ""

# Check if all pods are running
echo "ArgoCD Pod Status:"
kubectl get pods -n argocd
echo ""