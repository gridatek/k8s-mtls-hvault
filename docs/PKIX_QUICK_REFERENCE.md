# PKIX Path Building Error - Quick Reference Guide

## What is the Error?

```
javax.net.ssl.SSLHandshakeException: PKIX path building failed:
sun.security.provider.certpath.SunCertPathBuilderException:
unable to find valid certification path to requested target
```

**Translation**: The client cannot validate the server's certificate because the Certificate Authority (CA) that signed the server's certificate is not trusted by the client.

---

## Quick Diagnosis

### 1. Check if Truststore Exists

```bash
APP_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")
kubectl exec $APP_POD -- ls -lh /etc/security/ssl/truststore.jks
```

**Expected**: File should exist and be readable.

### 2. Check if Truststore Contains CA

```bash
kubectl exec $APP_POD -- keytool -list -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS
```

**Expected**: Should show at least one entry (the CA certificate).

### 3. Verify Certificate Chain

```bash
# Extract certificates
kubectl exec $APP_POD -- openssl pkcs12 -in /etc/security/ssl/app-a-keystore.p12 \
  -passin pass:changeit -nokeys -out /tmp/server-cert.pem

kubectl exec $APP_POD -- keytool -exportcert -alias ca \
  -keystore /etc/security/ssl/truststore.jks -storepass changeit \
  -rfc -file /tmp/ca-cert.pem

# Verify chain
kubectl exec $APP_POD -- openssl verify -CAfile /tmp/ca-cert.pem /tmp/server-cert.pem
```

**Expected**: Output should be `/tmp/server-cert.pem: OK`

### 4. Check Application Logs

```bash
kubectl logs deployment/app-a | grep -i "pkix\|sslhandshake"
```

**Expected**: No PKIX errors in logs.

---

## Quick Fixes

### Fix 1: Truststore Missing or Empty

**Problem**: Init container didn't retrieve truststore from Vault.

**Solution**:
```bash
cd k8s/scripts

# Re-upload certificates to Vault
bash upload-certs-to-vault.sh

# Restart deployment
kubectl rollout restart deployment/app-a
```

### Fix 2: Wrong Truststore Path in Configuration

**Problem**: `application.yml` has incorrect truststore path.

**Check**:
```bash
kubectl exec $APP_POD -- cat /workspace/BOOT-INF/classes/application.yml | grep trust-store
```

**Expected**:
```yaml
trust-store: file:/etc/security/ssl/truststore.jks
```

**Fix**: Update `application.yml` with correct path, rebuild, and redeploy.

### Fix 3: Certificate Chain Mismatch

**Problem**: Server certificate's issuer doesn't match any CA in truststore.

**Check Issuer Match**:
```bash
# Get server cert issuer
SERVER_ISSUER=$(kubectl exec $APP_POD -- openssl x509 -in /tmp/server-cert.pem -noout -issuer)

# Get CA subject
CA_SUBJECT=$(kubectl exec $APP_POD -- openssl x509 -in /tmp/ca-cert.pem -noout -subject)

echo "Server issuer: $SERVER_ISSUER"
echo "CA subject: $CA_SUBJECT"
```

**Expected**: Issuer should match CA subject.

**Fix**: Regenerate all certificates with the same CA:
```bash
cd k8s/scripts
rm -rf ../certs/*
bash generate-certs.sh
bash upload-certs-to-vault.sh
kubectl rollout restart deployment/app-a deployment/app-b
```

### Fix 4: Vault Connection Issues

**Problem**: Init container can't reach Vault to retrieve certificates.

**Check Vault Health**:
```bash
kubectl get pods -l app=vault
kubectl exec $APP_POD -- curl -v http://vault.default.svc.cluster.local:8200/v1/sys/health
```

**Fix**: Ensure Vault is running:
```bash
cd k8s/scripts
bash vault-deploy.sh
```

---

## Automated Verification

Run the automated verification script to check everything:

```bash
cd k8s/scripts
bash verify-no-pkix-error.sh
```

This script checks:
- ✓ Certificate files exist
- ✓ Keystores contain valid certificates
- ✓ Truststores contain CA certificate
- ✓ Certificate chains are valid
- ✓ mTLS communication works
- ✓ No PKIX errors in logs

---

## Reproduce the Error (For Learning)

To understand how the error occurs, you can intentionally break the configuration:

```bash
cd k8s/scripts
bash reproduce-pkix-error.sh
```

This script will:
1. Upload an empty truststore to Vault
2. Restart the application
3. Attempt mTLS communication (will fail with PKIX error)
4. Restore correct configuration

---

## Key Concepts

