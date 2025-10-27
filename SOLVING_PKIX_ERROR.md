# Solving javax.net.ssl.SSLHandshakeException: PKIX Path Building Failed

This repository provides a **complete, production-ready solution** for the common `javax.net.ssl.SSLHandshakeException: PKIX path building failed` error that occurs during mTLS/SSL communication.

## What is the PKIX Error?

```
javax.net.ssl.SSLHandshakeException: PKIX path building failed:
sun.security.provider.certpath.SunCertPathBuilderException:
unable to find valid certification path to requested target
```

This error occurs when a Java application attempts to establish an HTTPS connection but **cannot validate the server's certificate** because the Certificate Authority (CA) that signed the certificate is not trusted by the client.

## The Problem in Simple Terms

```
❌ BROKEN CONFIGURATION:

Server presents certificate:
┌─────────────────────────────┐
│ Certificate: app-b          │
│ Issued by: Unknown CA       │ ← Server cert signed by some CA
└─────────────────────────────┘

Client's truststore:
┌─────────────────────────────┐
│ (empty or wrong CA)         │ ← Client doesn't trust that CA
└─────────────────────────────┘

Result: PKIX path building failed ❌
```

```
✅ THIS REPOSITORY'S SOLUTION:

Server presents certificate:
┌─────────────────────────────┐
│ Certificate: app-b          │
│ Issued by: CN=k8s-ca        │ ← Server cert signed by k8s-ca
└─────────────────────────────┘

Client's truststore:
┌─────────────────────────────┐
│ CA: CN=k8s-ca (trusted)     │ ← Client trusts k8s-ca
└─────────────────────────────┘

Result: Certificate validated successfully ✅
```

## How This Repository Solves the Problem

### 1. Single Certificate Authority (CA)

All application certificates are signed by the same internal CA:

```bash
# k8s/scripts/generate-certs.sh

# Generate root CA (lines 26-31)
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem \
  -out ca-cert.pem \
  -subj "/C=US/ST=State/L=City/O=K8S/OU=CA/CN=k8s-ca"

# Sign App A certificate with this CA (lines 60-62)
openssl x509 -req -in app-a.csr -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out app-a-cert.pem -days 365

# Sign App B certificate with the SAME CA (lines 93-95)
openssl x509 -req -in app-b.csr -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out app-b-cert.pem -days 365
```

### 2. Shared Truststore with CA Certificate

All applications receive the same truststore containing the CA:

```bash
# k8s/scripts/generate-certs.sh (lines 114-118)

# Create truststore with CA certificate
keytool -import -trustcacerts -file ca-cert.pem -alias ca \
  -keystore truststore.jks -storepass changeit -noprompt
```

Both App A and App B use this **same truststore**.

### 3. Secure Distribution via HashiCorp Vault

Certificates are distributed securely using Vault:

```bash
# k8s/scripts/upload-certs-to-vault.sh

# Upload to Vault
vault kv put secret/app-a \
  ssl.keystore="$(base64 -w 0 app-a-keystore.p12)" \
  ssl.truststore="$(base64 -w 0 truststore.jks)" \  # ← Same truststore
  ssl.keystore-password="changeit"

vault kv put secret/app-b \
  ssl.keystore="$(base64 -w 0 app-b-keystore.p12)" \
  ssl.truststore="$(base64 -w 0 truststore.jks)" \  # ← Same truststore
  ssl.keystore-password="changeit"
```

### 4. Init Container Retrieves Certificates

Before the application starts, an init container retrieves certificates from Vault:

```yaml
# k8s/manifests/app-a-deployment.yaml (lines 25-50)

initContainers:
- name: vault-init
  command:
  - /bin/sh
  - -c
  - |
    # Authenticate with Vault using Kubernetes service account
    VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login role=app-a jwt=$SA_TOKEN)

    # Retrieve and decode truststore ← KEY STEP
    vault kv get -field=ssl.truststore secret/app-a | base64 -d > /etc/security/ssl/truststore.jks

    # Retrieve keystore
    vault kv get -field=ssl.keystore secret/app-a | base64 -d > /etc/security/ssl/app-a-keystore.p12
```

