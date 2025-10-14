#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"
PASSWORD="changeit"

echo "=== Uploading Certificates to Vault ==="

# Get Vault pod name
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")

echo "Vault pod: $VAULT_POD"

# Check if certs directory exists
if [ ! -d "${CERTS_DIR}" ]; then
  echo "Error: Certs directory not found: ${CERTS_DIR}"
  echo "Please run generate-certs.sh first"
  exit 1
fi

# Check if required files exist
REQUIRED_FILES=(
  "app-a-keystore.p12"
  "app-b-keystore.p12"
  "truststore.jks"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "${CERTS_DIR}/${file}" ]; then
    echo "Error: Required file not found: ${file}"
    exit 1
  fi
done

echo "Copying certificate files to Vault pod..."

# Copy certificate files to Vault pod to avoid argument length limits
kubectl cp "${CERTS_DIR}/app-a-keystore.p12" "${VAULT_POD}:/tmp/app-a-keystore.p12"
kubectl cp "${CERTS_DIR}/app-b-keystore.p12" "${VAULT_POD}:/tmp/app-b-keystore.p12"
kubectl cp "${CERTS_DIR}/truststore.jks" "${VAULT_POD}:/tmp/truststore.jks"

echo "Converting certificates to base64 inside Vault pod..."
kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/app-a-keystore.p12 > /tmp/app-a-keystore.b64"
kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/app-b-keystore.p12 > /tmp/app-b-keystore.b64"
kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/truststore.jks > /tmp/truststore.b64"

echo "Uploading App A certificates to Vault..."
kubectl exec $VAULT_POD -- sh -c '
  export VAULT_TOKEN=root
  APP_A_KEY=$(cat /tmp/app-a-keystore.b64)
  TRUST=$(cat /tmp/truststore.b64)
  vault kv put secret/app-a \
    ssl.keystore="$APP_A_KEY" \
    ssl.truststore="$TRUST" \
    ssl.keystore-password="'"${PASSWORD}"'" \
    ssl.truststore-password="'"${PASSWORD}"'" \
    ssl.keystore-type="PKCS12" \
    ssl.truststore-type="JKS" \
    ssl.key-alias="app-a"
'

echo "Uploading App B certificates to Vault..."
kubectl exec $VAULT_POD -- sh -c '
  export VAULT_TOKEN=root
  APP_B_KEY=$(cat /tmp/app-b-keystore.b64)
  TRUST=$(cat /tmp/truststore.b64)
  vault kv put secret/app-b \
    ssl.keystore="$APP_B_KEY" \
    ssl.truststore="$TRUST" \
    ssl.keystore-password="'"${PASSWORD}"'" \
    ssl.truststore-password="'"${PASSWORD}"'" \
    ssl.keystore-type="PKCS12" \
    ssl.truststore-type="JKS" \
    ssl.key-alias="app-b"
'

echo "Cleaning up temporary files..."
kubectl exec $VAULT_POD -- rm -f /tmp/app-a-keystore.p12 /tmp/app-b-keystore.p12 /tmp/truststore.jks \
  /tmp/app-a-keystore.b64 /tmp/app-b-keystore.b64 /tmp/truststore.b64

echo "Verifying stored secrets..."
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root vault kv get -format=json secret/app-a > /dev/null
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root vault kv get -format=json secret/app-b > /dev/null

echo ""
echo "=== Certificate Upload Complete ==="
echo "Certificates stored in Vault at:"
echo "  - secret/app-a"
echo "  - secret/app-b"
