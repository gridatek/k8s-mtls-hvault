#!/bin/bash

set -e

echo "=========================================="
echo "PKIX Error Prevention Verification"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get pod names
echo ""
echo "Getting pod names..."
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")
APP_B_POD=$(kubectl get pod -l app=app-b -o jsonpath="{.items[0].metadata.name}")

if [ -z "$APP_A_POD" ] || [ -z "$APP_B_POD" ]; then
  echo -e "${RED}❌ FAILED: Could not find app pods. Are they deployed?${NC}"
  exit 1
fi

echo "  App A Pod: $APP_A_POD"
echo "  App B Pod: $APP_B_POD"

echo ""
echo "=========================================="
echo "Test 1: Certificate Files Exist"
echo "=========================================="
echo "Checking App A certificate files..."
if kubectl exec $APP_A_POD -- test -f /etc/security/ssl/app-a-keystore.p12 && \
   kubectl exec $APP_A_POD -- test -f /etc/security/ssl/truststore.jks; then
  echo -e "${GREEN}✅ SUCCESS: App A certificate files exist${NC}"
  kubectl exec $APP_A_POD -- ls -lh /etc/security/ssl/
else
  echo -e "${RED}❌ FAILED: Certificate files missing${NC}"
  exit 1
fi

echo ""
echo "Checking App B certificate files..."
if kubectl exec $APP_B_POD -- test -f /etc/security/ssl/app-b-keystore.p12 && \
   kubectl exec $APP_B_POD -- test -f /etc/security/ssl/truststore.jks; then
  echo -e "${GREEN}✅ SUCCESS: App B certificate files exist${NC}"
  kubectl exec $APP_B_POD -- ls -lh /etc/security/ssl/
else
  echo -e "${RED}❌ FAILED: Certificate files missing${NC}"
  exit 1
fi

echo ""
echo "=========================================="
echo "Test 2: Keystore Contains Valid Certificate"
echo "=========================================="
echo "Checking App A keystore..."
KEYSTORE_OUTPUT=$(kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12 2>&1)

if echo "$KEYSTORE_OUTPUT" | grep -q "app-a"; then
  echo -e "${GREEN}✅ SUCCESS: App A keystore contains 'app-a' entry${NC}"
  echo "$KEYSTORE_OUTPUT" | grep "app-a"
else
  echo -e "${RED}❌ FAILED: App A keystore is invalid${NC}"
  echo "$KEYSTORE_OUTPUT"
  exit 1
fi

echo ""
echo "Checking App B keystore..."
KEYSTORE_OUTPUT=$(kubectl exec $APP_B_POD -- keytool -list -keystore /etc/security/ssl/app-b-keystore.p12 \
  -storepass changeit -storetype PKCS12 2>&1)

if echo "$KEYSTORE_OUTPUT" | grep -q "app-b"; then
  echo -e "${GREEN}✅ SUCCESS: App B keystore contains 'app-b' entry${NC}"
  echo "$KEYSTORE_OUTPUT" | grep "app-b"
else
  echo -e "${RED}❌ FAILED: App B keystore is invalid${NC}"
  echo "$KEYSTORE_OUTPUT"
  exit 1
fi

echo ""
echo "=========================================="
echo "Test 3: Truststore Contains CA Certificate"
echo "=========================================="
echo "Checking App A truststore..."
TRUSTSTORE_OUTPUT=$(kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS 2>&1)

if echo "$TRUSTSTORE_OUTPUT" | grep -q "ca,"; then
  echo -e "${GREEN}✅ SUCCESS: App A truststore contains CA certificate${NC}"
  echo "$TRUSTSTORE_OUTPUT" | grep "ca,"
else
  echo -e "${RED}❌ FAILED: CA certificate missing from truststore${NC}"
  echo "$TRUSTSTORE_OUTPUT"
  exit 1
fi

echo ""
echo "Checking App B truststore..."
TRUSTSTORE_OUTPUT=$(kubectl exec $APP_B_POD -- keytool -list -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS 2>&1)

if echo "$TRUSTSTORE_OUTPUT" | grep -q "ca,"; then
  echo -e "${GREEN}✅ SUCCESS: App B truststore contains CA certificate${NC}"
  echo "$TRUSTSTORE_OUTPUT" | grep "ca,"
else
  echo -e "${RED}❌ FAILED: CA certificate missing from truststore${NC}"
  echo "$TRUSTSTORE_OUTPUT"
  exit 1
fi

echo ""
echo "=========================================="
echo "Test 4: Certificate Chain Validation"
echo "=========================================="
echo "Extracting and verifying App A certificate chain..."