### Certificate Chain Validation Flow

```
1. Server (App B) presents certificate:
   ┌──────────────────────────────┐
   │ CN=app-b.default.svc...      │
   │ Issuer: CN=k8s-ca            │
   └──────────────────────────────┘

2. Client (App A) receives certificate and extracts issuer: "CN=k8s-ca"

3. Client searches truststore for matching CA:
   ┌──────────────────────────────┐
   │ Alias: ca                    │
   │ Subject: CN=k8s-ca           │ ← MATCH!
   └──────────────────────────────┘

4. Client verifies signature using CA's public key

5. ✓ Certificate validated successfully
```

### Why This Repository Prevents PKIX Errors

1. **Single CA**: All certificates signed by one CA (`k8s-ca`)
2. **Shared Truststore**: Both apps receive truststore with the CA certificate
3. **Proper Configuration**: Spring Boot configured to use custom truststore
4. **RestTemplate SSL**: Custom SSLContext loads the same truststore
5. **Vault Distribution**: Secure certificate distribution via Vault

### The Root Cause

The error occurs when:
```
Server Certificate Issuer ≠ Any CA in Client's Truststore
```

The solution ensures:
```
Server Certificate Issuer = CA in Client's Truststore
```

---

## Common Mistakes

### ❌ Mistake 1: Using Java's Default Truststore

```yaml
# WRONG - No truststore configured
server:
  ssl:
    key-store: file:/etc/security/ssl/app-a-keystore.p12
    # trust-store not configured!
```

**Problem**: Java uses default cacerts which doesn't contain internal CA.

**Fix**: Always specify custom truststore:
```yaml
server:
  ssl:
    trust-store: file:/etc/security/ssl/truststore.jks
    trust-store-password: changeit
```

### ❌ Mistake 2: Wrong Base64 Encoding

```bash
# WRONG - Creates line-wrapped base64
base64 truststore.jks > truststore.b64
```

**Problem**: Line wrapping corrupts binary data.

**Fix**: Use `-w 0` flag:
```bash
base64 -w 0 truststore.jks > truststore.b64
```

### ❌ Mistake 3: Forgetting RestTemplate Configuration

```java
// WRONG - RestTemplate without SSL configuration
@Bean
public RestTemplate restTemplate() {
    return new RestTemplate();
}
```

**Problem**: Outgoing HTTPS requests won't use custom truststore.

**Fix**: Configure SSLContext:
```java
@Bean
public RestTemplate restTemplate(
        @Value("${server.ssl.trust-store}") Resource trustStore,
        @Value("${server.ssl.trust-store-password}") String trustStorePassword) throws Exception {

    SSLContext sslContext = SSLContextBuilder.create()
            .loadTrustMaterial(trustStore.getURL(), trustStorePassword.toCharArray())
            .build();
    // ... configure RestTemplate with sslContext
}
```

### ❌ Mistake 4: Different CAs for Different Apps

```bash
# WRONG - Each app generates its own CA
openssl genrsa -out app-a-ca-key.pem 4096
openssl genrsa -out app-b-ca-key.pem 4096  # Different CA!
```

**Problem**: App A's certificate is signed by CA1, App B's by CA2. Neither trusts the other's CA.

**Fix**: Use one CA for all certificates.

---

## Testing Commands

### Test Direct mTLS Connection

```bash
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")

# Test App A → App B
kubectl exec $APP_A_POD -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health
```

**Expected**: `{"status":"UP"}`

### Test Application-Level Communication

```bash
# Test via RestTemplate endpoint
kubectl exec $APP_A_POD -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/api/call-app-b
```

**Expected**: `Hello from App A! Response from App B: Hello from App B!`

### View Certificate Details

```bash
# View server certificate
kubectl exec $APP_A_POD -- keytool -list -v \
  -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12 | less

# View CA certificate
kubectl exec $APP_A_POD -- keytool -list -v \
  -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS | less
```

---

## Further Reading

For detailed information, see:
- **[docs/PKIX_PATH_BUILDING_ERROR.md](PKIX_PATH_BUILDING_ERROR.md)** - Complete guide with detailed explanations
- **[docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - General troubleshooting guide
- **[docs/SECURITY.md](SECURITY.md)** - Security best practices

---

## Summary

**The Problem**: Client can't validate server's certificate.

**The Cause**: CA that signed the server's cert is not in client's truststore.

**The Solution**:
1. Use one CA to sign all certificates
2. Put that CA in all truststores
3. Configure Spring Boot to use the truststore
4. Configure RestTemplate with the same truststore

**This Repository**: Already implements the complete solution!
