# JVM SSL/TLS Quick Reference Guide

Quick reference for configuring and troubleshooting JVM SSL system properties.

## Quick Command Reference

### Setting JVM SSL Properties

**Command Line:**
```bash
java -Djavax.net.ssl.keyStore=/path/to/keystore.p12 \
     -Djavax.net.ssl.keyStorePassword=changeit \
     -Djavax.net.ssl.keyStoreType=PKCS12 \
     -Djavax.net.ssl.trustStore=/path/to/truststore.jks \
     -Djavax.net.ssl.trustStorePassword=changeit \
     -Djavax.net.ssl.trustStoreType=JKS \
     -jar app.jar
```

**Environment Variable:**
```bash
export JAVA_TOOL_OPTIONS="-Djavax.net.ssl.keyStore=/path/to/keystore.p12 -Djavax.net.ssl.keyStorePassword=changeit -Djavax.net.ssl.keyStoreType=PKCS12 -Djavax.net.ssl.trustStore=/path/to/truststore.jks -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=JKS"
```

**Kubernetes Deployment:**
```yaml
env:
- name: JAVA_TOOL_OPTIONS
  value: >-
    -Djavax.net.ssl.keyStore=/etc/security/ssl/app-a-keystore.p12
    -Djavax.net.ssl.keyStorePassword=changeit
    -Djavax.net.ssl.keyStoreType=PKCS12
    -Djavax.net.ssl.trustStore=/etc/security/ssl/truststore.jks
    -Djavax.net.ssl.trustStorePassword=changeit
    -Djavax.net.ssl.trustStoreType=JKS
```

## Essential JVM Properties

| Property | Purpose | Example Value |
|----------|---------|---------------|
| `javax.net.ssl.keyStore` | Path to client keystore (mTLS) | `/etc/security/ssl/app-a-keystore.p12` |
| `javax.net.ssl.keyStorePassword` | Keystore password | `changeit` |
| `javax.net.ssl.keyStoreType` | Keystore format | `PKCS12` or `JKS` |
| `javax.net.ssl.trustStore` | Path to CA truststore | `/etc/security/ssl/truststore.jks` |
| `javax.net.ssl.trustStorePassword` | Truststore password | `changeit` |
| `javax.net.ssl.trustStoreType` | Truststore format | `JKS` or `PKCS12` |

## Debugging Properties

| Property | Purpose | Values |
|----------|---------|--------|
| `javax.net.debug` | Enable SSL debugging | `all`, `ssl`, `ssl:handshake:verbose` |
| `jdk.tls.client.protocols` | Enabled protocols | `TLSv1.3,TLSv1.2` |
| `jdk.tls.server.protocols` | Server protocols | `TLSv1.3,TLSv1.2` |

**Enable verbose SSL debugging:**
```bash
-Djavax.net.debug=ssl:handshake:verbose
```

**Enable all SSL debugging:**
```bash
-Djavax.net.debug=all
```

## Common Testing Commands

### Test Certificate Files

```bash
# List keystore contents
keytool -list -keystore /path/to/keystore.p12 -storepass changeit -storetype PKCS12

# Verbose keystore info
keytool -list -v -keystore /path/to/keystore.p12 -storepass changeit -storetype PKCS12

# List truststore contents
keytool -list -keystore /path/to/truststore.jks -storepass changeit -storetype JKS

# Verify PKCS12 file
openssl pkcs12 -info -in /path/to/keystore.p12 -passin pass:changeit -noout
```

### Test mTLS Connection with curl

```bash
# With PKCS12 keystore
curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
     --cert-type P12 \
     https://localhost:8443/health

# With separate cert and key files
curl -k --cert /path/to/cert.pem \
     --key /path/to/key.pem \
     --cacert /path/to/ca.pem \
     https://localhost:8443/health

# Verbose output
curl -kv --cert /etc/security/ssl/app-a-keystore.p12:changeit \
      --cert-type P12 \
      https://localhost:8443/health
```

### Kubernetes Testing

```bash
# Check environment variable
kubectl exec deployment/app-a -- sh -c 'echo $JAVA_TOOL_OPTIONS'

# List certificate files
kubectl exec deployment/app-a -- ls -lh /etc/security/ssl/

# Test from inside pod
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/health

# Test cross-service communication
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health

# View application logs
kubectl logs -f deployment/app-a | grep -i ssl
```

## Troubleshooting Quick Checks