### 5. Spring Boot Configured to Use Custom Truststore

The application is configured to use the custom truststore instead of Java's default:

```yaml
# app-a/src/main/resources/application.yml

server:
  ssl:
    key-store: file:/etc/security/ssl/app-a-keystore.p12
    key-store-password: ${ssl.keystore-password}
    trust-store: file:/etc/security/ssl/truststore.jks  # ← Prevents PKIX error
    trust-store-password: ${ssl.truststore-password}
    client-auth: need
```

**Without this line**, Java would use the default `cacerts` truststore, which doesn't contain our internal CA → PKIX error!

### 6. RestTemplate Configured with SSL Context

For outgoing HTTPS requests, RestTemplate is configured with a custom SSL context:

```java
// app-a/src/main/java/com/k8s/appa/AppAApplication.java

@Bean
public RestTemplate restTemplate(
        @Value("${server.ssl.trust-store}") Resource trustStore,
        @Value("${server.ssl.trust-store-password}") String trustStorePassword) throws Exception {

    SSLContext sslContext = SSLContextBuilder.create()
            .loadKeyMaterial(keyStore.getURL(), keyStorePassword.toCharArray(), keyStorePassword.toCharArray())
            .loadTrustMaterial(trustStore.getURL(), trustStorePassword.toCharArray())  // ← Loads CA cert
            .build();

    // Configure RestTemplate with custom SSLContext
    // ... (full code in file)
}
```

**Without this**, RestTemplate would use Java's default trust manager → PKIX error on outgoing requests!

## Quick Start

### Deploy the Complete Solution

```bash
# Clone the repository
git clone <your-repo-url>
cd k8s-mtls-hvault22

# Start Minikube
minikube start

# Deploy everything (Vault + certificates + applications)
cd k8s/scripts
bash deploy.sh

# Wait for deployments
kubectl wait --for=condition=ready pod -l 'app in (app-a,app-b)' --timeout=180s

# Verify no PKIX errors
bash verify-no-pkix-error.sh
```

### Test mTLS Communication

```bash
# Get App A pod
APP_A_POD=$(kubectl get pod -l app=app-a -o jsonpath="{.items[0].metadata.name}")

# Test App A → App B (no PKIX error expected)
kubectl exec $APP_A_POD -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health

# Expected output: {"status":"UP"}
```

If you see the health check response, **the PKIX error has been prevented!**

## Understanding the Solution (Learning Mode)

### Reproduce the PKIX Error

To understand how the error occurs, you can intentionally break the configuration:

```bash
cd k8s/scripts
bash reproduce-pkix-error.sh
```

This script will:
1. Upload an empty truststore (no CA certificate)
2. Restart the application
3. Attempt communication (fails with PKIX error)
4. Show the error in logs
5. Restore correct configuration

### Verify the Solution

Run automated verification to check all components:

```bash
cd k8s/scripts
bash verify-no-pkix-error.sh
```

This checks:
- ✓ Certificate files exist
- ✓ Keystores contain valid certificates
- ✓ Truststores contain CA certificate
- ✓ Certificate chains are valid
- ✓ Certificate issuer matches CA subject
- ✓ mTLS communication works
- ✓ No PKIX errors in logs

## Documentation

### Comprehensive Guides

- **[docs/PKIX_PATH_BUILDING_ERROR.md](docs/PKIX_PATH_BUILDING_ERROR.md)** - Complete 400+ line guide covering:
  - Understanding the error (stack trace analysis)
  - Root causes (missing CA, wrong path, wrong password, etc.)
  - How this repository prevents the error
  - Step-by-step reproduction scenarios
  - Troubleshooting guide with real commands
  - Advanced certificate chain debugging

