# Documentation Index

Welcome to the k8s-parent documentation! This project demonstrates secure microservice communication using mutual TLS (mTLS) in Kubernetes.

## Quick Links

- **[Main README](../README.md)** - Project overview and quick start
- **[CLAUDE.md](../CLAUDE.md)** - Complete guide for Claude Code AI assistant

## Documentation Structure

### 📘 Core Documentation

| Document | Description | Audience |
|----------|-------------|----------|
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | System architecture, mTLS flow, and component design | Developers, Architects |
| **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** | Common issues, solutions, and debugging commands | All users |
| **[SECURITY.md](SECURITY.md)** | Security best practices and production guidelines | DevOps, Security teams |
| **[LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md)** | Development workflows, testing, and debugging | Developers |

### 🔧 Reference Documentation

| Document | Description |
|----------|-------------|
| **[.github/workflows/README.md](../.github/workflows/README.md)** | CI/CD workflows and GitHub Actions |
| **[k8s/manifests/README.md](../k8s/manifests/README.md)** | Kubernetes manifests reference |

## Documentation by Role

### For Developers

1. Start with [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) - Set up your environment
2. Review [ARCHITECTURE.md](ARCHITECTURE.md) - Understand the system design
3. Keep [TROUBLESHOOTING.md](TROUBLESHOOTING.md) handy - Quick reference for issues
4. Read [SECURITY.md](SECURITY.md) - Know the security implications

### For DevOps / SRE

1. Review [ARCHITECTURE.md](ARCHITECTURE.md) - Understand deployment architecture
2. Study [SECURITY.md](SECURITY.md) - Production security requirements
3. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Operational issues and solutions
4. Explore [.github/workflows/README.md](../.github/workflows/README.md) - CI/CD pipelines

### For Security Teams

1. Start with [SECURITY.md](SECURITY.md) - Security posture and recommendations
2. Review [ARCHITECTURE.md](ARCHITECTURE.md) - mTLS implementation details
3. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Certificate and TLS issues

### For New Contributors

1. Read [Main README](../README.md) - Project overview
2. Follow [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) - Set up your environment
3. Review [ARCHITECTURE.md](ARCHITECTURE.md) - Understand the codebase
4. Explore the [workflows documentation](../.github/workflows/README.md) - CI/CD process

## Key Concepts

### Mutual TLS (mTLS)

Both client and server authenticate each other using X.509 certificates:

```
Client                          Server
  │                              │
  ├─── ClientHello ─────────────►│
  │◄── ServerHello + ServerCert ─┤
  │    (Verify server cert)      │
  ├─── ClientCert + KeyExchange ►│
  │                 (Verify client cert)
  │◄── Finished ─────────────────┤
  │                              │
  ├─── Encrypted Data ──────────►│
  │◄── Encrypted Response ───────┤
```