### 1. Verify Environment Variable
```bash
kubectl exec deployment/app-a -- sh -c 'echo $JAVA_TOOL_OPTIONS'
```
Should output properties starting with `-Djavax.net.ssl.*`

### 2. Verify Certificate Files Exist
```bash
kubectl exec deployment/app-a -- ls -lh /etc/security/ssl/
```
Should show keystore and truststore files with non-zero sizes.

### 3. Verify Certificate Contents
```bash
kubectl exec deployment/app-a -- keytool -list -keystore /etc/security/ssl/app-a-keystore.p12 -storepass changeit -storetype PKCS12
```
Should show certificate with correct CN and SANs.

### 4. Test Local HTTPS Connection
```bash
kubectl exec deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://localhost:8443/health
```
Should return HTTP 200 with "UP" status.

### 5. Check Application Logs
```bash
kubectl logs deployment/app-a --tail=50 | grep -i "ssl\|certificate\|handshake"
```
Look for errors or handshake failures.

## Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| `PKCS12 KeyStore not available` | Missing keystore type | Add `-Djavax.net.ssl.keyStoreType=PKCS12` |
| `Keystore was tampered with` | Wrong password or corrupt file | Verify password, check file integrity |
| `Unable to find valid certification path` | CA cert missing from truststore | Add CA to truststore |
| `bad_certificate` | Client cert not trusted | Add CA to server's truststore |
| `Received fatal alert: handshake_failure` | Protocol or cipher mismatch | Check TLS version, enable debug |
| `No subject alternative names present` | Certificate missing SANs | Regenerate with correct SANs |

## File Formats

### PKCS12 (.p12, .pfx)
- Contains: Private key + certificate + (optionally) CA chain
- Password protected
- Used for: Client and server keystores
- Create: `openssl pkcs12 -export ...`

### JKS (.jks)
- Java-specific keystore format
- Password protected
- Used for: Truststores (CA certificates)
- Create: `keytool -importcert ...`

### PEM (.pem, .crt, .key)
- Text-based format
- Used for: Individual certificates and keys
- Extract from PKCS12: `openssl pkcs12 -in keystore.p12 -out cert.pem`

## Certificate Generation Shortcuts

### Generate Self-Signed Certificate
```bash
# Generate private key
openssl genrsa -out app-key.pem 2048

# Generate self-signed certificate
openssl req -new -x509 -key app-key.pem -out app-cert.pem -days 365

# Create PKCS12 keystore
openssl pkcs12 -export -in app-cert.pem -inkey app-key.pem -out app-keystore.p12 -name app
```

### Import Certificate to JKS Truststore
```bash
keytool -import -trustcacerts -alias ca \
  -file ca-cert.pem \
  -keystore truststore.jks \
  -storepass changeit
```

## Test Script

Run the comprehensive test script:
```bash
cd k8s/scripts
bash test-jvm-ssl.sh
```

This script tests:
- Environment variables
- Certificate files
- Certificate contents
- mTLS connectivity
- Application endpoints
- Error logs

## When to Use JVM Properties vs Programmatic

**Use JVM Properties When:**
- ✅ Simple, uniform SSL config across the app
- ✅ Container-based deployment
- ✅ No need for multiple SSL configurations
- ✅ Using standard Java HTTP clients

**Use Programmatic When:**
- ✅ Need different SSL configs per endpoint
- ✅ Advanced customization (custom TrustManagers)
- ✅ Dynamic certificate rotation
- ✅ Better password security (not in env vars)

## Additional Resources

- **Full Guide**: [docs/JVM_SSL_CONFIGURATION.md](JVM_SSL_CONFIGURATION.md)
- **Example Manifests**: `k8s/manifests/examples/app-a-deployment-jvm-props.yaml`
- **Test Script**: `k8s/scripts/test-jvm-ssl.sh`
- **Java JSSE Docs**: https://docs.oracle.com/javase/8/docs/technotes/guides/security/jsse/JSSERefGuide.html

## Pro Tips

1. **Always use PKCS12 for keystores** (modern standard, Java 9+)
2. **Keep JKS for truststores** (widely compatible)
3. **Use `-Djavax.net.debug=ssl:handshake:verbose`** for troubleshooting
4. **Test with curl first** before troubleshooting Java code
5. **Check SANs match DNS names** in certificates
6. **Verify file permissions** allow Java process to read certs
7. **Use ConfigMaps** for JVM options to avoid baking into images
8. **Never commit passwords** to version control (use Vault)
