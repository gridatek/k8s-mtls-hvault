#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"
PASSWORD="changeit"

echo "=== Uploading Invalid Truststore to Vault for App B ==="

# Get Vault pod name
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")

echo "Vault pod: $VAULT_POD"

# Check if bad truststore exists
if [ ! -f "${CERTS_DIR}/app-b-bad-truststore.jks" ]; then
  echo "Error: Bad truststore not found: ${CERTS_DIR}/app-b-bad-truststore.jks"
  echo "Please run break-app-b-trust.sh first"
  exit 1
fi

# Check if app-b keystore exists (we still need the valid keystore)
if [ ! -f "${CERTS_DIR}/app-b-keystore.p12" ]; then
  echo "Error: App B keystore not found: ${CERTS_DIR}/app-b-keystore.p12"
  echo "Please run generate-certs.sh first to create valid keystores"
  exit 1
fi

echo "Copying certificate files to Vault pod..."

# Copy the valid keystore and the INVALID truststore
kubectl cp "${CERTS_DIR}/app-b-keystore.p12" "${VAULT_POD}:/tmp/app-b-keystore.p12"
kubectl cp "${CERTS_DIR}/app-b-bad-truststore.jks" "${VAULT_POD}:/tmp/app-b-bad-truststore.jks"

echo "Converting certificates to base64 inside Vault pod..."
kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/app-b-keystore.p12 > /tmp/app-b-keystore.b64"
kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/app-b-bad-truststore.jks > /tmp/app-b-bad-truststore.b64"

echo "Updating App B in Vault with INVALID truststore..."
kubectl exec $VAULT_POD -- sh -c '
  export VAULT_TOKEN=root
  APP_B_KEY=$(cat /tmp/app-b-keystore.b64)
  BAD_TRUST=$(cat /tmp/app-b-bad-truststore.b64)
  vault kv put secret/app-b \
    ssl.keystore="$APP_B_KEY" \
    ssl.truststore="$BAD_TRUST" \
    ssl.keystore-password="'"${PASSWORD}"'" \
    ssl.truststore-password="'"${PASSWORD}"'" \
    ssl.keystore-type="PKCS12" \
    ssl.truststore-type="JKS" \
    ssl.key-alias="app-b"
'

echo "Cleaning up temporary files..."
kubectl exec $VAULT_POD -- rm -f /tmp/app-b-keystore.p12 /tmp/app-b-bad-truststore.jks \
  /tmp/app-b-keystore.b64 /tmp/app-b-bad-truststore.b64

echo ""
echo "=== Invalid Truststore Upload Complete ==="
echo "App B now has:"
echo "  - Valid keystore (can present its own certificate)"
echo "  - INVALID truststore (will NOT trust app-a's certificate)"
echo ""
echo "Expected behavior:"
echo "  - App B can still start up"
echo "  - App A -> App B: Will FAIL (app-b won't trust app-a's certificate)"
echo "  - App B -> App A: Will FAIL (app-a won't trust connection from app-b, or app-b won't trust app-a's response)"
echo ""
echo "To apply changes, restart app-b:"
echo "  kubectl rollout restart deployment/app-b"
echo ""
echo "To restore correct truststore, run:"
echo "  bash upload-certs-to-vault.sh"
echo "  kubectl rollout restart deployment/app-b"