- **[docs/PKIX_QUICK_REFERENCE.md](docs/PKIX_QUICK_REFERENCE.md)** - Quick reference for:
  - Fast diagnosis commands
  - Quick fixes
  - Common mistakes
  - Testing commands

### Project Documentation

- **[CLAUDE.md](CLAUDE.md)** - Complete project documentation
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Architecture details
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - General troubleshooting
- **[docs/SECURITY.md](docs/SECURITY.md)** - Security best practices

## Key Takeaways

### The Problem

```
Client cannot validate server's certificate because the CA that signed
the server's certificate is not in the client's truststore.
```

### The Solution

```
1. Use ONE CA to sign all certificates
2. Put that CA in ALL truststores
3. Configure Spring Boot to use the truststore
4. Configure RestTemplate with the same truststore
5. Distribute certificates securely (via Vault)
```

### Why This Works

```
Server Certificate Issuer = CA in Client's Truststore
          ↓                           ↓
    CN=k8s-ca              CN=k8s-ca (trusted)

         → Certificate validated ✅
         → No PKIX error ✅
```

## Common Use Cases

### Use Case 1: Learning About SSL/TLS Certificate Validation

Deploy this project to understand:
- How certificate chains work
- Why truststores are needed
- How Java validates certificates
- What causes PKIX errors

### Use Case 2: Reproducing and Solving PKIX Errors

Use the reproduction script to:
- See the actual error in logs
- Understand the root cause
- Practice troubleshooting
- Verify the fix

### Use Case 3: Implementing mTLS in Your Own Projects

Use this repository as a reference for:
- Certificate generation with SANs
- Truststore management
- Spring Boot SSL configuration
- RestTemplate SSL configuration
- Vault integration for secret management

### Use Case 4: Kubernetes Security Training

Demonstrate:
- mTLS between microservices
- Certificate-based authentication
- Vault integration with Kubernetes auth
- Init containers for secret retrieval

## Architecture Highlights

### Defense in Depth

1. **No Secrets in Images**: Certificates never in source code or Docker images
2. **Vault Storage**: Encrypted at rest in Vault
3. **Kubernetes Auth**: Service account tokens for Vault authentication
4. **Least Privilege**: Each app can only read its own secrets
5. **Mutual TLS**: Both client and server authenticate each other

### Deployment Flow

```
1. Vault Deployed → 2. Vault Initialized → 3. Certificates Generated
                                               ↓
                                    4. Uploaded to Vault
                                               ↓
5. Application Pod Starts → 6. Init Container Authenticates with Vault
                                               ↓
                            7. Init Container Retrieves Certificates
                                               ↓
                            8. Application Container Starts
                                               ↓
                            9. Spring Boot Loads Certificates
                                               ↓
                         10. mTLS Communication Established ✅
```

## Technology Stack

- **Spring Boot 3.2.0** - Application framework
- **Java 17** - Runtime
- **Apache HttpClient 5** - SSL/TLS configuration
- **HashiCorp Vault** - Secret management
- **Kubernetes** - Orchestration
- **Minikube** - Local development
- **OpenSSL** - Certificate generation
- **Maven** - Build tool

## Contributing

This repository demonstrates a production-ready pattern for preventing PKIX errors in microservices. Feel free to:
- Use it as a reference for your projects
- Extend it with additional features
- Report issues or improvements

## License

[Your License Here]

---

## Quick Command Reference

```bash
# Deploy everything
cd k8s/scripts && bash deploy.sh

# Verify no PKIX errors
bash verify-no-pkix-error.sh

# Reproduce PKIX error (learning)
bash reproduce-pkix-error.sh

# View logs
kubectl logs deployment/app-a | grep -i pkix

# Test communication
kubectl exec deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health

# Clean up
bash cleanup.sh
```

---

**This repository provides a complete, working solution to the PKIX path building failed error. Deploy it, study it, and apply the patterns to your own projects!**
