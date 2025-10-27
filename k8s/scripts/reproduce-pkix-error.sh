#!/bin/bash

# This script demonstrates how to reproduce the PKIX path building error
# by intentionally misconfiguring the truststore

set -e

echo "=========================================="
echo "PKIX Path Building Error Reproduction"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This script will temporarily break mTLS communication"
echo "to demonstrate the PKIX path building error."
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

# Get Vault pod
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")

echo ""
echo "=========================================="
echo "Scenario 1: Empty Truststore (No CA)"
echo "=========================================="
echo ""
echo "This simulates a truststore that doesn't contain the CA certificate"
echo "that signed the server's certificate."
echo ""

# Create an empty truststore
echo "Creating empty truststore..."
mkdir -p /tmp/pkix-test
cd /tmp/pkix-test

# Create a temporary keystore and delete the entry to get an empty truststore
keytool -genkeypair -alias dummy -keyalg RSA -keysize 2048 \
  -keystore empty-truststore.jks -storepass changeit \
  -dname "CN=Dummy" -validity 1 2>/dev/null

keytool -delete -alias dummy -keystore empty-truststore.jks -storepass changeit 2>/dev/null

echo "Empty truststore created."
echo ""

# Upload to Vault
echo "Uploading empty truststore to Vault for App A..."
kubectl cp empty-truststore.jks "${VAULT_POD}:/tmp/empty-truststore.jks"
kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/empty-truststore.jks > /tmp/empty-truststore.b64"

kubectl exec $VAULT_POD -- sh -c '
  export VAULT_TOKEN=root
  EMPTY_TRUST=$(cat /tmp/empty-truststore.b64)
  vault kv patch secret/app-a ssl.truststore="$EMPTY_TRUST"
'

echo -e "${YELLOW}✓ Empty truststore uploaded to Vault${NC}"
echo ""

# Restart App A to pick up the new truststore
echo "Restarting App A deployment to load empty truststore..."
kubectl rollout restart deployment/app-a
kubectl rollout status deployment/app-a --timeout=120s

APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")
echo "New App A pod: $APP_A_POD"
echo ""

# Give the app time to fully start
echo "Waiting for App A to fully start (30 seconds)..."
sleep 30

echo "=========================================="
echo "Testing Communication (Expect PKIX Error)"
echo "=========================================="
echo ""

echo "Attempting mTLS connection from App A to App B..."
echo "(This should fail with PKIX path building error)"
echo ""

set +e  # Don't exit on error
RESPONSE=$(kubectl exec $APP_A_POD -- curl -k --max-time 10 --show-error \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health 2>&1)
CURL_EXIT_CODE=$?
set -e

echo "Curl exit code: $CURL_EXIT_CODE"
echo "Response:"
echo "$RESPONSE"
echo ""

if [ $CURL_EXIT_CODE -ne 0 ]; then
  echo -e "${RED}❌ Connection failed (as expected)${NC}"
else
  echo -e "${YELLOW}⚠️  Unexpected: Connection succeeded${NC}"
fi

echo ""
echo "Checking App A logs for PKIX error..."
echo ""

PKIX_LOG=$(kubectl logs $APP_A_POD --tail=100 | grep -A 5 -B 5 -i "pkix\|certpath" || echo "No PKIX error in logs yet")
echo "$PKIX_LOG"

if echo "$PKIX_LOG" | grep -iq "pkix path building failed"; then
  echo ""
  echo -e "${RED}✓ PKIX path building failed error reproduced successfully!${NC}"
  echo ""
  echo "The error occurred because:"
  echo "  1. Server (App B) presented its certificate signed by 'CN=k8s-ca'"
  echo "  2. Client (App A) tried to validate the certificate"
  echo "  3. Client's truststore is empty (no CA certificates)"
  echo "  4. Client cannot build a certification path to a trusted root"
  echo "  5. Result: PKIX path building failed"
else
  echo ""
  echo -e "${YELLOW}⚠️  PKIX error not yet visible in logs (may take a few attempts)${NC}"
fi

echo ""
echo "=========================================="
echo "Restoring Correct Configuration"
echo "=========================================="
echo ""

echo "Uploading correct truststore back to Vault..."

# Re-upload the correct truststore
if [ -f "${CERTS_DIR}/truststore.jks" ]; then
  kubectl cp "${CERTS_DIR}/truststore.jks" "${VAULT_POD}:/tmp/truststore.jks"
  kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/truststore.jks > /tmp/truststore.b64"

  kubectl exec $VAULT_POD -- sh -c '
    export VAULT_TOKEN=root
    TRUST=$(cat /tmp/truststore.b64)
    vault kv patch secret/app-a ssl.truststore="$TRUST"
  '

  echo -e "${GREEN}✓ Correct truststore restored in Vault${NC}"
else
  echo -e "${RED}❌ Original truststore not found at ${CERTS_DIR}/truststore.jks${NC}"
  echo "Run generate-certs.sh and upload-certs-to-vault.sh to recreate certificates."
  exit 1
fi

echo ""
echo "Restarting App A with correct truststore..."
kubectl rollout restart deployment/app-a
kubectl rollout status deployment/app-a --timeout=120s

APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")
echo "New App A pod: $APP_A_POD"

echo ""
echo "Waiting for App A to fully start (30 seconds)..."
sleep 30

echo ""
echo "Testing communication (should succeed now)..."
RESPONSE=$(kubectl exec $APP_A_POD -- curl -k --fail --silent \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health)

if echo "$RESPONSE" | grep -q "UP"; then
  echo -e "${GREEN}✓ Communication restored successfully!${NC}"
  echo "  Response: $RESPONSE"
else
  echo -e "${RED}❌ Communication still failing${NC}"
  echo "  Response: $RESPONSE"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "This demonstration showed how the PKIX path building error occurs when:"
echo ""
echo "  1. The client's truststore is empty or missing the CA certificate"
echo "  2. The server presents a certificate signed by an unknown CA"
echo "  3. The client cannot validate the certificate chain"
echo ""
echo "The solution implemented in this repository:"
echo ""
echo "  ✓ Generate all certificates from a shared CA"
echo "  ✓ Create a truststore containing that CA certificate"
echo "  ✓ Distribute the truststore to all applications via Vault"
echo "  ✓ Configure Spring Boot to use the custom truststore"
echo "  ✓ Configure RestTemplate to use the same truststore"
echo ""
echo "This ensures that all certificates can be validated correctly,"
echo "preventing PKIX path building errors."
echo ""

# Cleanup
rm -rf /tmp/pkix-test

echo "Temporary files cleaned up."
echo ""
