# How to Reproduce and See the PKIX Error

This guide shows you how to intentionally trigger the PKIX path building error for educational purposes.

## Quick Start - Automated Script

The easiest way to see the error:

```bash
cd k8s/scripts
bash trigger-pkix-error.sh
```

This script will:
1. ✅ Show current working configuration
2. ❌ Break the truststore (remove CA certificate)
3. 🔍 Attempt mTLS connection (will fail)
4. 📋 Show the PKIX error in logs
5. ✅ Restore working configuration

## What You'll See

### Step-by-Step Output

```bash
Step 1: Current working configuration
✓ Truststore contains 1 entry (ca certificate)
✓ Communication works: {"status":"UP"}

Step 2: Creating empty truststore
⚠️  Truststore now contains 0 entries

Step 3: Uploading empty truststore to Vault
✓ Empty truststore uploaded

Step 4: Restarting App A
✓ App A restarted with empty truststore

Step 5: Attempting mTLS communication
❌ Connection FAILED (as expected)

═══════════════════════════════════════════════
        PKIX ERROR (As Expected)
═══════════════════════════════════════════════

Error: SSL routines::tlsv13 alert certificate required

Step 6: Application logs show PKIX error
❌ PKIX path building failed
```

### The Actual Error Message

You'll see this in the application logs:

```
javax.net.ssl.SSLHandshakeException: PKIX path building failed:
sun.security.provider.certpath.SunCertPathBuilderException:
unable to find valid certification path to requested target
    at java.base/sun.security.ssl.Alert.createSSLException(Alert.java:131)
    at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:371)
    at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:314)
    ...
Caused by: sun.security.validator.ValidatorException: PKIX path building failed
    at java.base/sun.security.validator.PKIXValidator.doBuild(PKIXValidator.java:439)
    at java.base/sun.security.validator.PKIXValidator.engineValidate(PKIXValidator.java:306)
    ...
Caused by: sun.security.provider.certpath.SunCertPathBuilderException:
unable to find valid certification path to requested target
    at java.base/sun.security.provider.certpath.SunCertPathBuilder.build(SunCertPathBuilder.java:141)
    ...
```

## Manual Method (More Control)

If you want to trigger the error manually:

### 1. Deploy Working Configuration

```bash
cd k8s/scripts
bash deploy.sh
```

### 2. Verify It Works

```bash
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")

kubectl exec $APP_A_POD -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health
```

**Expected**: `{"status":"UP"}`

### 3. Create Empty Truststore

```bash
# Create empty truststore
keytool -genkeypair -alias dummy -keyalg RSA -keysize 2048 \
  -keystore /tmp/empty-truststore.jks -storepass changeit \
  -dname "CN=Dummy" -validity 1

# Delete the dummy entry to make it empty
keytool -delete -alias dummy \
  -keystore /tmp/empty-truststore.jks -storepass changeit

# Verify it's empty
keytool -list -keystore /tmp/empty-truststore.jks \
  -storepass changeit -storetype JKS
```

**Expected**: "Your keystore contains 0 entries"

### 4. Upload Empty Truststore to Vault

```bash
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")

# Copy to Vault pod
kubectl cp /tmp/empty-truststore.jks "${VAULT_POD}:/tmp/empty-truststore.jks"

# Base64 encode
kubectl exec $VAULT_POD -- sh -c "base64 -w 0 /tmp/empty-truststore.jks > /tmp/empty-truststore.b64"

# Update Vault
kubectl exec $VAULT_POD -- sh -c '
  export VAULT_TOKEN=root
  EMPTY_TRUST=$(cat /tmp/empty-truststore.b64)
  vault kv patch secret/app-a ssl.truststore="$EMPTY_TRUST"
'
```

### 5. Restart App A

```bash
kubectl rollout restart deployment/app-a
kubectl rollout status deployment/app-a --timeout=120s

# Wait for app to fully start
sleep 30
```

### 6. Try Communication (Will Fail)

```bash
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")

kubectl exec $APP_A_POD -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health
```

**Expected**: Connection fails with SSL/TLS error

### 7. Check Logs for PKIX Error

```bash
kubectl logs $APP_A_POD | grep -A 10 -B 5 "PKIX"
```

**Expected**: You'll see the PKIX path building failed error!

### 8. Restore Configuration

```bash
cd k8s/scripts

# Re-upload correct truststore
bash upload-certs-to-vault.sh

# Restart App A
kubectl rollout restart deployment/app-a
```

## Understanding What Happened

### Why Did the Error Occur?

