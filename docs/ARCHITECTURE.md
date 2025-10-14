# Architecture Documentation

## Overview

This project demonstrates secure microservice communication using mutual TLS (mTLS) in a Kubernetes environment. It implements two Spring Boot applications that authenticate each other using X.509 certificates.

## System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                       Minikube Cluster                       │
│                                                              │
│  ┌────────────────────────┐      ┌────────────────────────┐  │
│  │  Namespace: default    │      │  Namespace: default    │  │
│  │                        │      │                        │  │
│  │  ┌──────────────────┐  │      │  ┌──────────────────┐  │  │
│  │  │   Pod: app-a     │  │      │  │   Pod: app-b     │  │  │
│  │  │                  │  │      │  │                  │  │  │
│  │  │  Container:      │  │◄────►│  │  Container:      │  │  │
│  │  │  - app-a:8443    │  │ mTLS │  │  - app-b:8443    │  │  │
│  │  │  - Spring Boot   │  │      │  │  - Spring Boot   │  │  │
│  │  │  - JRE 17        │  │      │  │  - JRE 17        │  │  │
│  │  │  - Curl          │  │      │  │  - Curl          │  │  │
│  │  └──────────────────┘  │      │  └──────────────────┘  │  │
│  │           │            │      │           │            │  │
│  │           ▼            │      │           ▼            │  │
│  │  ┌──────────────────┐  │      │  ┌──────────────────┐  │  │
│  │  │  Volume Mount    │  │      │  │  Volume Mount    │  │  │
│  │  │  /etc/security/  │  │      │  │  /etc/security/  │  │  │
│  │  │  ssl/            │  │      │  │  ssl/            │  │  │
│  │  └──────────────────┘  │      │  └──────────────────┘  │  │
│  │           │            │      │           │            │  │
│  │           ▼            │      │           ▼            │  │
│  │  ┌──────────────────┐  │      │  ┌──────────────────┐  │  │
│  │  │  Secret:         │  │      │  │  Secret:         │  │  │
│  │  │  app-a-ssl       │  │      │  │  app-b-ssl       │  │  │
│  │  │  - keystore.p12  │  │      │  │  - keystore.p12  │  │  │
│  │  │  - truststore.jks│  │      │  │  - truststore.jks│  │  │
│  │  └──────────────────┘  │      │  └──────────────────┘  │  │
│  │                        │      │                        │  │
│  │  Service:              │      │  Service:              │  │
│  │  app-a                 │      │  app-b                 │  │
│  │  Type: ClusterIP       │      │  Type: ClusterIP       │  │
│  │  Port: 8443            │      │  Port: 8443            │  │
│  └────────────────────────┘      └────────────────────────┘  │
│                                                              │
│  DNS Resolution:                                             │
│  - app-a.default.svc.cluster.local → Service IP              │
│  - app-b.default.svc.cluster.local → Service IP              │
└──────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Spring Boot Applications

**Technology Stack:**
- Spring Boot 3.2.0
- Java 17 (eclipse-temurin JRE)
- Embedded Tomcat with SSL/TLS
- Apache HttpClient for outbound mTLS requests

**Configuration:**
- Port: 8443 (HTTPS only, no HTTP)
- SSL Client Auth: `need` (mandatory client certificates)
- Keystore Type: PKCS#12
- Truststore Type: JKS

### 2. Docker Images

**Base Image:** `eclipse-temurin:17-jre-alpine`

**Additions:**
- `curl` package (for health probe authentication)
- Application JAR
- No embedded certificates (mounted via Kubernetes Secrets)

**Image Size:** ~200MB per image

### 3. Kubernetes Resources

#### Deployments
- **Replicas:** 1 per application
- **Strategy:** RollingUpdate
- **Resource Limits:** None (BestEffort QoS)
- **Image Pull Policy:** IfNotPresent (Never in CI)

#### Services
- **Type:** ClusterIP (internal only)
- **Port:** 8443/TCP
- **Protocol:** HTTPS with mTLS
- **DNS:** `<service>.<namespace>.svc.cluster.local`

#### Secrets
- **Type:** Opaque
- **Contents:**
  - `app-{a|b}-keystore.p12` - Private key + certificate
  - `truststore.jks` - CA certificate for validation
- **Mount Path:** `/etc/security/ssl/`
- **Permissions:** Read-only

## mTLS Flow Diagram

### Certificate Generation Flow

```
┌─────────────────┐
│ CA Private Key  │
│  (ca-key.pem)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ CA Certificate  │
│  (ca-cert.pem)  │
│  (Self-signed)  │
└────────┬────────┘
         │
         ├──────────────────────┬──────────────────────┐
         ▼                      ▼                      ▼
┌────────────────┐    ┌────────────────┐    ┌────────────────┐
│ App A CSR      │    │ App B CSR      │    │ Truststore.jks │
│                │    │                │    │ (CA Cert Only) │
└────────┬───────┘    └────────┬───────┘    └────────────────┘
         │                     │
         ▼                     ▼
┌────────────────┐    ┌────────────────┐
│ App A Cert     │    │ App B Cert     │
│ (Signed by CA) │    │ (Signed by CA) │
│ SAN: app-a...  │    │ SAN: app-b...  │
└────────┬───────┘    └────────┬───────┘
         │                     │
         ▼                     ▼
┌────────────────┐    ┌────────────────┐
│ App A Keystore │    │ App B Keystore │
│ (PKCS#12)      │    │ (PKCS#12)      │
│ - Private Key  │    │ - Private Key  │
│ - Certificate  │    │ - Certificate  │
└────────────────┘    └────────────────┘
```

