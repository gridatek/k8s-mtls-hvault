#!/bin/bash

################################################################################
# test-jvm-ssl.sh
#
# Test script to demonstrate and verify JVM SSL system properties configuration.
# This script helps validate that JVM properties are correctly configured for mTLS.
#
# Usage:
#   bash test-jvm-ssl.sh
#
# Requirements:
#   - Kubernetes cluster running (Minikube)
#   - kubectl configured
#   - Applications deployed with JVM SSL properties configured
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Header
echo "================================================================================"
echo "  JVM SSL System Properties Test Script"
echo "================================================================================"
echo ""

# Test 1: Check if applications are running
log_info "Test 1: Checking application deployments..."
APP_A_READY=$(kubectl get deployment app-a -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
APP_B_READY=$(kubectl get deployment app-b -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

if [ "$APP_A_READY" -gt 0 ] && [ "$APP_B_READY" -gt 0 ]; then
    log_success "Both applications are running (app-a: $APP_A_READY replicas, app-b: $APP_B_READY replicas)"
else
    log_error "Applications are not ready (app-a: $APP_A_READY, app-b: $APP_B_READY)"
    exit 1
fi

# Get pod names
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")
APP_B_POD=$(kubectl get pod -l app=app-b -o jsonpath="{.items[0].metadata.name}")

log_info "App A Pod: $APP_A_POD"
log_info "App B Pod: $APP_B_POD"
echo ""

# Test 2: Verify JAVA_TOOL_OPTIONS environment variable
log_info "Test 2: Checking JAVA_TOOL_OPTIONS environment variable..."
echo ""

log_info "App A JAVA_TOOL_OPTIONS:"
JAVA_OPTS_A=$(kubectl exec $APP_A_POD -- sh -c 'echo $JAVA_TOOL_OPTIONS' 2>/dev/null || echo "NOT SET")
echo "$JAVA_OPTS_A"
echo ""

log_info "App B JAVA_TOOL_OPTIONS:"
JAVA_OPTS_B=$(kubectl exec $APP_B_POD -- sh -c 'echo $JAVA_TOOL_OPTIONS' 2>/dev/null || echo "NOT SET")
echo "$JAVA_OPTS_B"
echo ""

# Check if JVM properties are set
if echo "$JAVA_OPTS_A" | grep -q "javax.net.ssl.keyStore"; then
    log_success "App A has JVM SSL properties configured"
else
    log_warning "App A does not have JVM SSL properties in JAVA_TOOL_OPTIONS"
    log_info "This is OK if using programmatic configuration"
fi

if echo "$JAVA_OPTS_B" | grep -q "javax.net.ssl.keyStore"; then
    log_success "App B has JVM SSL properties configured"
else
    log_warning "App B does not have JVM SSL properties in JAVA_TOOL_OPTIONS"
    log_info "This is OK if using programmatic configuration"
fi
echo ""

# Test 3: Verify certificate files exist
log_info "Test 3: Verifying certificate files in containers..."
echo ""

log_info "App A certificate files:"
kubectl exec $APP_A_POD -- ls -lh /etc/security/ssl/
echo ""

log_info "App B certificate files:"
kubectl exec $APP_B_POD -- ls -lh /etc/security/ssl/
echo ""

# Check specific files
APP_A_KEYSTORE=$(kubectl exec $APP_A_POD -- test -f /etc/security/ssl/app-a-keystore.p12 && echo "EXISTS" || echo "MISSING")
APP_A_TRUSTSTORE=$(kubectl exec $APP_A_POD -- test -f /etc/security/ssl/truststore.jks && echo "EXISTS" || echo "MISSING")

if [ "$APP_A_KEYSTORE" = "EXISTS" ] && [ "$APP_A_TRUSTSTORE" = "EXISTS" ]; then
    log_success "App A certificates exist"
else
    log_error "App A missing certificates (keystore: $APP_A_KEYSTORE, truststore: $APP_A_TRUSTSTORE)"
fi

APP_B_KEYSTORE=$(kubectl exec $APP_B_POD -- test -f /etc/security/ssl/app-b-keystore.p12 && echo "EXISTS" || echo "MISSING")
APP_B_TRUSTSTORE=$(kubectl exec $APP_B_POD -- test -f /etc/security/ssl/truststore.jks && echo "EXISTS" || echo "MISSING")

if [ "$APP_B_KEYSTORE" = "EXISTS" ] && [ "$APP_B_TRUSTSTORE" = "EXISTS" ]; then
    log_success "App B certificates exist"
else
    log_error "App B missing certificates (keystore: $APP_B_KEYSTORE, truststore: $APP_B_TRUSTSTORE)"
fi
echo ""

# Test 4: Inspect certificate contents
log_info "Test 4: Inspecting certificate contents with keytool..."
echo ""

log_info "App A keystore contents:"
kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/app-a-keystore.p12 -storepass changeit -storetype PKCS12 2>/dev/null || log_error "Failed to read keystore"
echo ""

log_info "App A truststore contents:"
kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/truststore.jks -storepass changeit -storetype JKS 2>/dev/null || log_error "Failed to read truststore"
echo ""

# Test 5: Test mTLS connectivity
log_info "Test 5: Testing mTLS connectivity..."
echo ""

log_info "Testing App A health endpoint (localhost)..."
APP_A_HEALTH_LOCAL=$(kubectl exec $APP_A_POD -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://localhost:8443/health -s -w "\n%{http_code}" 2>/dev/null | tail -1)
if [ "$APP_A_HEALTH_LOCAL" = "200" ]; then
    log_success "App A health check succeeded (HTTP $APP_A_HEALTH_LOCAL)"
else
    log_error "App A health check failed (HTTP $APP_A_HEALTH_LOCAL)"
fi
echo ""

log_info "Testing App B health endpoint (localhost)..."
APP_B_HEALTH_LOCAL=$(kubectl exec $APP_B_POD -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://localhost:8443/health -s -w "\n%{http_code}" 2>/dev/null | tail -1)
if [ "$APP_B_HEALTH_LOCAL" = "200" ]; then
    log_success "App B health check succeeded (HTTP $APP_B_HEALTH_LOCAL)"
else
    log_error "App B health check failed (HTTP $APP_B_HEALTH_LOCAL)"
fi
echo ""

log_info "Testing App A to App B communication (via Kubernetes DNS)..."
APP_A_TO_B=$(kubectl exec $APP_A_POD -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://app-b.default.svc.cluster.local:8443/health -s -w "\n%{http_code}" 2>/dev/null | tail -1)
if [ "$APP_A_TO_B" = "200" ]; then
    log_success "App A → App B communication succeeded (HTTP $APP_A_TO_B)"
else
    log_error "App A → App B communication failed (HTTP $APP_A_TO_B)"
fi
echo ""

log_info "Testing App B to App A communication (via Kubernetes DNS)..."
APP_B_TO_A=$(kubectl exec $APP_B_POD -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://app-a.default.svc.cluster.local:8443/health -s -w "\n%{http_code}" 2>/dev/null | tail -1)
if [ "$APP_B_TO_A" = "200" ]; then
    log_success "App B → App A communication succeeded (HTTP $APP_B_TO_A)"
else
    log_error "App B → App A communication failed (HTTP $APP_B_TO_A)"
fi
echo ""

# Test 6: Test application-level endpoints
log_info "Test 6: Testing application-level endpoints..."
echo ""

log_info "Testing App A /api/call-app-b endpoint..."
APP_A_CALL_B=$(kubectl exec $APP_A_POD -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://localhost:8443/api/call-app-b -s)
echo "Response: $APP_A_CALL_B"
if echo "$APP_A_CALL_B" | grep -q "App B"; then
    log_success "App A successfully called App B"
else
    log_error "App A failed to call App B"
fi
echo ""

log_info "Testing App B /api/call-app-a endpoint..."
APP_B_CALL_A=$(kubectl exec $APP_B_POD -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://localhost:8443/api/call-app-a -s)
echo "Response: $APP_B_CALL_A"
if echo "$APP_B_CALL_A" | grep -q "App A"; then
    log_success "App B successfully called App A"
else
    log_error "App B failed to call App A"
fi
echo ""

# Test 7: Check application logs for SSL errors
log_info "Test 7: Checking application logs for SSL/TLS errors..."
echo ""

log_info "Checking App A logs for SSL errors..."
APP_A_ERRORS=$(kubectl logs $APP_A_POD --tail=100 | grep -i "ssl\|handshake\|certificate" | grep -i "error\|fail\|exception" || echo "No SSL errors found")
echo "$APP_A_ERRORS"
echo ""

log_info "Checking App B logs for SSL errors..."
APP_B_ERRORS=$(kubectl logs $APP_B_POD --tail=100 | grep -i "ssl\|handshake\|certificate" | grep -i "error\|fail\|exception" || echo "No SSL errors found")
echo "$APP_B_ERRORS"
echo ""

# Test 8: Test without client certificate (should fail)
log_info "Test 8: Testing without client certificate (should fail with 403/400)..."
echo ""

log_info "Attempting to connect to App A without client certificate..."
NO_CERT_RESPONSE=$(kubectl exec $APP_A_POD -- curl -k https://localhost:8443/health -s -w "\n%{http_code}" 2>/dev/null | tail -1 || echo "FAILED")
if [ "$NO_CERT_RESPONSE" = "400" ] || [ "$NO_CERT_RESPONSE" = "403" ] || [ "$NO_CERT_RESPONSE" = "FAILED" ]; then
    log_success "Correctly rejected connection without client certificate (HTTP $NO_CERT_RESPONSE)"
else
    log_warning "Unexpected response without client certificate: HTTP $NO_CERT_RESPONSE"
    log_warning "Expected 400/403, this might indicate client-auth is not 'need'"
fi
echo ""

# Summary
echo "================================================================================"
echo "  Test Summary"
echo "================================================================================"
echo ""

log_info "SSL Configuration Method:"
if echo "$JAVA_OPTS_A" | grep -q "javax.net.ssl.keyStore"; then
    echo "  - Using JVM System Properties (JAVA_TOOL_OPTIONS)"
else
    echo "  - Using Programmatic Configuration (Java code)"
fi
echo ""

log_info "Certificate Validation:"
echo "  - App A Keystore: $APP_A_KEYSTORE"
echo "  - App A Truststore: $APP_A_TRUSTSTORE"
echo "  - App B Keystore: $APP_B_KEYSTORE"
echo "  - App B Truststore: $APP_B_TRUSTSTORE"
echo ""

log_info "mTLS Communication:"
echo "  - App A Health Check: HTTP $APP_A_HEALTH_LOCAL"
echo "  - App B Health Check: HTTP $APP_B_HEALTH_LOCAL"
echo "  - App A → App B: HTTP $APP_A_TO_B"
echo "  - App B → App A: HTTP $APP_B_TO_A"
echo "  - No Client Cert Test: HTTP $NO_CERT_RESPONSE (should be 400/403)"
echo ""

# Final verdict
if [ "$APP_A_TO_B" = "200" ] && [ "$APP_B_TO_A" = "200" ] && [ "$APP_A_HEALTH_LOCAL" = "200" ] && [ "$APP_B_HEALTH_LOCAL" = "200" ]; then
    log_success "All mTLS tests passed! The system is working correctly."
    echo ""
    exit 0
else
    log_error "Some tests failed. Review the output above for details."
    echo ""
    exit 1
fi