```
┌─────────────────────────────────────────────────────────┐
│ Server (App B) presents certificate:                    │
│   Subject: CN=app-b.default.svc.cluster.local           │
│   Issuer: CN=k8s-ca ←──────────┐                        │
└─────────────────────────────────────────────────────────┘
                                  │
                                  │ Client searches for this CA
                                  ↓
┌─────────────────────────────────────────────────────────┐
│ Client (App A) truststore:                              │
│   (empty - 0 entries)                                   │
│                                                          │
│   ❌ CN=k8s-ca NOT FOUND!                               │
└─────────────────────────────────────────────────────────┘
                                  ↓
        ❌ PKIX path building failed
        Cannot validate server certificate
        Connection rejected
```

### How the Fix Works

```
┌─────────────────────────────────────────────────────────┐
│ Server (App B) presents certificate:                    │
│   Subject: CN=app-b.default.svc.cluster.local           │
│   Issuer: CN=k8s-ca ←──────────┐                        │
└─────────────────────────────────────────────────────────┘
                                  │
                                  │ Client searches for this CA
                                  ↓
┌─────────────────────────────────────────────────────────┐
│ Client (App A) truststore:                              │
│   Entry 1: ca (TrustedCertEntry)                        │
│   Subject: CN=k8s-ca                                    │
│                                                          │
│   ✅ CN=k8s-ca FOUND!                                   │
└─────────────────────────────────────────────────────────┘
                                  ↓
        ✅ Certificate validated successfully
        Signature verified with CA public key
        Connection established
```

## Different Ways to Trigger the Error

### Method 1: Empty Truststore (No CA)
- Remove all entries from truststore
- Result: No CA to validate any certificate

### Method 2: Wrong CA in Truststore
```bash
# Generate different CA
openssl req -new -x509 -days 365 -key ca-key.pem \
  -out different-ca-cert.pem \
  -subj "/CN=different-ca"

# Put different CA in truststore
keytool -import -trustcacerts -file different-ca-cert.pem \
  -alias wrong-ca -keystore truststore.jks -storepass changeit
```

Result: Server cert signed by "k8s-ca", truststore has "different-ca" → PKIX error

### Method 3: No Truststore at All
Comment out truststore in `application.yml`:
```yaml
server:
  ssl:
    # trust-store: file:/etc/security/ssl/truststore.jks
    # trust-store-password: changeit
```

Result: Java uses default cacerts (doesn't contain internal CA) → PKIX error

### Method 4: Wrong Truststore Path
```yaml
server:
  ssl:
    trust-store: file:/wrong/path/truststore.jks  # Wrong path
```

Result: Truststore not found → PKIX error

### Method 5: Wrong Truststore Password
```yaml
server:
  ssl:
    trust-store: file:/etc/security/ssl/truststore.jks
    trust-store-password: wrongpassword  # Wrong password
```

Result: Cannot decrypt truststore → PKIX error

## Viewing the Error in Different Places

### 1. Application Startup Logs

```bash
kubectl logs deployment/app-a | grep -i "ssl\|pkix\|certificate"
```

### 2. During mTLS Connection

```bash
kubectl logs deployment/app-a --follow
# In another terminal, trigger a request
kubectl exec deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health
```

### 3. RestTemplate Requests

```bash
# Call application endpoint that uses RestTemplate
kubectl exec deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/api/call-app-b
```

### 4. Health Probe Failures

If health probes are configured without client certs:
```bash
kubectl describe pod -l app=app-a
# Look for "Liveness probe failed" or "Readiness probe failed"
```

## Learning Points

### What the Error Teaches You

1. **Certificate Chains Matter**: Server cert must chain to a trusted CA
2. **Truststore is Essential**: Java needs to know which CAs to trust
3. **Default Truststore Insufficient**: Internal/self-signed certs need custom truststore
4. **Configuration is Critical**: Path, password, and content must all be correct

### How to Prevent It

1. ✅ Generate all certs from one CA
2. ✅ Distribute CA to all truststores
3. ✅ Configure Spring Boot to use custom truststore
4. ✅ Configure RestTemplate with same truststore
5. ✅ Test certificate chain before deployment

## Troubleshooting the Error

If you see this error unexpectedly:

```bash
# 1. Check if truststore exists
kubectl exec $APP_A_POD -- ls -lh /etc/security/ssl/truststore.jks

# 2. Check truststore contents
kubectl exec $APP_A_POD -- keytool -list \
  -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit -storetype JKS

# 3. Check certificate chain
kubectl exec $APP_A_POD -- openssl verify \
  -CAfile /tmp/ca-cert.pem /tmp/server-cert.pem

# 4. Run automated verification
cd k8s/scripts
bash verify-no-pkix-error.sh
```

## Summary

**To see the error**: `bash trigger-pkix-error.sh`

**To fix the error**: Ensure CA in truststore matches certificate issuer

**To prevent the error**: Use this repository's pattern of shared CA + shared truststore

---

**Now you can confidently reproduce, understand, and fix PKIX path building errors!** 🎯