### mTLS Handshake Flow

```
App A                                          App B
  │                                              │
  │ 1. ClientHello                               │
  ├─────────────────────────────────────────────►│
  │                                              │
  │ 2. ServerHello + Certificate (App B)         │
  │◄─────────────────────────────────────────────┤
  │                                              │
  │ 3. Verify App B cert against Truststore      │
  │    (Check CA signature, SAN, expiry)         │
  │                                              │
  │ 4. Certificate (App A) + ClientKeyExchange   │
  ├─────────────────────────────────────────────►│
  │                                              │
  │                                              │ 5. Verify App A cert
  │                                              │    against Truststore
  │                                              │
  │ 6. Finished                                  │
  │◄─────────────────────────────────────────────┤
  │                                              │
  │ 7. Encrypted Application Data                │
  ├─────────────────────────────────────────────►│
  │◄─────────────────────────────────────────────┤
  │                                              │
```

### Request Flow: App A → App B

```
1. Application Code:
   └─► RestTemplate/HttpClient with SSL Context
       └─► Load keystore: app-a-keystore.p12
       └─► Load truststore: truststore.jks

2. Network Layer:
   └─► DNS Resolution: app-b.default.svc.cluster.local → 10.x.x.x
   └─► TCP Connection: 10.x.x.x:8443

3. TLS Handshake:
   └─► App A presents: app-a certificate
   └─► App B presents: app-b certificate
   └─► Mutual verification via shared CA in truststore

4. HTTP Request:
   └─► GET /health (or /api/greet)
   └─► Over encrypted TLS channel

5. Response:
   └─► HTTP 200 OK
   └─► Body: {"status":"UP"} or greeting message
```

## Health Probes with mTLS

Since `client-auth=need` is configured, even Kubernetes health probes must provide client certificates.

### Health Probe Configuration

```yaml
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - |
      curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
        --cert-type P12 \
        https://localhost:8443/health
  initialDelaySeconds: 60
  periodSeconds: 10
```

**Why `exec` instead of `httpGet`?**
- Kubernetes `httpGet` probes cannot provide client certificates
- `exec` probe uses curl with certificate authentication
- Requires curl to be installed in the container image

## Certificate Details

### CA Certificate

- **Type:** Self-signed root CA
- **Validity:** 365 days
- **Key Size:** 2048-bit RSA
- **Purpose:** Sign application certificates

### Application Certificates

**Common Properties:**
- **Validity:** 365 days
- **Key Size:** 2048-bit RSA
- **Signed by:** Internal CA
- **Format:** PEM (converted to PKCS#12 for Java)

**Subject Alternative Names (SANs):**
- App A: `DNS:app-a`, `DNS:app-a.default.svc.cluster.local`
- App B: `DNS:app-b`, `DNS:app-b.default.svc.cluster.local`

**Why SANs Matter:**
- Kubernetes services use FQDN for internal DNS
- Certificate validation requires SAN to match the hostname
- Without correct SANs, TLS handshake fails with hostname mismatch

## Security Boundaries

### What is Protected

✅ **Data in Transit:**
- All communication between App A and App B is encrypted
- TLS 1.3 (or TLS 1.2) with strong cipher suites

✅ **Identity Verification:**
- Both services verify each other's identity via certificates
- Prevents impersonation attacks

✅ **Man-in-the-Middle Protection:**
- Encrypted channel prevents eavesdropping
- Certificate pinning via truststore prevents MITM

### What is NOT Protected

❌ **Data at Rest:**
- Kubernetes Secrets are base64-encoded, not encrypted by default
- Consider using encryption at rest (KMS, Sealed Secrets, etc.)

❌ **Secrets Management:**
- Keystore password is hardcoded (`changeit`)
- In production, use Vault or external secret managers

❌ **Certificate Rotation:**
- Manual certificate regeneration required
- No automated rotation (consider cert-manager)

❌ **External Access:**
- Services are ClusterIP only (no external ingress)
- Not accessible outside the cluster

## Performance Considerations

### TLS Handshake Overhead

- **First Request:** ~100-200ms for full TLS handshake
- **Subsequent Requests:** ~5-10ms (TLS session reuse)
- **Mitigation:** Keep-alive connections, connection pooling

### Resource Usage

- **Memory:** ~512MB per application (JVM heap)
- **CPU:** Minimal (TLS offload is CPU-intensive but brief)
- **Network:** Negligible overhead (~5% compared to plain HTTP)

### Scaling Considerations

- Each pod requires its own certificate and keystore
- Shared truststore across all pods
- Horizontal scaling: Add more pods with load balancing
- Vertical scaling: Increase pod resources if needed

## Future Enhancements

1. **cert-manager Integration**
   - Automated certificate generation and rotation
   - Integration with Let's Encrypt or internal CA

2. **Service Mesh (Istio/Linkerd)**
   - Automatic mTLS between all services
   - Certificate management handled by mesh control plane
   - Observability and traffic management

3. **HashiCorp Vault**
   - Dynamic secret generation
   - Secure keystore password management
   - Automated certificate renewal

4. **Monitoring & Observability**
   - Certificate expiry monitoring
   - TLS handshake metrics
   - Failed authentication alerts

5. **Zero Trust Network**
   - Network policies to restrict pod-to-pod communication
   - Service accounts with RBAC
   - Admission controllers for security validation