See [ARCHITECTURE.md#mtls-flow-diagram](ARCHITECTURE.md#mtls-flow-diagram) for details.

### Certificate Chain

```
CA Certificate (Self-signed)
    │
    ├── App A Certificate (SAN: app-a.default.svc.cluster.local)
    │   └── App A Keystore (PKCS#12)
    │
    └── App B Certificate (SAN: app-b.default.svc.cluster.local)
        └── App B Keystore (PKCS#12)

Truststore (JKS)
    └── CA Certificate (for validation)
```

See [ARCHITECTURE.md#certificate-generation-flow](ARCHITECTURE.md#certificate-generation-flow) for details.

### Kubernetes Resources

```
Namespace: default
├── Deployment: app-a
│   └── Pod: app-a-xxxxx
│       ├── Container: app-a (Spring Boot + JRE 17)
│       └── Volume: ssl-certs (from Secret)
├── Service: app-a (ClusterIP, Port 8443)
├── Secret: app-a-ssl-secret
│   ├── app-a-keystore.p12
│   └── truststore.jks
│
├── Deployment: app-b
│   └── Pod: app-b-xxxxx
│       ├── Container: app-b (Spring Boot + JRE 17)
│       └── Volume: ssl-certs (from Secret)
├── Service: app-b (ClusterIP, Port 8443)
└── Secret: app-b-ssl-secret
    ├── app-b-keystore.p12
    └── truststore.jks
```

See [ARCHITECTURE.md#system-architecture](ARCHITECTURE.md#system-architecture) for details.

## Quick Reference Commands

### Build & Deploy

```bash
# Complete deployment
cd k8s/scripts && bash deploy.sh

# Build only
mvn clean package

# Deploy to Minikube
kubectl apply -f k8s/manifests/
```

### Testing

```bash
# Test health endpoint with mTLS
kubectl exec -it deployment/app-a -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/health

# Test service-to-service communication
kubectl exec -it deployment/app-a -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/api/greet
```

### Debugging

```bash
# View pod logs
kubectl logs -f deployment/app-a

# Get pod shell
kubectl exec -it deployment/app-a -- /bin/sh

# Check certificate
kubectl exec -it deployment/app-a -- \
  keytool -list -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12

# View events
kubectl get events --sort-by='.lastTimestamp'
```

See [TROUBLESHOOTING.md#debugging-commands](TROUBLESHOOTING.md#debugging-commands) for more.

## Frequently Asked Questions

### Why are health probes failing with "bad certificate"?

Health probes must provide client certificates for mTLS authentication. We use `exec` probes with curl instead of `httpGet` probes.

See [TROUBLESHOOTING.md#health-probe-failures](TROUBLESHOOTING.md#1-health-probe-failures) for solution.

### How do I test mTLS communication?

All curl commands must provide the client certificate:

```bash
curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health
```

See [LOCAL_DEVELOPMENT.md#testing-strategies](LOCAL_DEVELOPMENT.md#testing-strategies) for examples.

### How do I regenerate expired certificates?

```bash
cd k8s/scripts
bash generate-certs.sh
bash create-k8s-secrets.sh
kubectl rollout restart deployment/app-a deployment/app-b
```

See [TROUBLESHOOTING.md#certificate-expired](TROUBLESHOOTING.md#symptom-b-certificate-expired) for details.

### How do I add a new service to the mesh?

1. Generate certificate with correct SAN
2. Create PKCS#12 keystore
3. Create Kubernetes Secret
4. Configure Spring Boot with mTLS
5. Use `exec` health probes with curl

See [ARCHITECTURE.md](ARCHITECTURE.md) and [SECURITY.md](SECURITY.md) for guidance.

## Contributing

We welcome contributions! Here's how to get started:

1. **Fork the repository** and clone locally
2. **Set up development environment** using [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md)
3. **Create a feature branch**: `git checkout -b feature/my-feature`
4. **Make changes** and add tests
5. **Run tests**: `mvn test`
6. **Commit with clear messages**: `git commit -m "Add feature X"`
7. **Push and create PR**: `git push origin feature/my-feature`

### Code Guidelines

- Follow existing code style
- Add tests for new features
- Update documentation
- Ensure CI/CD passes

### Documentation Guidelines

- Use clear, concise language
- Include code examples
- Add diagrams where helpful
- Keep READMEs up to date

## Support

- **Issues**: Report bugs or request features on [GitHub Issues](https://github.com/kgridou/k8s-parent/issues)
- **Discussions**: Ask questions in [GitHub Discussions](https://github.com/kgridou/k8s-parent/discussions)
- **Documentation**: Check this documentation first

## Additional Resources

### External Documentation

- [Spring Boot Security](https://docs.spring.io/spring-boot/docs/current/reference/html/application-properties.html#application-properties.server.server.ssl)
- [Kubernetes TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)
- [OpenSSL Documentation](https://www.openssl.org/docs/)
- [NIST TLS Guidelines](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-52r2.pdf)

### Related Projects

- [cert-manager](https://cert-manager.io/) - Automated certificate management
- [Istio](https://istio.io/) - Service mesh with automatic mTLS
- [Linkerd](https://linkerd.io/) - Lightweight service mesh

---

**Last Updated**: 2025-10-13

**Maintainers**: See [CODEOWNERS](../.github/CODEOWNERS) (if exists)