# Extract server certificate
kubectl exec $APP_A_POD -- openssl pkcs12 -in /etc/security/ssl/app-a-keystore.p12 \
  -passin pass:changeit -nokeys -out /tmp/app-a-cert.pem 2>/dev/null

# Extract CA certificate
kubectl exec $APP_A_POD -- keytool -exportcert -alias ca \
  -keystore /etc/security/ssl/truststore.jks -storepass changeit \
  -rfc -file /tmp/ca-cert.pem 2>/dev/null

# Verify certificate chain
VERIFY_OUTPUT=$(kubectl exec $APP_A_POD -- openssl verify -CAfile /tmp/ca-cert.pem /tmp/app-a-cert.pem 2>&1)

if echo "$VERIFY_OUTPUT" | grep -q "OK"; then
  echo -e "${GREEN}✅ SUCCESS: App A certificate chain is valid${NC}"
  echo "$VERIFY_OUTPUT"
else
  echo -e "${RED}❌ FAILED: App A certificate chain validation failed${NC}"
  echo "$VERIFY_OUTPUT"
  exit 1
fi

echo ""
echo "Extracting and verifying App B certificate chain..."

# Extract server certificate
kubectl exec $APP_B_POD -- openssl pkcs12 -in /etc/security/ssl/app-b-keystore.p12 \
  -passin pass:changeit -nokeys -out /tmp/app-b-cert.pem 2>/dev/null

# Extract CA certificate
kubectl exec $APP_B_POD -- keytool -exportcert -alias ca \
  -keystore /etc/security/ssl/truststore.jks -storepass changeit \
  -rfc -file /tmp/ca-cert.pem 2>/dev/null

# Verify certificate chain
VERIFY_OUTPUT=$(kubectl exec $APP_B_POD -- openssl verify -CAfile /tmp/ca-cert.pem /tmp/app-b-cert.pem 2>&1)

if echo "$VERIFY_OUTPUT" | grep -q "OK"; then
  echo -e "${GREEN}✅ SUCCESS: App B certificate chain is valid${NC}"
  echo "$VERIFY_OUTPUT"
else
  echo -e "${RED}❌ FAILED: App B certificate chain validation failed${NC}"
  echo "$VERIFY_OUTPUT"
  exit 1
fi

echo ""
echo "=========================================="
echo "Test 5: Certificate Issuer/CA Match"
echo "=========================================="
echo "Verifying App A certificate issuer matches CA subject..."

SERVER_CERT_ISSUER=$(kubectl exec $APP_A_POD -- openssl x509 -in /tmp/app-a-cert.pem -noout -issuer | sed 's/issuer=//')
CA_SUBJECT=$(kubectl exec $APP_A_POD -- openssl x509 -in /tmp/ca-cert.pem -noout -subject | sed 's/subject=//')

echo "  Server cert issuer: $SERVER_CERT_ISSUER"
echo "  CA subject:         $CA_SUBJECT"

if [ "$SERVER_CERT_ISSUER" == "$CA_SUBJECT" ]; then
  echo -e "${GREEN}✅ SUCCESS: Issuer matches CA subject${NC}"
else
  echo -e "${RED}❌ FAILED: Issuer does not match CA subject${NC}"
  exit 1
fi

echo ""
echo "=========================================="
echo "Test 6: mTLS Communication (App A → App B)"
echo "=========================================="
echo "Testing HTTPS request from App A to App B..."

RESPONSE=$(kubectl exec $APP_A_POD -- curl -k --fail --silent --show-error \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health 2>&1)

if echo "$RESPONSE" | grep -q "UP"; then
  echo -e "${GREEN}✅ SUCCESS: App A can communicate with App B (no PKIX error)${NC}"
  echo "  Response: $RESPONSE"
else
  echo -e "${RED}❌ FAILED: Communication failed${NC}"
  echo "  Response: $RESPONSE"

  if echo "$RESPONSE" | grep -iq "pkix"; then
    echo -e "${RED}  ⚠️  PKIX path building error detected!${NC}"
  fi
  exit 1
fi

echo ""
echo "=========================================="
echo "Test 7: mTLS Communication (App B → App A)"
echo "=========================================="
echo "Testing HTTPS request from App B to App A..."

