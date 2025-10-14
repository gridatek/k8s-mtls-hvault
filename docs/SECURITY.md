# Security Best Practices

## Overview

This document outlines security considerations for the mTLS service-to-service communication implementation. While this is a demonstration project, these guidelines apply to production deployments.

## Current Security Posture

### ✅ What's Secure

1. **Encrypted Communication**
   - All traffic between services uses TLS 1.2/1.3
   - Strong cipher suites enforced
   - No plain HTTP communication

2. **Mutual Authentication**
   - Both client and server present certificates
   - Identity verification prevents impersonation
   - Man-in-the-middle attacks mitigated

3. **Certificate-Based Identity**
   - Services identified by X.509 certificates
   - Subject Alternative Names (SANs) enforce hostname validation
   - CA-signed certificates prevent rogue certificates

4. **Internal-Only Services**
   - ClusterIP services (not exposed externally)
   - No ingress controller configured
   - Network isolation within Kubernetes cluster

### ⚠️ Security Gaps (Demo Project)

1. **Hardcoded Passwords**
   - Keystore password: `changeit`
   - Truststore password: `changeit`
   - Stored in plain text in configuration files

2. **Secrets Management**
   - Kubernetes Secrets are base64-encoded, not encrypted
   - No encryption at rest by default
   - Secrets stored in Git (certificates only for demo)

3. **No Certificate Rotation**
   - Manual certificate renewal required
   - 365-day validity with no auto-renewal
   - No alerting for expiring certificates

4. **No Network Policies**
   - All pods can communicate with each other
   - No namespace isolation enforced
   - No egress filtering

5. **Container Security**
   - Running as root user
   - No security context constraints
   - No AppArmor/SELinux profiles

---

## Production Security Enhancements

### 1. Secrets Management

#### Use External Secret Stores

**Option A: HashiCorp Vault**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-a
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      serviceAccountName: app-a
      initContainers:
      - name: vault-agent
        image: vault:latest
        command:
        - vault
        - agent
        - -config=/vault/config/agent.hcl
        volumeMounts:
        - name: vault-config
          mountPath: /vault/config
        - name: ssl-certs
          mountPath: /etc/security/ssl
```

**Option B: Sealed Secrets**

```bash
# Install sealed-secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Create sealed secret
kubeseal --format=yaml < app-a-secret.yaml > app-a-sealed-secret.yaml

# Deploy sealed secret
kubectl apply -f app-a-sealed-secret.yaml
```

**Option C: External Secrets Operator**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-a-ssl-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: app-a-ssl-secret
  data:
  - secretKey: app-a-keystore.p12
    remoteRef:
      key: secret/data/app-a
      property: keystore
```

#### Environment-Specific Passwords

```yaml
# Use Kubernetes secrets for passwords
apiVersion: v1
kind: Secret
metadata:
  name: app-a-passwords
type: Opaque
stringData:
  keystore-password: <generate-strong-password>
  truststore-password: <generate-strong-password>
---
# Reference in deployment
env:
- name: KEYSTORE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: app-a-passwords
      key: keystore-password
```

Update `application.yml`:
```yaml
server:
  ssl:
    key-store-password: ${KEYSTORE_PASSWORD}
    trust-store-password: ${TRUSTSTORE_PASSWORD}
```

---

### 2. Certificate Management

#### Automated Rotation with cert-manager

```yaml
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create CA issuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca
spec:
  ca:
    secretName: ca-key-pair

# Auto-generate certificates
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-a-cert
spec:
  secretName: app-a-tls
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days
  subject:
    organizations:
    - k8s-demo
  commonName: app-a
  dnsNames:
  - app-a
  - app-a.default.svc.cluster.local
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
```

#### Certificate Expiry Monitoring

```bash
# Prometheus rule
- alert: CertificateExpiring
  expr: |
    (cert_manager_certificate_expiration_timestamp_seconds - time()) / 86400 < 30
  for: 1h
  labels:
    severity: warning
  annotations:
    summary: "Certificate {{ $labels.name }} expiring soon"
    description: "Certificate expires in {{ $value }} days"
```

---

### 3. Network Security

#### Kubernetes Network Policies

```yaml
# Restrict App A to only communicate with App B
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-a-network-policy
spec:
  podSelector:
    matchLabels:
      app: app-a
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: app-b
    ports:
    - protocol: TCP
      port: 8443
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: app-b
    ports:
    - protocol: TCP
      port: 8443
  - to:  # Allow DNS
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

#### Service Mesh (Istio)

```yaml
# Strict mTLS for all services
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT

# Authorization policy
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: app-a-policy
spec:
  selector:
    matchLabels:
      app: app-a
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/app-b"]
    to:
    - operation:
        methods: ["GET"]
        paths: ["/health", "/api/greet"]
```

---

### 4. Container Security

#### Security Context

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app-a
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: ssl-certs
          mountPath: /etc/security/ssl
          readOnly: true
      volumes:
      - name: tmp
        emptyDir: {}
```

#### Update Dockerfile

```dockerfile
FROM eclipse-temurin:17-jre-alpine

# Install curl
RUN apk add --no-cache curl

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app

# Copy application
COPY app-a/target/app-a-1.0.0-SNAPSHOT.jar /app/app-a.jar

# Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

EXPOSE 8443

ENTRYPOINT ["java", "-jar", "/app/app-a.jar"]
```

#### Image Scanning

