# Solving javax.net.ssl.SSLHandshakeException: PKIX Path Building Failed

## Table of Contents
1. [Understanding the Error](#understanding-the-error)
2. [Root Causes](#root-causes)
3. [How This Repository Prevents the Error](#how-this-repository-prevents-the-error)
4. [Reproducing the Error](#reproducing-the-error)
5. [Solution Implementation](#solution-implementation)
6. [Verification Steps](#verification-steps)
7. [Troubleshooting Guide](#troubleshooting-guide)

---

## Understanding the Error

### Complete Error Stack Trace
```
javax.net.ssl.SSLHandshakeException: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
    at java.base/sun.security.ssl.Alert.createSSLException(Alert.java:131)
    at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:371)
    at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:314)
    at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:309)
    at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.checkServerCerts(CertificateMessage.java:654)
    at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.onCertificate(CertificateMessage.java:473)
    at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.consume(CertificateMessage.java:369)
    at java.base/sun.security.ssl.SSLHandshake.consume(SSLHandshake.java:392)
    at java.base/sun.security.ssl.HandshakeContext.dispatch(HandshakeContext.java:443)
    at java.base/sun.security.ssl.SSLEngineImpl$DelegatedTask$DelegatedAction.run(SSLEngineImpl.java:1074)
    at java.base/sun.security.ssl.SSLEngineImpl$DelegatedTask$DelegatedAction.run(SSLEngineImpl.java:1061)
    ...
Caused by: sun.security.validator.ValidatorException: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
    at java.base/sun.security.validator.PKIXValidator.doBuild(PKIXValidator.java:439)
    at java.base/sun.security.validator.PKIXValidator.engineValidate(PKIXValidator.java:306)
    at java.base/sun.security.validator.Validator.validate(Validator.java:264)
    at java.base/sun.security.ssl.X509TrustManagerImpl.checkTrusted(X509TrustManagerImpl.java:231)
    at java.base/sun.security.ssl.X509TrustManagerImpl.checkServerTrusted(X509TrustManagerImpl.java:132)
    at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.checkServerCerts(CertificateMessage.java:638)
    ... 25 more
Caused by: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
    at java.base/sun.security.provider.certpath.SunCertPathBuilder.build(SunCertPathBuilder.java:141)
    at java.base/sun.security.provider.certpath.SunCertPathBuilder.engineBuild(SunCertPathBuilder.java:126)
    at java.base/java.security.cert.CertPathBuilder.build(CertPathBuilder.java:297)
    at java.base/sun.security.validator.PKIXValidator.doBuild(PKIXValidator.java:434)
    ... 30 more
```

### What This Means

The error occurs during the **TLS handshake** when the client tries to validate the server's certificate:

```
Client                                Server
  |                                      |
  |--- ClientHello ------------------>  |
  |<-- ServerHello, Certificate -------|  Server sends its certificate
  |                                      |
  |  ❌ PKIX Path Building Failed      |
  |     Cannot validate cert!           |
  |                                      |
  X  Connection fails                   X
```

**The client cannot build a "certification path"** from the server's certificate to a trusted root CA in its truststore.

---

## Root Causes

### 1. Missing CA Certificate in Truststore

**Problem**: The CA that signed the server's certificate is not in the client's truststore.

```
Server Certificate Chain:
┌──────────────────────────────┐
│ Server Cert (app-b)          │ ← Presented by server
│ Issued by: K8s CA            │
└──────────────────────────────┘
           ↓ signed by
┌──────────────────────────────┐
│ K8s CA Certificate           │ ← MUST be in client's truststore
│ Self-signed root CA          │
└──────────────────────────────┘

Client Truststore:
┌──────────────────────────────┐
│ ???                          │ ← If K8s CA is missing → PKIX error!
└──────────────────────────────┘
```

### 2. Wrong Truststore Path

**Problem**: Application can't find the truststore file.

```yaml
# application.yml - WRONG PATH
server:
  ssl:
    trust-store: file:/wrong/path/truststore.jks  # ❌ File not found
    trust-store-password: changeit
```

**Result**: Truststore is empty, no CAs are trusted → PKIX error.

### 3. Wrong Truststore Password

**Problem**: Password is incorrect, truststore cannot be loaded.

```yaml
# application.yml - WRONG PASSWORD
server:
  ssl:
    trust-store: file:/etc/security/ssl/truststore.jks
    trust-store-password: wrongpassword  # ❌ Cannot decrypt
```

**Result**: Cannot read CA certificates → PKIX error.

### 4. Incomplete Certificate Chain

**Problem**: Server sends certificate without intermediate CAs.

```
What server should send:
┌──────────────────────────────┐
│ Server Cert                  │
│ Intermediate CA (if any)     │
│ Root CA                      │
└──────────────────────────────┘

What server actually sends:
┌──────────────────────────────┐
│ Server Cert                  │ ← Only leaf cert, chain incomplete!
└──────────────────────────────┘
```

**Result**: Client cannot build path to trusted root → PKIX error.

### 5. Using Java's Default Truststore (cacerts)

**Problem**: Trying to validate internal certificates using the JVM's default truststore.

```bash
# Java default truststore location
$JAVA_HOME/lib/security/cacerts

# Contains public CAs like:
- DigiCert, Let's Encrypt, VeriSign, etc.

# Does NOT contain:
- Your internal CA (K8s CA)
- Self-signed certificates
```

**Result**: Internal/self-signed certs are not trusted → PKIX error.

---

## How This Repository Prevents the Error

This repository implements a **complete certificate chain management solution** that prevents PKIX errors:

### 1. Certificate Generation with Shared CA

**File**: `k8s/scripts/generate-certs.sh`

```bash
# Step 1: Generate Root CA (lines 26-31)
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem \
  -out ca-cert.pem \
  -subj "/C=US/ST=State/L=City/O=K8S/OU=CA/CN=k8s-ca"

# Step 2: Generate App A Certificate SIGNED by CA (lines 34-62)
openssl genrsa -out app-a-key.pem 2048
openssl req -new -key app-a-key.pem -out app-a.csr \
  -subj "/C=US/ST=State/L=City/O=K8S/OU=AppA/CN=app-a.default.svc.cluster.local"

# Sign with CA - creates valid certificate chain
openssl x509 -req -in app-a.csr -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out app-a-cert.pem -days 365

# Step 3: Create PKCS12 keystore with certificate chain
openssl pkcs12 -export -in app-a-cert.pem -inkey app-a-key.pem \
  -out app-a-keystore.p12 -name app-a -passout pass:changeit

# Step 4: Create SHARED TRUSTSTORE with CA certificate
keytool -import -trustcacerts -file ca-cert.pem -alias ca \
  -keystore truststore.jks -storepass changeit -noprompt
```

**Key Point**: Both App A and App B share the same `truststore.jks` containing the CA certificate.

### 2. Certificate Distribution via Vault

**File**: `k8s/scripts/upload-certs-to-vault.sh`

```bash
# Upload App A keystore + SHARED truststore
vault kv put secret/app-a \
  ssl.keystore="$(base64 -w 0 app-a-keystore.p12)" \
  ssl.truststore="$(base64 -w 0 truststore.jks)" \
  ssl.keystore-password="changeit" \
  ssl.truststore-password="changeit"

# Upload App B keystore + SAME SHARED truststore
vault kv put secret/app-b \
  ssl.keystore="$(base64 -w 0 app-b-keystore.p12)" \
  ssl.truststore="$(base64 -w 0 truststore.jks)" \
  ssl.keystore-password="changeit" \
  ssl.truststore-password="changeit"
```

**Key Point**: Both applications receive the same truststore containing the shared CA.

### 3. Init Container Certificate Retrieval

**File**: `k8s/manifests/app-a-deployment.yaml` (lines 25-50)

```yaml
initContainers:
- name: vault-init
  image: hashicorp/vault:1.15.4
  command:
  - /bin/sh
  - -c
  - |
    # Authenticate with Vault
    VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login role=app-a jwt=$SA_TOKEN)

    # Retrieve and decode TRUSTSTORE (contains CA cert)
    vault kv get -field=ssl.truststore secret/app-a | base64 -d > /etc/security/ssl/truststore.jks

    # Retrieve keystore
    vault kv get -field=ssl.keystore secret/app-a | base64 -d > /etc/security/ssl/app-a-keystore.p12
  volumeMounts:
  - name: ssl-certs
    mountPath: /etc/security/ssl
```

**Key Point**: Truststore is written to `/etc/security/ssl/truststore.jks` before application starts.

### 4. Spring Boot Truststore Configuration

**File**: `app-a/src/main/resources/application.yml` (lines 1-12)

```yaml
server:
  port: 8443
  ssl:
    enabled: true
    key-store: file:/etc/security/ssl/app-a-keystore.p12
    key-store-password: ${ssl.keystore-password}
    key-store-type: ${ssl.keystore-type}
    key-alias: ${ssl.key-alias}
    trust-store: file:/etc/security/ssl/truststore.jks  # ← Prevents PKIX error
    trust-store-password: ${ssl.truststore-password}
    trust-store-type: ${ssl.truststore-type}
    client-auth: need
```

**Key Point**: Line 9 explicitly sets the truststore path. Spring Boot will use this instead of Java's default cacerts.

### 5. RestTemplate Client Configuration

**File**: `app-a/src/main/java/com/k8s/appa/AppAApplication.java` (lines 35-38)

```java
@Bean
public RestTemplate restTemplate(
        @Value("${server.ssl.trust-store}") Resource trustStore,
        @Value("${server.ssl.trust-store-password}") String trustStorePassword) throws Exception {

    SSLContext sslContext = SSLContextBuilder.create()
            .loadKeyMaterial(keyStore.getURL(), keyStorePassword.toCharArray(), keyStorePassword.toCharArray())
            .loadTrustMaterial(trustStore.getURL(), trustStorePassword.toCharArray())  // ← Prevents PKIX error
            .build();

    SSLConnectionSocketFactory sslSocketFactory = new SSLConnectionSocketFactory(sslContext);
    // ... configure RestTemplate with custom SSLContext
}
```

**Key Point**: Line 37 loads the truststore into the SSL context for outgoing HTTPS requests.

### Certificate Chain Validation Flow

```
App A calls App B via RestTemplate:

1. App A initiates HTTPS connection to app-b.default.svc.cluster.local:8443

2. App B (server) sends its certificate:
   ┌──────────────────────────────────────┐
   │ Subject: CN=app-b.default.svc...     │
   │ Issuer: CN=k8s-ca                    │
   │ Serial: 1234567890                   │
   └──────────────────────────────────────┘

3. App A (client) validates the certificate:

   a) Extract issuer from certificate: "CN=k8s-ca"

   b) Search truststore.jks for matching CA:
      ┌──────────────────────────────────────┐
      │ Alias: ca                            │
      │ Subject: CN=k8s-ca                   │ ✅ MATCH FOUND!
      │ Trusted: Yes                         │
      └──────────────────────────────────────┘

   c) Verify server cert signature using CA's public key: ✅ Valid

   d) Check certificate validity dates: ✅ Valid

   e) Check SAN matches hostname: ✅ app-b.default.svc.cluster.local in SAN list

4. ✅ Certificate chain validation successful!

5. mTLS handshake continues (App A presents its certificate to App B)

6. Secure connection established
```

---

## Reproducing the Error

To understand the error better, let's intentionally break the configuration:

### Scenario 1: Missing Truststore

**Modify** `app-a/src/main/resources/application.yml`:

```yaml
server:
  ssl:
    # Comment out truststore configuration
    # trust-store: file:/etc/security/ssl/truststore.jks
    # trust-store-password: ${ssl.truststore-password}
```

**Result**: App A will use Java's default cacerts, which doesn't contain the K8s CA.

**Test**:
```bash
kubectl exec -it deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://app-b.default.svc.cluster.local:8443/health
```

**Expected Error**:
```
javax.net.ssl.SSLHandshakeException: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
```

### Scenario 2: Wrong Truststore Path

**Modify** `app-a/src/main/resources/application.yml`:

```yaml
server:
  ssl:
    trust-store: file:/wrong/path/truststore.jks  # ❌ Wrong path
    trust-store-password: ${ssl.truststore-password}
```

**Result**: FileNotFoundException → truststore cannot be loaded → PKIX error.

**Logs**:
```
Caused by: java.io.FileNotFoundException: /wrong/path/truststore.jks (No such file or directory)
    at java.base/java.io.FileInputStream.open0(Native Method)
    at java.base/java.io.FileInputStream.open(FileInputStream.java:219)
    ...
```

### Scenario 3: Wrong Truststore Password

**Modify** `app-a/src/main/resources/application.yml`:

```yaml
server:
  ssl:
    trust-store: file:/etc/security/ssl/truststore.jks
    trust-store-password: wrongpassword  # ❌ Wrong password
```

**Result**: Truststore cannot be decrypted → PKIX error.

**Logs**:
```
Caused by: java.io.IOException: Keystore was tampered with, or password was incorrect
    at java.base/sun.security.provider.JavaKeyStore.engineLoad(JavaKeyStore.java:792)
    at java.base/sun.security.provider.JavaKeyStore$JKS.engineLoad(JavaKeyStore.java:57)
    ...
```

### Scenario 4: Missing CA in Truststore

**Create a truststore without the CA**:

```bash
# Create empty truststore
keytool -genkeypair -alias dummy -keyalg RSA -keysize 2048 \
  -keystore empty-truststore.jks -storepass changeit \
  -dname "CN=Dummy"

# Delete the dummy entry
keytool -delete -alias dummy -keystore empty-truststore.jks -storepass changeit

# Upload to Vault
vault kv put secret/app-a \
  ssl.truststore="$(base64 -w 0 empty-truststore.jks)"
```

**Result**: Truststore exists but doesn't contain the CA → PKIX error.

---

## Solution Implementation

The repository already implements all the necessary components. Here's a step-by-step guide:

### Step 1: Deploy the Complete Infrastructure

```bash
cd k8s/scripts

# This will:
# 1. Deploy Vault
# 2. Generate certificates with shared CA
# 3. Create truststore with CA certificate
# 4. Upload certificates to Vault
# 5. Deploy applications with proper configuration
bash deploy.sh
```

### Step 2: Verify Certificate Chain

```bash
# Get App A pod name
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")

# View keystore contents (server certificate)
kubectl exec $APP_A_POD -- keytool -list -v -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12

# Look for:
# - Alias name: app-a
# - Certificate chain length: 1
# - Owner: CN=app-a.default.svc.cluster.local
# - Issuer: CN=k8s-ca  ← Must match CA in truststore

# View truststore contents (CA certificate)
kubectl exec $APP_A_POD -- keytool -list -v -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS

# Look for:
# - Alias name: ca
# - Owner: CN=k8s-ca  ← Must match issuer of server cert
# - Entry type: trustedCertEntry
```

### Step 3: Verify Certificate Chain Matches

```bash
# Extract server certificate issuer
SERVER_CERT_ISSUER=$(kubectl exec $APP_A_POD -- keytool -list -v \
  -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12 | grep "Issuer:" | head -1)

echo "Server certificate issuer: $SERVER_CERT_ISSUER"
# Output: Issuer: CN=k8s-ca, OU=CA, O=K8S, L=City, ST=State, C=US

# Extract truststore CA subject
CA_SUBJECT=$(kubectl exec $APP_A_POD -- keytool -list -v \
  -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS | grep "Owner:" | head -1)

echo "Truststore CA subject: $CA_SUBJECT"
# Output: Owner: CN=k8s-ca, OU=CA, O=K8S, L=City, ST=State, C=US

# These should match! (Issuer of server cert == Subject of CA in truststore)
```

### Step 4: Test mTLS Communication

```bash
# Test App A calling App B (no PKIX error should occur)
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health

# Expected output: {"status":"UP"}

# Test via application endpoint (uses RestTemplate with truststore)
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/api/call-app-b

# Expected output: Hello from App A! Response from App B: Hello from App B!
```

### Step 5: Check Application Logs (No PKIX Errors)

```bash
# View App A logs
kubectl logs deployment/app-a | grep -i "pkix\|ssl\|handshake"

# You should see successful SSL initialization:
# - "Using SSL"
# - "Connector[https-jsse-nio-8443], TLS virtual host [_default_], certificate type [UNDEFINED] configured"
# - No PKIX errors
```

---

## Verification Steps

### Automated Verification Script

Create `k8s/scripts/verify-no-pkix-error.sh`:

```bash
#!/bin/bash

set -e

echo "=========================================="
echo "PKIX Error Prevention Verification"
echo "=========================================="

# Get pod names
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")
APP_B_POD=$(kubectl get pod -l app=app-b -o jsonpath="{.items[0].metadata.name}")

echo ""
echo "1. Verifying certificate files exist..."
kubectl exec $APP_A_POD -- ls -lh /etc/security/ssl/
kubectl exec $APP_B_POD -- ls -lh /etc/security/ssl/

echo ""
echo "2. Verifying keystore contains valid certificate..."
kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12 | grep "app-a"

echo ""
echo "3. Verifying truststore contains CA certificate..."
kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS | grep "ca,"

echo ""
echo "4. Testing App A → App B communication (no PKIX error expected)..."
RESPONSE=$(kubectl exec $APP_A_POD -- curl -k --fail --silent \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health)

if [[ "$RESPONSE" == *"UP"* ]]; then
  echo "✅ SUCCESS: App A can communicate with App B without PKIX error"
else
  echo "❌ FAILED: Unexpected response: $RESPONSE"
  exit 1
fi

echo ""
echo "5. Testing App B → App A communication (no PKIX error expected)..."
RESPONSE=$(kubectl exec $APP_B_POD -- curl -k --fail --silent \
  --cert /etc/security/ssl/app-b-keystore.p12:changeit \
  --cert-type P12 \
  https://app-a.default.svc.cluster.local:8443/health)

if [[ "$RESPONSE" == *"UP"* ]]; then
  echo "✅ SUCCESS: App B can communicate with App A without PKIX error"
else
  echo "❌ FAILED: Unexpected response: $RESPONSE"
  exit 1
fi

echo ""
echo "6. Checking application logs for PKIX errors..."
PKIX_ERRORS=$(kubectl logs deployment/app-a --tail=500 | grep -i "pkix" || true)
if [ -z "$PKIX_ERRORS" ]; then
  echo "✅ SUCCESS: No PKIX errors found in App A logs"
else
  echo "❌ FAILED: Found PKIX errors in App A logs:"
  echo "$PKIX_ERRORS"
  exit 1
fi

echo ""
echo "=========================================="
echo "✅ ALL VERIFICATIONS PASSED"
echo "No PKIX path building errors detected!"
echo "=========================================="
```

### Run Verification

```bash
cd k8s/scripts
bash verify-no-pkix-error.sh
```

---

## Troubleshooting Guide

### Symptom 1: PKIX Error in Application Logs

**Logs**:
```
javax.net.ssl.SSLHandshakeException: PKIX path building failed:
sun.security.provider.certpath.SunCertPathBuilderException:
unable to find valid certification path to requested target
```

**Diagnosis Steps**:

```bash
# Step 1: Check if truststore file exists
kubectl exec $APP_A_POD -- ls -lh /etc/security/ssl/truststore.jks

# Step 2: Check if truststore is readable
kubectl exec $APP_A_POD -- keytool -list -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS

# Step 3: Verify CA is in truststore
kubectl exec $APP_A_POD -- keytool -list -v -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS | grep -A 5 "Alias name: ca"

# Step 4: Check application.yml configuration
kubectl exec $APP_A_POD -- cat /app/application.yml | grep trust-store
```

**Common Fixes**:

1. **Truststore file missing**: Re-run init container or redeploy
   ```bash
   kubectl rollout restart deployment/app-a
   ```

2. **Wrong truststore password in Vault**:
   ```bash
   VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")
   kubectl exec $VAULT_POD -- env VAULT_TOKEN=root \
     vault kv get -format=json secret/app-a | jq -r '.data.data."ssl.truststore-password"'
   # Should output: changeit
   ```

3. **CA certificate missing from truststore**:
   ```bash
   cd k8s/scripts
   bash upload-certs-to-vault.sh  # Re-upload with correct truststore
   kubectl rollout restart deployment/app-a
   ```

### Symptom 2: Certificate Chain Validation Failed

**Logs**:
```
Certificate chaining error
```

**Diagnosis**:

```bash
# Check server certificate issuer
kubectl exec $APP_A_POD -- keytool -list -v \
  -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12 | grep "Issuer:"

# Check CA in truststore
kubectl exec $APP_A_POD -- keytool -list -v \
  -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS | grep "Owner:"

# These should match!
```

**Fix**: Regenerate certificates with matching CA:

```bash
cd k8s/scripts
bash generate-certs.sh      # Regenerate all certificates
bash upload-certs-to-vault.sh  # Upload to Vault
kubectl rollout restart deployment/app-a
kubectl rollout restart deployment/app-b
```

### Symptom 3: Init Container Fails to Retrieve Truststore

**Pod Status**: `Init:Error` or `Init:CrashLoopBackOff`

**Diagnosis**:

```bash
# Check init container logs
kubectl logs $APP_A_POD -c vault-init

# Check if truststore exists in Vault
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root \
  vault kv get -format=json secret/app-a | jq -r '.data.data | keys'

# Should include: ssl.truststore
```

**Fix**: Upload truststore to Vault:

```bash
cd k8s/scripts
bash upload-certs-to-vault.sh
```

### Symptom 4: Wrong CA in Truststore

**Scenario**: Truststore contains a different CA than the one that signed server certificates.

**Diagnosis**:

```bash
# Compare certificate fingerprints
# 1. Get server cert's issuer fingerprint (the CA that signed it)
kubectl exec $APP_A_POD -- openssl pkcs12 -in /etc/security/ssl/app-a-keystore.p12 \
  -passin pass:changeit -nokeys -out /tmp/server-cert.pem

kubectl exec $APP_A_POD -- openssl x509 -in /tmp/server-cert.pem \
  -noout -issuer_hash

# 2. Get CA fingerprint from truststore
kubectl exec $APP_A_POD -- keytool -exportcert -alias ca \
  -keystore /etc/security/ssl/truststore.jks -storepass changeit \
  -rfc -file /tmp/ca-from-truststore.pem

kubectl exec $APP_A_POD -- openssl x509 -in /tmp/ca-from-truststore.pem \
  -noout -subject_hash

# Hashes should match!
```

**Fix**: Ensure all certificates are generated with the same CA:

```bash
cd k8s/scripts

# Delete old certificates
rm -rf ../certs/*

# Regenerate with single CA
bash generate-certs.sh
bash upload-certs-to-vault.sh

# Redeploy applications
kubectl rollout restart deployment/app-a
kubectl rollout restart deployment/app-b
```

---

## Advanced: Debugging Certificate Chains

### Extract and Analyze Certificates

```bash
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")

# 1. Extract server certificate from keystore
kubectl exec $APP_A_POD -- openssl pkcs12 \
  -in /etc/security/ssl/app-a-keystore.p12 \
  -passin pass:changeit -nokeys -out /tmp/app-a-cert.pem

# 2. View server certificate details
kubectl exec $APP_A_POD -- openssl x509 -in /tmp/app-a-cert.pem -text -noout

# Key fields to check:
# - Subject: CN=app-a.default.svc.cluster.local (server identity)
# - Issuer: CN=k8s-ca (CA that signed this cert)
# - Subject Alternative Name: DNS:app-a.default.svc.cluster.local

# 3. Extract CA certificate from truststore
kubectl exec $APP_A_POD -- keytool -exportcert -alias ca \
  -keystore /etc/security/ssl/truststore.jks -storepass changeit \
  -rfc -file /tmp/ca-cert.pem

# 4. View CA certificate details
kubectl exec $APP_A_POD -- openssl x509 -in /tmp/ca-cert.pem -text -noout

# Key fields to check:
# - Subject: CN=k8s-ca (must match issuer of server cert!)
# - Basic Constraints: CA:TRUE (this is a Certificate Authority)

# 5. Verify server cert signature using CA public key
kubectl exec $APP_A_POD -- openssl verify -CAfile /tmp/ca-cert.pem /tmp/app-a-cert.pem

# Expected output: /tmp/app-a-cert.pem: OK
```

### Simulate Certificate Validation

```bash
# This mimics what Java does during PKIX path building:

# 1. Read server certificate issuer
ISSUER=$(kubectl exec $APP_A_POD -- openssl x509 -in /tmp/app-a-cert.pem -noout -issuer)
echo "Server cert issuer: $ISSUER"

# 2. Search truststore for matching CA
CA_SUBJECT=$(kubectl exec $APP_A_POD -- openssl x509 -in /tmp/ca-cert.pem -noout -subject)
echo "Truststore CA subject: $CA_SUBJECT"

# 3. If issuer matches CA subject, verify signature
kubectl exec $APP_A_POD -- openssl verify -CAfile /tmp/ca-cert.pem /tmp/app-a-cert.pem

# If this succeeds, PKIX path building should succeed in Java
```

---

## Summary

This repository **already implements the complete solution** to prevent PKIX path building errors:

1. ✅ **Shared CA**: All certificates signed by the same K8s CA
2. ✅ **Truststore with CA**: Both apps receive truststore containing the CA certificate
3. ✅ **Proper Configuration**: `application.yml` explicitly sets truststore path
4. ✅ **RestTemplate SSL**: Custom SSLContext loads truststore for outgoing requests
5. ✅ **Vault Distribution**: Certificates distributed securely via Vault
6. ✅ **Init Container**: Ensures certificates are present before app starts

**The key insight**: The truststore's CA certificate must match the issuer of the server's certificate. This repository ensures this by:
- Using a single CA to sign all certificates
- Distributing the same truststore (containing that CA) to all applications
- Properly configuring Spring Boot to use the custom truststore instead of Java's default cacerts

**To use this repository to solve PKIX errors in your own projects**:
1. Generate all certificates from a single CA (or use your organization's CA)
2. Create a truststore containing that CA certificate
3. Configure Spring Boot's `server.ssl.trust-store` to use your truststore
4. Configure RestTemplate's SSLContext to load the same truststore
5. Verify certificate chains match using the troubleshooting commands above