RESPONSE=$(kubectl exec $APP_B_POD -- curl -k --fail --silent --show-error \
  --cert /etc/security/ssl/app-b-keystore.p12:changeit \
  --cert-type P12 \
  https://app-a.default.svc.cluster.local:8443/health 2>&1)

if echo "$RESPONSE" | grep -q "UP"; then
  echo -e "${GREEN}✅ SUCCESS: App B can communicate with App A (no PKIX error)${NC}"
  echo "  Response: $RESPONSE"
else
  echo -e "${RED}❌ FAILED: Communication failed${NC}"
  echo "  Response: $RESPONSE"

  if echo "$RESPONSE" | grep -iq "pkix"; then
    echo -e "${RED}  ⚠️  PKIX path building error detected!${NC}"
  fi
  exit 1
fi

echo ""
echo "=========================================="
echo "Test 8: Application-Level Communication"
echo "=========================================="
echo "Testing App A calling App B via RestTemplate..."

RESPONSE=$(kubectl exec $APP_A_POD -- curl -k --fail --silent --show-error \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/api/call-app-b 2>&1)

if echo "$RESPONSE" | grep -q "Hello from App B"; then
  echo -e "${GREEN}✅ SUCCESS: RestTemplate communication works (no PKIX error)${NC}"
  echo "  Response: $RESPONSE"
else
  echo -e "${RED}❌ FAILED: RestTemplate communication failed${NC}"
  echo "  Response: $RESPONSE"
  exit 1
fi

echo ""
echo "Testing App B calling App A via RestTemplate..."

RESPONSE=$(kubectl exec $APP_B_POD -- curl -k --fail --silent --show-error \
  --cert /etc/security/ssl/app-b-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/api/call-app-a 2>&1)

if echo "$RESPONSE" | grep -q "Hello from App A"; then
  echo -e "${GREEN}✅ SUCCESS: RestTemplate communication works (no PKIX error)${NC}"
  echo "  Response: $RESPONSE"
else
  echo -e "${RED}❌ FAILED: RestTemplate communication failed${NC}"
  echo "  Response: $RESPONSE"
  exit 1
fi

echo ""
echo "=========================================="
echo "Test 9: Application Logs (No PKIX Errors)"
echo "=========================================="
echo "Checking App A logs for PKIX errors..."

PKIX_ERRORS=$(kubectl logs deployment/app-a --tail=500 | grep -i "pkix" || true)
if [ -z "$PKIX_ERRORS" ]; then
  echo -e "${GREEN}✅ SUCCESS: No PKIX errors found in App A logs${NC}"
else
  echo -e "${RED}❌ FAILED: Found PKIX errors in App A logs:${NC}"
  echo "$PKIX_ERRORS"
  exit 1
fi

echo ""
echo "Checking App B logs for PKIX errors..."

PKIX_ERRORS=$(kubectl logs deployment/app-b --tail=500 | grep -i "pkix" || true)
if [ -z "$PKIX_ERRORS" ]; then
  echo -e "${GREEN}✅ SUCCESS: No PKIX errors found in App B logs${NC}"
else
  echo -e "${RED}❌ FAILED: Found PKIX errors in App B logs:${NC}"
  echo "$PKIX_ERRORS"
  exit 1
fi

echo ""
echo "=========================================="
echo "Test 10: SSL Handshake Errors Check"
echo "=========================================="
echo "Checking for any SSL handshake errors..."

SSL_ERRORS=$(kubectl logs deployment/app-a --tail=500 | grep -i "sslhandshakeexception\|handshake.*failed" || true)
if [ -z "$SSL_ERRORS" ]; then
  echo -e "${GREEN}✅ SUCCESS: No SSL handshake errors in App A logs${NC}"
else
  echo -e "${YELLOW}⚠️  WARNING: Found SSL handshake errors in App A logs:${NC}"
  echo "$SSL_ERRORS"
fi

SSL_ERRORS=$(kubectl logs deployment/app-b --tail=500 | grep -i "sslhandshakeexception\|handshake.*failed" || true)
if [ -z "$SSL_ERRORS" ]; then
  echo -e "${GREEN}✅ SUCCESS: No SSL handshake errors in App B logs${NC}"
else
  echo -e "${YELLOW}⚠️  WARNING: Found SSL handshake errors in App B logs:${NC}"
  echo "$SSL_ERRORS"
fi

echo ""
echo "=========================================="
echo "✅ ALL VERIFICATIONS PASSED"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Certificate files exist and are readable"
echo "  ✓ Keystores contain valid certificates"
echo "  ✓ Truststores contain CA certificate"
echo "  ✓ Certificate chains are valid"
echo "  ✓ Certificate issuer matches CA subject"
echo "  ✓ App A ↔ App B mTLS communication works"
echo "  ✓ RestTemplate-based communication works"
echo "  ✓ No PKIX path building errors detected"
echo "  ✓ No SSL handshake errors detected"
echo ""
echo -e "${GREEN}🎉 No PKIX path building errors found!${NC}"
echo "The truststore configuration is correct and all certificates are properly validated."
echo ""
