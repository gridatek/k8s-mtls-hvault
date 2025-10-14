#!/bin/bash

# Complete deployment script with HashiCorp Vault
# This script deploys the full mTLS infrastructure with Vault-based secret management

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "Complete Deployment Process"
echo "Using HashiCorp Vault for Secret Management"
echo "========================================="
echo ""

# Step 1: Deploy and configure Vault
echo "Step 1: Deploying and configuring Vault..."
bash "${SCRIPT_DIR}/vault-deploy.sh"

# Step 2: Build Docker images
echo ""
echo "Step 2: Building Docker images..."
bash "${SCRIPT_DIR}/build-images.sh"

# Step 3: Deploy applications to Kubernetes
echo ""
echo "Step 3: Deploying applications to Kubernetes..."
kubectl apply -f "${SCRIPT_DIR}/../manifests/vault-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/../manifests/vault-service.yaml"
kubectl apply -f "${SCRIPT_DIR}/../manifests/app-a-service.yaml"
kubectl apply -f "${SCRIPT_DIR}/../manifests/app-a-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/../manifests/app-b-service.yaml"
kubectl apply -f "${SCRIPT_DIR}/../manifests/app-b-deployment.yaml"

# Wait for deployments
echo ""
echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/vault || true
kubectl wait --for=condition=available --timeout=180s deployment/app-a || true
kubectl wait --for=condition=available --timeout=180s deployment/app-b || true

# Show status
echo ""
echo "========================================="
echo "Deployment Complete"
echo "========================================="
echo ""
echo "Pods:"
kubectl get pods -l 'app in (app-a,app-b,vault)'
echo ""
echo "Services:"
kubectl get services -l 'app in (app-a,app-b,vault)'

echo ""
echo "To test the deployment:"
echo "  kubectl exec -it deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://app-b.default.svc.cluster.local:8443/health"
echo "  kubectl exec -it deployment/app-b -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://app-a.default.svc.cluster.local:8443/health"

echo ""
echo "To access Vault UI (for development):"
echo "  kubectl port-forward svc/vault 8200:8200"
echo "  Open: http://localhost:8200"
echo "  Token: root"

echo ""
echo "To view logs:"
echo "  kubectl logs -f deployment/app-a"
echo "  kubectl logs -f deployment/app-b"
echo "  kubectl logs -f deployment/vault"
