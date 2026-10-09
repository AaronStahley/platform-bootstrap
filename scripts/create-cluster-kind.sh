#!/bin/bash

set -e  # Exit on any error

echo "========================================="
echo "Creating Kubernetes Cluster with kind"
echo "========================================="
echo ""

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-platform-demo}"
KIND_VERSION="v0.20.0"

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "kind is not installed."
    echo ""
    echo "Installing kind..."
    
    # Detect OS
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        ARCH="arm64"
    fi
    
    # Download and install kind
    curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}"
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    
    echo "kind installed successfully"
    echo ""
fi

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster..."
        kind delete cluster --name "${CLUSTER_NAME}"
    else
        echo "Exiting without changes."
        exit 0
    fi
fi

# Create cluster configuration
echo "Creating cluster configuration..."
cat <<EOF > /tmp/kind-config-${CLUSTER_NAME}.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
EOF

echo ""
echo "Cluster Configuration:"
echo "  Name: ${CLUSTER_NAME}"
echo "  Nodes: 1 control-plane + 2 workers"
echo "  Port Mappings: 80 (HTTP), 443 (HTTPS)"
echo ""

# Create the cluster
echo "Creating cluster (this may take a few minutes)..."
kind create cluster --config /tmp/kind-config-${CLUSTER_NAME}.yaml

# Clean up temp config
rm /tmp/kind-config-${CLUSTER_NAME}.yaml

echo ""
echo "Cluster created successfully"
echo ""

# Verify cluster
echo "Verifying cluster..."
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

echo ""
echo "Cluster Nodes:"
kubectl get nodes

echo ""
echo "========================================="
echo "Cluster Ready"
echo "========================================="
echo ""