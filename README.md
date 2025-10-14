# Kubernetes mTLS Service-to-Service Communication Demo

[![CI](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/ci.yml/badge.svg)](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/ci.yml)
[![Certificate Generation](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/certificate-generation.yml/badge.svg)](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/certificate-generation.yml)
[![K8s Integration](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/k8s-integration-test.yml/badge.svg)](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/k8s-integration-test.yml)

A demonstration project showcasing secure service-to-service communication using mutual TLS (mTLS) in Kubernetes with Minikube.

## Overview

This project implements two Spring Boot microservices (App A and App B) that communicate securely within a Kubernetes cluster using mutual TLS authentication. Each service acts as both an HTTPS client and server, ensuring all communication is encrypted and mutually authenticated.

## Features

- **Mutual TLS Authentication**: Both services verify each other's identity using X.509 certificates
- **HashiCorp Vault Integration**: Centralized secret management with Kubernetes authentication
- **Spring Boot 3.2.0**: Modern Spring Boot applications with Java 17
- **Maven Multi-Module**: Organized project structure with separate modules
- **Kubernetes Ready**: Complete deployment manifests and scripts for Minikube
- **Certificate Management**: Automated certificate generation using OpenSSL
- **Service Discovery**: Uses Kubernetes DNS for service-to-service communication
- **CI/CD Pipeline**: GitHub Actions workflows for automated testing and validation

## Quick Start

### Prerequisites

- Java 17+
- Maven 3.6+
- Docker
- Minikube
- kubectl
- OpenSSL
- Java keytool

### Complete Deployment

```bash
# Start Minikube
minikube start

# Run complete deployment
cd k8s/scripts
bash deploy.sh
```

This single command will:
1. Deploy and configure HashiCorp Vault
2. Generate all required certificates
3. Upload certificates to Vault
4. Build Maven artifacts
5. Create Docker images
6. Deploy both applications with Vault integration

### Verify Deployment

```bash
# Check pods
kubectl get pods

# Test mTLS communication (requires client certificate)
kubectl exec -it deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://app-b.default.svc.cluster.local:8443/health
```

## Project Structure

```
k8s-parent/
├── app-a/                  # Spring Boot Application A
│   ├── src/main/java/      # Java source code
│   └── pom.xml             # Maven configuration
├── app-b/                  # Spring Boot Application B
│   ├── src/main/java/      # Java source code
│   └── pom.xml             # Maven configuration
├── k8s/                    # Kubernetes resources
│   ├── manifests/          # Deployment & Service YAML files
│   ├── scripts/            # Deployment and certificate scripts
│   ├── Dockerfile-app-a    # Docker image for App A
│   └── Dockerfile-app-b    # Docker image for App B
└── pom.xml                 # Parent POM
```

## Architecture

Both applications expose HTTPS endpoints on port 8443 and communicate using:
- **PKCS#12 Keystores** (.p12): Contains each app's private key and certificate
- **Java Truststore** (.jks): Contains CA certificate for peer verification
- **HashiCorp Vault**: Stores certificates securely with Kubernetes authentication
- **Init Containers**: Retrieve and decode certificates from Vault at pod startup
- **Spring Cloud Vault**: Injects SSL passwords and configuration properties

Service communication flow:
```
App A (app-a.default.svc.cluster.local:8443)
  ↕ mTLS Connection
App B (app-b.default.svc.cluster.local:8443)
```

## API Endpoints

### App A
- `GET /health` - Health check endpoint
- `GET /api/greet` - Returns greeting message
- `GET /api/call-app-b` - Calls App B's greet endpoint via mTLS

### App B
- `GET /health` - Health check endpoint
- `GET /api/greet` - Returns greeting message
- `GET /api/call-app-a` - Calls App A's greet endpoint via mTLS

## Manual Deployment Steps

If you prefer step-by-step deployment with Vault:

```bash
# 1. Deploy and configure Vault
cd k8s/scripts
bash vault-deploy.sh

# 2. Build Docker images
bash build-images.sh

# 3. Deploy applications
cd ../manifests
kubectl apply -f app-a-service.yaml
kubectl apply -f app-a-deployment.yaml
kubectl apply -f app-b-service.yaml
kubectl apply -f app-b-deployment.yaml
```

The `vault-deploy.sh` script handles certificate generation and upload to Vault automatically.

