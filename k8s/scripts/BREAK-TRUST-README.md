# Breaking App B Trust for Testing

This directory contains scripts to intentionally break the trust chain for App B to test mTLS certificate validation failures.

## Overview

The scripts will:
1. Generate a fake CA certificate (different from the real CA)
2. Create an invalid truststore for App B containing only the fake CA
3. Upload this invalid truststore to Vault while keeping App B's valid keystore

## Result

After applying these changes:
- **App B can still present its own certificate** (valid keystore)
- **App B will NOT trust App A's certificate** (invalid truststore with wrong CA)
- **mTLS handshakes will fail** when App B tries to validate certificates

## Usage

### Step 1: Generate the Invalid Truststore

```bash
cd k8s/scripts
bash break-app-b-trust.sh
```

This creates:
- `k8s/certs/fake-ca-cert.pem` - Fake CA certificate
- `k8s/certs/fake-ca-key.pem` - Fake CA private key
- `k8s/certs/app-b-bad-truststore.jks` - Invalid truststore with fake CA

### Step 2: Upload to Vault

**Prerequisites:**
- Vault must be running
- App B keystore must exist (run `bash generate-certs.sh` first if needed)

```bash
bash upload-bad-trust-to-vault.sh
```

### Step 3: Restart App B

```bash
kubectl rollout restart deployment/app-b
```

### Step 4: Test the Failure

```bash
# This should FAIL with SSL/TLS handshake error
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health

# Check app-b logs for certificate validation errors
kubectl logs -f deployment/app-b | grep -i "ssl\|tls\|certificate\|handshake"
```

## Expected Error Messages

You should see errors like:
- `PKIX path validation failed`
- `unable to find valid certification path to requested target`
- `SSL handshake failed`
- `peer not authenticated`

## Restoring Normal Operation

To restore the correct truststore and fix mTLS:

```bash
# Re-upload correct certificates
bash upload-certs-to-vault.sh

# Restart app-b
kubectl rollout restart deployment/app-b

# Verify it works
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health
```

## What's Happening Under the Hood

1. **Valid Keystore**: App B still has its valid keystore with its own certificate signed by the real CA
2. **Invalid Truststore**: App B's truststore contains a fake CA certificate
3. **Handshake Failure**: When App A connects to App B:
   - App A presents its certificate (signed by real CA)
   - App B tries to validate it against its truststore (which only has fake CA)
   - Validation fails because the certificate chain cannot be established
   - Connection is rejected

## Use Cases

This is useful for testing:
- Certificate validation error handling
- mTLS failure modes
- Logging and monitoring of SSL/TLS errors
- Graceful degradation when trust is broken
- Security controls that prevent untrusted connections
