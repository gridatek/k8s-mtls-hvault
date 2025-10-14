# Kubernetes mTLS Service-to-Service Communication Demo

[![CI](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/ci.yml/badge.svg)](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/ci.yml)
[![Certificate Generation](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/certificate-generation.yml/badge.svg)](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/certificate-generation.yml)
[![K8s Integration](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/k8s-integration-test.yml/badge.svg)](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/k8s-integration-test.yml)

A demonstration project showcasing secure service-to-service communication using mutual TLS (mTLS) in Kubernetes with Minikube.

## Overview

This project implements two Spring Boot microservices (App A and App B) that communicate securely within a Kubernetes cluster using mutual TLS authentication. Each service acts as both an HTTPS client and server, ensuring all communication is encrypted and mutually authenticated.

## Features

- **Mutual TLS Authentication**: Both services verify each other's identity using X.509 certificates
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
1. Generate all required certificates
2. Build Maven artifacts
3. Create Docker images
4. Create Kubernetes secrets
5. Deploy both applications

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
- **Kubernetes Secrets**: Securely mounts certificates into pods at `/etc/security/ssl/`

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

If you prefer step-by-step deployment:

```bash
# 1. Generate certificates
cd k8s/scripts
bash generate-certs.sh

# 2. Build Docker images
bash build-images.sh

# 3. Create Kubernetes secrets
bash create-k8s-secrets.sh

# 4. Deploy applications
kubectl apply -f ../manifests/
```

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
- **[docs/LOCAL_DEVELOPMENT.md](docs/LOCAL_DEVELOPMENT.md)** - Local development guide
- **[.github/workflows/README.md](.github/workflows/README.md)** - CI/CD workflow documentation

## Security Notes

- Certificates are valid for 365 days
- Default keystore password is `changeit` (should be changed in production)
- mTLS is enforced with `client-auth=need`
- All communication is encrypted and authenticated

## Future Enhancements

- Integration with cert-manager for automated certificate rotation
- HashiCorp Vault for secrets management
- Prometheus metrics and monitoring
- Distributed tracing with Jaeger/Zipkin

## License

This is a demonstration project for educational purposes.