## Testing

All curl commands require client certificates due to mTLS configuration (`client-auth=need`):

```bash
# Test App A health endpoint
kubectl exec -it deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://localhost:8443/health

# Test App B health endpoint
kubectl exec -it deployment/app-b -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://localhost:8443/health

# Test mTLS communication (App A → App B)
kubectl exec -it deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://app-b.default.svc.cluster.local:8443/api/greet

# Test mTLS communication (App B → App A)
kubectl exec -it deployment/app-b -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://app-a.default.svc.cluster.local:8443/api/greet

# View logs
kubectl logs -f deployment/app-a
kubectl logs -f deployment/app-b
```

## Cleanup

```bash
cd k8s/scripts
bash cleanup.sh
```

## Building Locally

```bash
# Build all modules
mvn clean package

# Build specific module
mvn clean package -pl app-a

# Run tests
mvn test
```

## Monitoring and Visualization

### Access UIs

Use the helper script for easy access to monitoring UIs:

```bash
cd k8s/scripts
bash access-ui.sh
```

**Available UIs:**

1. **Vault UI** - Manage secrets and certificates
   - Access: `kubectl port-forward svc/vault 8200:8200`
   - URL: http://localhost:8200
   - Token: `root` (dev only)

2. **Kubernetes Dashboard** - Visualize cluster state
   - Deploy and access via the helper script
   - View pod status, logs, resource usage in real-time

3. **k9s** - Terminal-based Kubernetes UI
   - Install: `brew install k9s` (macOS) or `choco install k9s` (Windows)
   - Run: `k9s`
   - Real-time monitoring with keyboard shortcuts

For detailed monitoring instructions, see [CLAUDE.md](CLAUDE.md#monitoring-and-visualization).

## HashiCorp Vault Integration

This project uses HashiCorp Vault for centralized secret management:

### Key Features
- **Kubernetes Authentication**: Applications authenticate using service account tokens
- **Secure Storage**: Certificates stored base64-encoded in Vault's KV v2 secrets engine
- **Init Container Pattern**: Certificates retrieved before application starts
- **Least-Privilege Access**: Separate Vault policies for each application

### Vault Scripts
Located in `k8s/scripts/`:
- `vault-deploy.sh` - Complete Vault setup with certificates
- `init-vault.sh` - Initialize Vault configuration
- `upload-certs-to-vault.sh` - Upload certificates to Vault
- `diagnose-vault-certs.sh` - Verify certificate integrity

### Quick Commands

```bash
# Access Vault UI (development only)
kubectl port-forward svc/vault 8200:8200
# Open http://localhost:8200 (Token: root)

# View certificates in Vault
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")
kubectl exec -it $VAULT_POD -- vault kv get secret/app-a/ssl

# Diagnose certificate issues
cd k8s/scripts && bash diagnose-vault-certs.sh
```

For detailed Vault documentation, see [CLAUDE.md](CLAUDE.md#hashicorp-vault-integration).

## CI/CD

This project includes comprehensive GitHub Actions workflows:

### Workflows
- **CI Build & Test**: Builds Maven artifacts, runs tests, and creates Docker images
- **Certificate Generation Test**: Validates certificate generation scripts and certificate chain
- **Kubernetes Integration Test**: Full end-to-end testing with kind cluster, including mTLS communication

See [.github/workflows/README.md](.github/workflows/README.md) for detailed workflow documentation.

### Running Tests Locally
```bash
# Run all tests
mvn test

# Run integration tests
mvn verify

# Test certificate generation
cd k8s/scripts && bash generate-certs.sh
```

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Complete guide for Claude Code AI assistant
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Detailed architecture and mTLS flow
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[docs/SECURITY.md](docs/SECURITY.md)** - Security best practices
- **[.github/workflows/README.md](.github/workflows/README.md)** - CI/CD workflow documentation

## Security Notes

- Certificates are valid for 365 days
- Default keystore password is `changeit` (should be changed in production)
- mTLS is enforced with `client-auth=need`
- All communication is encrypted and authenticated

## Future Enhancements

- Integration with cert-manager for automated certificate rotation
- Prometheus metrics and monitoring
- Distributed tracing with Jaeger/Zipkin
- HashiCorp Vault Agent for dynamic secret rotation

## License

This is a demonstration project for educational purposes.
