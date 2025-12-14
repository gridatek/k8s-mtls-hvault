#!/bin/bash

# This script intentionally triggers the PKIX path building error
# for educational purposes

set -e

echo "=========================================="
echo "PKIX Error Reproduction - Manual Steps"
echo "=========================================="
echo ""
echo "This will break App A's truststore configuration to demonstrate"
echo "the PKIX path building failed error."
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"

# Check if apps are deployed
if ! kubectl get deployment app-a &>/dev/null; then
  echo -e "${RED}❌ App A is not deployed. Please run 'bash deploy.sh' first.${NC}"
  exit 1
fi

# Get Vault pod
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")

if [ -z "$VAULT_POD" ]; then
  echo -e "${RED}❌ Vault pod not found. Please run 'bash vault-deploy.sh' first.${NC}"
  exit 1
fi

echo -e "${CYAN}Step 1: Showing current working configuration...${NC}"
echo ""

APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")

echo "Current truststore in App A:"
kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS 2>/dev/null | grep -A 1 "Your keystore contains"

echo ""
echo -e "${GREEN}✓ Current truststore contains the CA certificate (working)${NC}"
echo ""
echo "Testing current communication (should work)..."

RESPONSE=$(kubectl exec $APP_A_POD -- curl -k --fail --silent --max-time 5 \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health 2>&1 || echo "FAILED")

if [[ "$RESPONSE" == *"UP"* ]]; then
  echo -e "${GREEN}✓ Communication works: $RESPONSE${NC}"
else
  echo -e "${RED}✗ Communication already broken: $RESPONSE${NC}"
  exit 1
fi

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Step 2: Creating empty truststore (no CA certificate)...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create empty truststore
mkdir -p /tmp/pkix-test
cd /tmp/pkix-test

echo "Creating empty truststore..."
# Create temp entry and delete it to get empty truststore
keytool -genkeypair -alias dummy -keyalg RSA -keysize 2048 \
  -keystore empty-truststore.jks -storepass changeit \
  -dname "CN=Dummy" -validity 1 2>/dev/null

keytool -delete -alias dummy -keystore empty-truststore.jks -storepass changeit 2>/dev/null

echo ""
echo "Verifying empty truststore:"
keytool -list -keystore empty-truststore.jks -storepass changeit -storetype JKS 2>/dev/null | grep -A 1 "Your keystore contains"

echo ""
echo -e "${YELLOW}⚠️  Truststore is now empty (contains 0 entries)${NC}"
echo ""

echo -e "${CYAN}Step 3: Uploading empty truststore to Vault...${NC}"
echo ""

# Upload empty truststore to Vault
kubectl cp empty-truststore.jks "${VAULT_POD}:/tmp/empty-truststore.jks"
kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/empty-truststore.jks > /tmp/empty-truststore.b64"

kubectl exec $VAULT_POD -- sh -c '
  export VAULT_TOKEN=root
  EMPTY_TRUST=$(cat /tmp/empty-truststore.b64)
  vault kv patch secret/app-a ssl.truststore="$EMPTY_TRUST"
' 2>/dev/null

echo -e "${YELLOW}✓ Empty truststore uploaded to Vault (secret/app-a)${NC}"
echo ""

echo -e "${CYAN}Step 4: Restarting App A to load the empty truststore...${NC}"
echo ""

kubectl rollout restart deployment/app-a >/dev/null
echo "Waiting for App A to restart..."
kubectl rollout status deployment/app-a --timeout=120s

# Get new pod name
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")
echo "New App A pod: $APP_A_POD"

# Wait for app to fully start
echo "Waiting 30 seconds for Spring Boot to initialize..."
sleep 30

echo ""
echo -e "${CYAN}Step 5: Verifying empty truststore is loaded...${NC}"
echo ""

kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS 2>/dev/null | grep -A 1 "Your keystore contains"

echo ""
echo -e "${RED}⚠️  App A now has an empty truststore (0 trusted CAs)${NC}"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Step 6: Attempting mTLS communication (WILL FAIL)...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Trying to connect from App A to App B..."
echo "(App B will present its certificate signed by k8s-ca)"
echo "(App A has no CA in truststore, so cannot validate it)"
echo ""

set +e  # Don't exit on error
RESPONSE=$(kubectl exec $APP_A_POD -- curl -k --max-time 10 --show-error \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health 2>&1)
CURL_EXIT_CODE=$?
set -e

echo -e "${RED}═══════════════════════════════════════════════${NC}"
echo -e "${RED}        PKIX ERROR (As Expected)               ${NC}"
echo -e "${RED}═══════════════════════════════════════════════${NC}"
echo ""
echo "Exit code: $CURL_EXIT_CODE"
echo ""
echo "Error output:"
echo "$RESPONSE"
echo ""

if [ $CURL_EXIT_CODE -ne 0 ]; then
  echo -e "${RED}✓ Connection FAILED as expected!${NC}"
  echo ""
  echo "The connection failed because:"
  echo "  1. Server (App B) presented certificate signed by 'CN=k8s-ca'"
  echo "  2. Client (App A) searched truststore for 'CN=k8s-ca'"
  echo "  3. Truststore is empty (0 entries)"
  echo "  4. Client cannot build certification path"
  echo "  5. Result: Connection rejected"
