#!/bin/bash

set -e

echo "=== Initializing Vault ==="

# Wait for Vault to be ready
echo "Waiting for Vault to be ready..."
kubectl wait --for=condition=ready pod -l app=vault --timeout=120s

# Get Vault pod name
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")

echo "Vault pod: $VAULT_POD"

echo "Configuring Vault..."

# Enable KV v2 secrets engine for applications
echo "Enabling KV v2 secrets engine..."
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root vault secrets enable -version=2 -path=secret kv || echo "KV secrets engine already enabled"

# Enable Kubernetes auth method
echo "Enabling Kubernetes auth..."
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root vault auth enable kubernetes || echo "Kubernetes auth already enabled"

# Configure Kubernetes auth
echo "Configuring Kubernetes auth..."
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root sh -c 'vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT_HTTPS"'

# Create policy for app-a
echo "Creating app-a policy..."
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root sh -c 'vault policy write app-a-policy - <<EOF
path "secret/data/app-a" {
  capabilities = ["read"]
}
path "secret/data/application" {
  capabilities = ["read"]
}
EOF'

# Create policy for app-b
echo "Creating app-b policy..."
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root sh -c 'vault policy write app-b-policy - <<EOF
path "secret/data/app-b" {
  capabilities = ["read"]
}
path "secret/data/application" {
  capabilities = ["read"]
}
EOF'

# Create Kubernetes auth role for app-a
echo "Creating app-a role..."
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root vault write auth/kubernetes/role/app-a \
    bound_service_account_names=app-a \
    bound_service_account_namespaces=default \
    policies=app-a-policy \
    ttl=24h

# Create Kubernetes auth role for app-b
echo "Creating app-b role..."
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root vault write auth/kubernetes/role/app-b \
    bound_service_account_names=app-b \
    bound_service_account_namespaces=default \
    policies=app-b-policy \
    ttl=24h

echo "=== Vault initialization complete ==="