```yaml
# GitHub Actions workflow
- name: Scan Docker image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: app-a:1.0.0-SNAPSHOT
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'

- name: Upload scan results
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```

---

### 5. Application Security

#### Dependency Scanning

```bash
# Maven dependency check
mvn org.owasp:dependency-check-maven:check

# Snyk scan
snyk test --all-projects
```

#### Update Dependencies Regularly

```xml
<!-- pom.xml -->
<plugin>
  <groupId>org.owasp</groupId>
  <artifactId>dependency-check-maven</artifactId>
  <version>8.4.0</version>
  <executions>
    <execution>
      <goals>
        <goal>check</goal>
      </goals>
    </execution>
  </executions>
</plugin>
```

#### Secure Spring Boot Configuration

```yaml
# application.yml
server:
  ssl:
    enabled: true
    protocol: TLS
    enabled-protocols: TLSv1.3,TLSv1.2
    ciphers: >
      TLS_AES_256_GCM_SHA384,
      TLS_AES_128_GCM_SHA256,
      TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
      TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: when-authorized

logging:
  level:
    org.springframework.security: INFO
  pattern:
    console: '%d{yyyy-MM-dd HH:mm:ss} - %msg%n'
```

---

### 6. Monitoring & Auditing

#### Audit Logging

```yaml
# Enable Kubernetes audit logging
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets"]
  namespaces: ["default"]
```

#### Security Metrics

```java
// Add metrics for mTLS connections
@Component
public class SecurityMetrics {
    private final MeterRegistry registry;

    @EventListener
    public void onAuthenticationSuccess(AuthenticationSuccessEvent event) {
        registry.counter("mtls.authentication.success",
            "client", extractClientCN(event)).increment();
    }

    @EventListener
    public void onAuthenticationFailure(AuthenticationFailureEvent event) {
        registry.counter("mtls.authentication.failure",
            "reason", event.getException().getMessage()).increment();
    }
}
```

#### Alerting

```yaml
# Prometheus alerts
groups:
- name: security
  rules:
  - alert: TLSHandshakeFailure
    expr: rate(mtls_authentication_failure_total[5m]) > 10
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High rate of TLS handshake failures"

  - alert: UnauthorizedAccess
    expr: mtls_authentication_failure_total{reason="bad_certificate"} > 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Unauthorized access attempt detected"
```

---

### 7. Compliance & Standards

#### NIST Guidelines

Follow [NIST SP 800-52 Rev. 2](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-52r2.pdf):

- ✅ Use TLS 1.2 or 1.3
- ✅ Disable TLS 1.0 and 1.1
- ✅ Use FIPS 140-2 validated crypto modules (if required)
- ✅ Implement certificate validation
- ✅ Use strong cipher suites

#### CIS Kubernetes Benchmark

Relevant controls:
- 5.2.1: Minimize the admission of privileged containers
- 5.2.2: Minimize the admission of containers wishing to share the host process ID namespace
- 5.2.3: Minimize the admission of containers wishing to share the host IPC namespace
- 5.7.2: Ensure that the seccomp profile is set to docker/default in your pod definitions
- 5.7.3: Apply Security Context to Your Pods and Containers

---

## Security Checklist

### Pre-Production

- [ ] Replace hardcoded passwords with secret management
- [ ] Implement certificate rotation
- [ ] Enable encryption at rest for etcd
- [ ] Configure network policies
- [ ] Run containers as non-root
- [ ] Implement read-only root filesystem
- [ ] Enable security context constraints
- [ ] Scan container images for vulnerabilities
- [ ] Update all dependencies to latest secure versions
- [ ] Configure audit logging
- [ ] Set up monitoring and alerting
- [ ] Document incident response procedures

### Ongoing

- [ ] Monitor certificate expiry (30-day warning)
- [ ] Review access logs weekly
- [ ] Scan for vulnerabilities monthly
- [ ] Update dependencies quarterly
- [ ] Rotate certificates before expiry
- [ ] Review and update network policies
- [ ] Conduct security audits annually
- [ ] Train team on security best practices

---

## Security Incident Response

### Detection

1. Monitor for:
   - Failed TLS handshakes
   - Unauthorized access attempts
   - Certificate validation failures
   - Unusual traffic patterns

2. Alert channels:
   - Prometheus/Grafana alerts
   - Kubernetes events
   - Application logs
   - SIEM integration

### Response Procedure

1. **Identify**: Confirm security incident
2. **Contain**: Isolate affected services
3. **Investigate**: Analyze logs and metrics
4. **Remediate**: Fix vulnerability or revoke compromised certificates
5. **Recover**: Restore normal operations
6. **Document**: Record incident details and lessons learned

### Certificate Compromise

If a certificate is compromised:

```bash
# 1. Revoke compromised certificate
# 2. Generate new certificates
cd k8s/scripts
bash generate-certs.sh

# 3. Update secrets
bash create-k8s-secrets.sh

# 4. Force pod restart
kubectl rollout restart deployment/app-a
kubectl rollout restart deployment/app-b

# 5. Monitor for unauthorized use of old certificate
kubectl logs -l app=app-a | grep "bad certificate"
```

---

## Additional Resources

- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/security-checklist/)
- [Spring Security Documentation](https://spring.io/projects/spring-security)
- [TLS Best Practices (Mozilla)](https://wiki.mozilla.org/Security/Server_Side_TLS)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