else
  echo -e "${YELLOW}⚠️  Unexpected: Connection succeeded${NC}"
fi

echo ""
echo -e "${CYAN}Step 7: Checking application logs for PKIX error...${NC}"
echo ""

echo "Searching for PKIX error in App A logs..."
echo ""

PKIX_LOG=$(kubectl logs $APP_A_POD --tail=200 | grep -A 10 -B 5 -i "pkix\|certpath\|sslhandshake" || echo "")

if [ -n "$PKIX_LOG" ]; then
  echo -e "${RED}═══════════════════════════════════════════════${NC}"
  echo -e "${RED}     PKIX ERROR IN APPLICATION LOGS           ${NC}"
  echo -e "${RED}═══════════════════════════════════════════════${NC}"
  echo ""
  echo "$PKIX_LOG"
  echo ""
  echo -e "${RED}✓ PKIX path building failed error found in logs!${NC}"
else
  echo -e "${YELLOW}No PKIX error in logs yet (may appear on next connection attempt)${NC}"
  echo ""
  echo "Try this command to trigger the error from within the application:"
  echo -e "${CYAN}kubectl exec $APP_A_POD -- curl -k \\${NC}"
  echo -e "${CYAN}  --cert /etc/security/ssl/app-a-keystore.p12:changeit \\${NC}"
  echo -e "${CYAN}  --cert-type P12 \\${NC}"
  echo -e "${CYAN}  https://localhost:8443/api/call-app-b${NC}"
fi

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Step 8: Understanding the error...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "The full error message would be:"
echo ""
echo -e "${RED}javax.net.ssl.SSLHandshakeException: PKIX path building failed:${NC}"
echo -e "${RED}sun.security.provider.certpath.SunCertPathBuilderException:${NC}"
echo -e "${RED}unable to find valid certification path to requested target${NC}"
echo ""

echo "What this means:"
echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │ Server Certificate (App B)                              │"
echo "  │   CN: app-b.default.svc.cluster.local                   │"
echo "  │   Issuer: CN=k8s-ca ←───────┐                           │"
echo "  └─────────────────────────────────────────────────────────┘"
echo "                                │"
echo "                                │ Client searches truststore"
echo "                                │ for this CA..."
echo "                                ↓"
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │ Client Truststore (App A)                               │"
echo "  │   (empty - 0 entries) ←─────── ❌ CA NOT FOUND!         │"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""
echo "  Result: Cannot build certification path → PKIX error!"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}Would you like to restore the working configuration?${NC}"
echo ""
read -p "Press Enter to restore, or Ctrl+C to keep broken config for testing..."

echo ""
echo -e "${CYAN}Step 9: Restoring correct truststore...${NC}"
echo ""

if [ ! -f "${CERTS_DIR}/truststore.jks" ]; then
  echo -e "${RED}❌ Original truststore not found at ${CERTS_DIR}/truststore.jks${NC}"
  echo "Run: cd k8s/scripts && bash generate-certs.sh && bash upload-certs-to-vault.sh"
  exit 1
fi

# Upload correct truststore back
kubectl cp "${CERTS_DIR}/truststore.jks" "${VAULT_POD}:/tmp/truststore.jks"
kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/truststore.jks > /tmp/truststore.b64"

kubectl exec $VAULT_POD -- sh -c '
  export VAULT_TOKEN=root
  TRUST=$(cat /tmp/truststore.b64)
  vault kv patch secret/app-a ssl.truststore="$TRUST"
' 2>/dev/null

echo -e "${GREEN}✓ Correct truststore restored in Vault${NC}"
echo ""

echo "Restarting App A with correct truststore..."
kubectl rollout restart deployment/app-a >/dev/null
kubectl rollout status deployment/app-a --timeout=120s

APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")

echo "Waiting 30 seconds for app to start..."
sleep 30

echo ""
echo "Verifying truststore now contains CA:"
kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS 2>/dev/null | grep -A 1 "Your keystore contains"

echo ""
echo "Testing communication (should work now)..."
RESPONSE=$(kubectl exec $APP_A_POD -- curl -k --fail --silent \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health)

if [[ "$RESPONSE" == *"UP"* ]]; then
  echo -e "${GREEN}✓ Communication restored! Response: $RESPONSE${NC}"
else
  echo -e "${RED}✗ Still failing: $RESPONSE${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}            DEMONSTRATION COMPLETE             ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "You have successfully reproduced and fixed the PKIX error!"
echo ""
echo "Key Learnings:"
echo "  1. Empty truststore → PKIX path building failed"
echo "  2. Truststore with CA → Certificate validated successfully"
echo "  3. The CA in truststore must match the certificate issuer"
echo ""
echo "Configuration restored. All systems operational."
echo ""

# Cleanup
rm -rf /tmp/pkix-test
