#!/bin/bash

# Vault Deployment Script
# This script deploys and configures HashiCorp Vault in Minikube for certificate management

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "========================================="
echo "Vault Deployment for mTLS Certificate Management"
echo "========================================="

# Step 1: Deploy Vault
echo ""
echo "Step 1: Deploying Vault to Kubernetes..."
kubectl apply -f "${MANIFESTS_DIR}/vault-deployment.yaml"
kubectl apply -f "${MANIFESTS_DIR}/vault-service.yaml"

echo "Waiting for Vault pod to be ready..."
kubectl wait --for=condition=ready pod -l app=vault --timeout=120s

VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")
echo "Vault pod is ready: ${VAULT_POD}"

# Step 2: Initialize Vault
echo ""
echo "Step 2: Initializing Vault..."
bash "${SCRIPT_DIR}/init-vault.sh"

# Step 3: Generate certificates
echo ""
echo "Step 3: Generating certificates..."
if [ ! -d "${SCRIPT_DIR}/../certs" ] || [ -z "$(ls -A ${SCRIPT_DIR}/../certs 2>/dev/null)" ]; then
  bash "${SCRIPT_DIR}/generate-certs.sh"
else
  echo "Certificates already exist. Skipping generation."
fi

# Step 4: Upload certificates to Vault
echo ""
echo "Step 4: Uploading certificates to Vault..."
bash "${SCRIPT_DIR}/upload-incomplete-certs-to-vault.sh"

echo ""
echo "========================================="
echo "Vault deployment complete!"
echo "========================================="
echo ""
echo "Vault is now configured with:"
echo "  - KV v2 secrets engine at: secret/"
echo "  - Kubernetes authentication enabled"
echo "  - Policies for app-a and app-b"
echo "  - SSL certificates stored in Vault"
echo ""
echo "Next steps:"
echo "  1. Build Docker images: bash build-images.sh"
echo "  2. Deploy applications: kubectl apply -f ../manifests/app-*"
echo ""
echo "To access Vault UI (for development):"
echo "  kubectl port-forward svc/vault 8200:8200"
echo "  Open: http://localhost:8200"
echo "  Token: root"
