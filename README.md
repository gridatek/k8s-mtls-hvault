# 🔐 Kubernetes mTLS with HashiCorp Vault

[![CI](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/ci.yml/badge.svg)](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/ci.yml)
[![Certificate Generation](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/certificate-generation.yml/badge.svg)](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/certificate-generation.yml)
[![K8s Integration](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/k8s-integration-test.yml/badge.svg)](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/k8s-integration-test.yml)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Java](https://img.shields.io/badge/Java-17-orange.svg)
![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.2.0-green.svg)

> **A comprehensive guide to implementing secure service-to-service communication using mutual TLS (mTLS) in Kubernetes with HashiCorp Vault for secret management.**

This production-ready demonstration showcases enterprise-grade security patterns for microservices, including certificate management, mutual authentication, and zero-trust networking principles.

![Architecture](https://img.shields.io/badge/Architecture-Microservices-blue) ![Security](https://img.shields.io/badge/Security-mTLS-brightgreen) ![Vault](https://img.shields.io/badge/Secrets-Vault-purple)

---

## 📚 Table of Contents

- [What You'll Learn](#-what-youll-learn)
- [Overview](#-overview)
- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Architecture](#-architecture)
- [Step-by-Step Guide](#-step-by-step-guide)
- [Monitoring & Visualization](#-monitoring--visualization)
- [Testing](#-testing)
- [Troubleshooting](#-troubleshooting)
- [Documentation](#-documentation)
- [CI/CD](#-cicd)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🎓 What You'll Learn

By following this guide, you will understand:

- ✅ **Mutual TLS (mTLS)** implementation for service-to-service authentication
- ✅ **X.509 Certificate Management** with custom Certificate Authorities
- ✅ **HashiCorp Vault** integration with Kubernetes authentication
- ✅ **Init Container Pattern** for secret injection
- ✅ **Spring Boot SSL/TLS** configuration for HTTPS endpoints
- ✅ **Kubernetes Service Discovery** using DNS
- ✅ **Zero-Trust Security** principles in microservices
- ✅ **Certificate Lifecycle Management** and rotation strategies

**Perfect for:** DevOps Engineers, Security Engineers, Backend Developers, Platform Engineers

**Difficulty Level:** Intermediate to Advanced

**Estimated Time:** 30-45 minutes

---

## 🌟 Overview

This project demonstrates a real-world implementation of **mutual TLS authentication** between two Spring Boot microservices running in Kubernetes. Unlike traditional one-way TLS (where only the server presents a certificate), mTLS requires both client and server to authenticate each other using X.509 certificates.

### Why This Matters

In production microservices architectures:
- **Service mesh security** requires mTLS for inter-service communication
- **Zero-trust networking** mandates mutual authentication
- **Compliance requirements** (PCI-DSS, HIPAA, SOC2) often require encrypted communication
- **Secret management** must be centralized and auditable

This guide provides a **complete, working implementation** you can adapt for your own projects.

---

## ✨ Features

### Core Security Features
- 🔒 **Mutual TLS Authentication** - Both services verify each other's identity
- 🗝️ **HashiCorp Vault Integration** - Enterprise-grade secret management
- 🛡️ **Certificate-Based Authorization** - No shared secrets or passwords
- 📜 **X.509 Certificate Chain** - Complete PKI infrastructure

### Technical Features
- ☕ **Spring Boot 3.2.0** - Modern Java framework with Java 17
- 🐳 **Docker & Kubernetes** - Containerized deployment with Minikube
- 🔄 **Automated Certificate Generation** - OpenSSL-based certificate creation
- 🎯 **Init Container Pattern** - Secure secret injection before startup
- 📊 **Monitoring UIs** - Vault UI, Kubernetes Dashboard, k9s support
- ✅ **CI/CD Ready** - GitHub Actions workflows included

### Developer Experience
- 🚀 **One-Command Deployment** - Get started in minutes
- 🔧 **Helper Scripts** - Automated setup and diagnostics
- 📖 **Comprehensive Documentation** - Architecture, troubleshooting, security guides
- 🧪 **Automated Testing** - Certificate validation and integration tests

---

## 📋 Prerequisites

### Required Software

Ensure you have the following installed before starting:

#### ✅ **Core Tools**
- [ ] **Java 17 or higher**
  ```bash
  java -version  # Should show version 17 or higher
  ```
- [ ] **Maven 3.6+**
  ```bash
  mvn --version
  ```
- [ ] **Docker Desktop**
  ```bash
  docker --version
  ```

#### ✅ **Kubernetes Tools**
- [ ] **Minikube**
  ```bash
  minikube version
  ```
- [ ] **kubectl**
  ```bash
  kubectl version --client
  ```

#### ✅ **Security Tools**
- [ ] **OpenSSL**
  ```bash
  openssl version
  ```
- [ ] **Java keytool** (included with JDK)
  ```bash
  keytool -help
  ```

#### ✅ **Optional but Recommended**
- [ ] **k9s** - Terminal UI for Kubernetes
  ```bash
  # macOS
  brew install k9s

  # Windows
  choco install k9s
  ```
- [ ] **stern** - Multi-pod log tailing
  ```bash
  # macOS
  brew install stern

  # Windows
  choco install stern
  ```

### System Requirements
- **RAM**: 8GB minimum (16GB recommended for smooth operation)
- **CPU**: 4 cores recommended
- **Disk**: 20GB free space
- **OS**: macOS, Linux, or Windows 10/11 (with WSL2 for bash scripts)

> **Windows Users**: All bash scripts require Git Bash, WSL, or a similar Unix shell environment. PowerShell is not supported.

---

## 🚀 Quick Start

Get the project running in **5 minutes**:

### 1️⃣ Clone the Repository

```bash
git clone https://github.com/yourusername/k8s-mtls-hvault.git
cd k8s-mtls-hvault
```

### 2️⃣ Start Minikube

```bash
minikube start --memory=8192 --cpus=4
```

### 3️⃣ Deploy Everything

```bash
cd k8s/scripts
bash deploy.sh
```

This single command will:
1. ✅ Deploy and configure HashiCorp Vault
2. ✅ Generate CA and application certificates
3. ✅ Upload certificates to Vault (base64-encoded)
4. ✅ Build Maven artifacts
5. ✅ Create Docker images in Minikube
6. ✅ Deploy both applications with mTLS enabled

### 4️⃣ Verify the Deployment

```bash
# Check all pods are running
kubectl get pods

# Test mTLS communication from App A to App B
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health

# Expected output: {"status":"UP"}
```

### 5️⃣ Access the UIs

```bash
# Interactive UI menu
bash access-ui.sh

# Or manually access Vault UI
kubectl port-forward svc/vault 8200:8200
# Open http://localhost:8200 (Token: root)
```

🎉 **Congratulations!** Your mTLS-enabled microservices are now running.

---

## 🏗️ Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                       │
│                                                              │
│  ┌──────────────┐           ┌──────────────┐               │
│  │   App A      │◄──mTLS───►│   App B      │               │
│  │              │           │              │               │
│  │ :8443 HTTPS  │           │ :8443 HTTPS  │               │
│  └──────┬───────┘           └──────┬───────┘               │
│         │                          │                        │
│         │ Vault Auth              │ Vault Auth             │
│         ▼                          ▼                        │
│  ┌─────────────────────────────────────────┐               │
│  │          HashiCorp Vault                │               │
│  │  - KV v2 Secrets Engine                │               │
│  │  - Kubernetes Auth                      │               │
│  │  - SSL Certificates (base64)            │               │
│  │  - Policies & Roles                     │               │
│  └─────────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

### mTLS Handshake Flow

```
App A (Client)                                    App B (Server)
      │                                                │
      │  1. ClientHello + Client Certificate          │
      ├──────────────────────────────────────────────►│
      │                                                │
      │  2. Validate Client Cert against Truststore   │
      │                                                ├─► ✓ Verified
      │                                                │
      │  3. ServerHello + Server Certificate          │
      │◄──────────────────────────────────────────────┤
      │                                                │
  ✓ Verified ◄─┤  4. Validate Server Cert              │
      │         against Truststore                     │
      │                                                │
      │  5. Encrypted Communication Established       │
      │◄─────────────────────────────────────────────►│
```

### Certificate Structure

- **CA Certificate** (`ca-cert.pem`) - Root of trust for all certificates
- **App A Certificate** (`app-a-cert.pem`) - Signed by CA, with SANs for Kubernetes DNS
- **App B Certificate** (`app-b-cert.pem`) - Signed by CA, with SANs for Kubernetes DNS
- **PKCS#12 Keystores** (`.p12`) - Contains private key + certificate for each app
- **Java Truststore** (`.jks`) - Contains CA certificate for peer validation

### Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **Spring Boot Apps** | HTTP client/server with mTLS | `app-a/`, `app-b/` |
| **Vault** | Centralized secret storage | Deployed as pod in cluster |
| **Init Containers** | Certificate retrieval from Vault | Part of app deployments |
| **CA Certificate** | Signs all application certificates | `k8s/certs/ca-cert.pem` |
| **Kubernetes Services** | DNS-based service discovery | `k8s/manifests/*-service.yaml` |

---

## 📖 Step-by-Step Guide

### Manual Deployment (Detailed Steps)

If you want to understand each step, follow this detailed guide:

#### Step 1: Deploy HashiCorp Vault

```bash
cd k8s/scripts
bash vault-deploy.sh
```

**What this does:**
- Deploys Vault as a Kubernetes pod
- Initializes Vault with root token
- Enables KV v2 secrets engine
- Configures Kubernetes authentication
- Creates policies for app-a and app-b
- Generates SSL certificates
- Uploads certificates to Vault (base64-encoded)

#### Step 2: Build Docker Images

```bash
bash build-images.sh
```

**What this does:**
- Builds Maven project (`mvn clean package`)
- Creates Docker images for app-a and app-b
- Loads images into Minikube's Docker daemon
- Tags images as `app-a:1.0.0-SNAPSHOT` and `app-b:1.0.0-SNAPSHOT`

#### Step 3: Deploy Applications

```bash
cd ../manifests
kubectl apply -f app-a-service.yaml
kubectl apply -f app-a-deployment.yaml
kubectl apply -f app-b-service.yaml
kubectl apply -f app-b-deployment.yaml
```

**What this does:**
- Creates Kubernetes services for DNS resolution
- Deploys applications with init containers
- Init containers authenticate with Vault and retrieve certificates
- Applications start with mTLS enabled

#### Step 4: Verify Deployment

```bash
# Watch pods come online
kubectl get pods -w

# Check pod logs
kubectl logs -f deployment/app-a
kubectl logs -f deployment/app-b

# Test health endpoints
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 https://localhost:8443/health
```

---

## 📊 Monitoring & Visualization

### Access Monitoring UIs

Use the interactive helper script:

```bash
cd k8s/scripts
bash access-ui.sh
```

This provides a menu to:
1. Access Vault UI
2. Deploy Kubernetes Dashboard
3. Get dashboard authentication token
4. View all UI access information

### Available UIs

#### 1. Vault UI
**Purpose**: Manage secrets, view certificates, audit logs

```bash
kubectl port-forward svc/vault 8200:8200
# Open: http://localhost:8200
# Token: root
```

**What you can see:**
- All SSL certificates (base64-encoded)
- Kubernetes authentication configuration
- Access policies and roles
- Audit trail of secret access

#### 2. Kubernetes Dashboard
**Purpose**: Visual cluster monitoring

```bash
# Deploy (run once)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Get access token
kubectl -n kubernetes-dashboard create token dashboard-admin

# Start proxy
kubectl proxy
# Open: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

**What you can see:**
- Pod status and resource usage
- Deployment rollout progress
- Service endpoints
- Events and logs
- ConfigMaps and secrets

#### 3. k9s Terminal UI
**Purpose**: Real-time cluster monitoring in terminal

```bash
k9s
```

**Useful shortcuts:**
- `:pods` - View all pods
- `l` - View logs
- `s` - Shell into pod
- `/` - Filter resources
- `d` - Describe resource

---

## 🧪 Testing

### Testing mTLS Communication

All endpoints require client certificates due to `client-auth=need`:

#### Test Health Endpoints

```bash
# App A health check
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 https://localhost:8443/health

# App B health check
kubectl exec -it deployment/app-b -- curl -k \
  --cert /etc/security/ssl/app-b-keystore.p12:changeit \
  --cert-type P12 https://localhost:8443/health
```

#### Test Inter-Service Communication

```bash
# App A → App B
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/api/greet

# App B → App A
kubectl exec -it deployment/app-b -- curl -k \
  --cert /etc/security/ssl/app-b-keystore.p12:changeit \
  --cert-type P12 \
  https://app-a.default.svc.cluster.local:8443/api/greet
```

#### Test Application Endpoints

```bash
# App A calls App B
kubectl exec -it deployment/app-a -- curl -k \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 https://localhost:8443/api/call-app-b

# App B calls App A
kubectl exec -it deployment/app-b -- curl -k \
  --cert /etc/security/ssl/app-b-keystore.p12:changeit \
  --cert-type P12 https://localhost:8443/api/call-app-a
```

### Running Unit Tests

```bash
# Run all tests
mvn test

# Run tests for specific module
mvn test -pl app-a

# Run integration tests
mvn verify

# Test certificate generation
cd k8s/scripts && bash generate-certs.sh
```

### Verify Certificate Chain

```bash
# View App A certificate details
openssl x509 -in k8s/certs/app-a-cert.pem -text -noout

# Verify certificate is signed by CA
openssl verify -CAfile k8s/certs/ca-cert.pem k8s/certs/app-a-cert.pem

# View Subject Alternative Names (SANs)
openssl x509 -in k8s/certs/app-a-cert.pem -noout -ext subjectAltName
```

---

## 🔧 Troubleshooting

### Common Issues

#### Pods Not Starting

```bash
# Check pod status
kubectl get pods

# Describe pod for events
kubectl describe pod <pod-name>

# Check init container logs
kubectl logs <pod-name> -c vault-init

# Check application logs
kubectl logs <pod-name>
```

#### Certificate Issues

```bash
# Diagnose certificate integrity
cd k8s/scripts
bash diagnose-vault-certs.sh

# View certificates in Vault
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")
kubectl exec -it $VAULT_POD -- vault kv get secret/app-a/ssl
```

#### mTLS Connection Failures

```bash
# Check if apps can resolve each other via DNS
kubectl exec -it deployment/app-a -- nslookup app-b.default.svc.cluster.local

# Test connectivity without TLS
kubectl exec -it deployment/app-a -- telnet app-b.default.svc.cluster.local 8443

# Check SSL configuration
kubectl logs deployment/app-a | grep -i "ssl\|tls\|certificate"
```

#### Vault Authentication Failures

```bash
# Verify Vault is running
kubectl get pods -l app=vault

# Check Vault health
kubectl exec -it deployment/vault -- vault status

# Verify service accounts exist
kubectl get sa app-a app-b vault

# Check Vault Kubernetes auth config
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")
kubectl exec -it $VAULT_POD -- vault read auth/kubernetes/role/app-a
```

### Need More Help?

See detailed troubleshooting guide: **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**

---

## 📚 Documentation

### Comprehensive Guides

| Document | Description |
|----------|-------------|
| **[CLAUDE.md](CLAUDE.md)** | Complete reference guide for developers |
| **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** | Detailed architecture and design decisions |
| **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** | Common issues and solutions |
| **[docs/SECURITY.md](docs/SECURITY.md)** | Security best practices and hardening |
| **[.github/workflows/README.md](.github/workflows/README.md)** | CI/CD pipeline documentation |

### API Endpoints

#### App A
- `GET /health` - Health check endpoint
- `GET /api/greet` - Returns greeting message
- `GET /api/call-app-b` - Calls App B's greet endpoint via mTLS

#### App B
- `GET /health` - Health check endpoint
- `GET /api/greet` - Returns greeting message
- `GET /api/call-app-a` - Calls App A's greet endpoint via mTLS

### Helper Scripts

Located in `k8s/scripts/`:

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Complete automated deployment |
| `vault-deploy.sh` | Deploy and configure Vault |
| `init-vault.sh` | Initialize Vault configuration |
| `upload-certs-to-vault.sh` | Upload certificates to Vault |
| `generate-certs.sh` | Generate SSL certificates |
| `build-images.sh` | Build Docker images |
| `diagnose-vault-certs.sh` | Diagnose certificate issues |
| `access-ui.sh` | Interactive UI access menu |
| `cleanup.sh` | Remove all deployments |

---

## 🔄 CI/CD

### GitHub Actions Workflows

This project includes three automated workflows:

#### 1. **CI Build & Test** (`.github/workflows/ci.yml`)
- Triggers: Push/PR to main or develop branches
- Actions: Maven build, unit tests, Docker image creation
- Status: ![CI Badge](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/ci.yml/badge.svg)

#### 2. **Certificate Generation Test** (`.github/workflows/certificate-generation.yml`)
- Triggers: Changes to certificate scripts
- Actions: Certificate generation validation, chain verification
- Status: ![Cert Badge](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/certificate-generation.yml/badge.svg)

#### 3. **Kubernetes Integration Test** (`.github/workflows/k8s-integration-test.yml`)
- Triggers: Push/PR to main
- Actions: Full end-to-end deployment to Minikube, mTLS communication tests
- Status: ![K8s Badge](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/k8s-integration-test.yml/badge.svg)

See detailed CI/CD documentation: **[.github/workflows/README.md](.github/workflows/README.md)**

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

### Ways to Contribute

- 🐛 **Report Bugs** - Open an issue with details and reproduction steps
- 💡 **Suggest Features** - Share ideas for improvements
- 📝 **Improve Documentation** - Fix typos, add examples, clarify concepts
- 🔧 **Submit Pull Requests** - Fix bugs or add features

### Development Workflow

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly (run all tests, verify deployment)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to your fork (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Code Style

- Follow existing code formatting
- Add comments for complex logic
- Update documentation for user-facing changes
- Include tests for new features

---

## 📄 License

This project is licensed under the **MIT License** - see below for details.

```
MIT License

Copyright (c) 2024 k8s-mtls-hvault Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 🌟 Acknowledgments

This project was built using:
- [Spring Boot](https://spring.io/projects/spring-boot) - Application framework
- [HashiCorp Vault](https://www.vaultproject.io/) - Secret management
- [Kubernetes](https://kubernetes.io/) - Container orchestration
- [Minikube](https://minikube.sigs.k8s.io/) - Local Kubernetes cluster
- [OpenSSL](https://www.openssl.org/) - Certificate generation

---

## 📧 Contact & Support

- **Issues**: [GitHub Issues](https://github.com/gridatek/k8s-mtls-hvault/issues)
- **Discussions**: [GitHub Discussions](https://github.com/gridatek/k8s-mtls-hvault/discussions)

---

## 🔖 Tags

`kubernetes` `mtls` `mutual-tls` `hashicorp-vault` `spring-boot` `microservices` `security` `ssl-certificates` `x509` `service-mesh` `zero-trust` `devops` `platform-engineering`

---

<p align="center">
  <sub>Built with ❤️ for the DevOps and Security community</sub>
</p>

<p align="center">
  <sub>⭐ If this project helped you, please star it on GitHub! ⭐</sub>
</p>
