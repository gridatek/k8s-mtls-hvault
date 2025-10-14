#!/bin/bash

# DEPRECATED: This script is no longer used.
# The project now uses HashiCorp Vault for secret management.
# See vault-deploy.sh and upload-certs-to-vault.sh instead.
#
# This script is kept for reference only.

echo "=============================================="
echo "WARNING: This script is deprecated!"
echo "=============================================="
echo "This project now uses HashiCorp Vault for secret management."
echo "Please use: bash vault-deploy.sh"
echo ""
echo "If you still want to proceed with Kubernetes Secrets (not recommended),"
echo "press Ctrl+C to cancel or Enter to continue..."
read -r

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"

echo "=== Creating Kubernetes Secrets ==="

# Check if certificate files exist
if [ ! -f "${CERTS_DIR}/app-a-keystore.p12" ]; then
    echo "Error: app-a-keystore.p12 not found!"
    echo "Please run generate-certs.sh first."
    exit 1
fi

if [ ! -f "${CERTS_DIR}/app-b-keystore.p12" ]; then
    echo "Error: app-b-keystore.p12 not found!"
    echo "Please run generate-certs.sh first."
    exit 1
fi

if [ ! -f "${CERTS_DIR}/truststore.jks" ]; then
    echo "Error: truststore.jks not found!"
    echo "Please run generate-certs.sh first."
    exit 1
fi

# Delete existing secrets if they exist
echo "Deleting existing secrets (if any)..."
kubectl delete secret app-a-ssl-secret --ignore-not-found=true
kubectl delete secret app-b-ssl-secret --ignore-not-found=true

# Create App A secret
echo "Creating secret for App A..."
kubectl create secret generic app-a-ssl-secret \
  --from-file=app-a-keystore.p12="${CERTS_DIR}/app-a-keystore.p12" \
  --from-file=truststore.jks="${CERTS_DIR}/truststore.jks"

# Create App B secret
echo "Creating secret for App B..."
kubectl create secret generic app-b-ssl-secret \
  --from-file=app-b-keystore.p12="${CERTS_DIR}/app-b-keystore.p12" \
  --from-file=truststore.jks="${CERTS_DIR}/truststore.jks"

# Verify secrets were created
echo ""
echo "=== Secrets Created Successfully ==="
kubectl get secrets app-a-ssl-secret app-b-ssl-secret

echo ""
echo "Next steps:"
echo "1. Build and push Docker images"
echo "2. Deploy applications: kubectl apply -f k8s/manifests/"
