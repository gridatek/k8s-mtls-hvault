# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Kubernetes-based demonstration project for secure service-to-service communication using mutual TLS (mTLS). The project implements two microservices (App A and App B) that communicate securely within a Minikube cluster.

### Architecture

- **App A** and **App B**: Both applications act as both HTTP clients and servers
- Each app exposes an HTTPS endpoint and makes HTTPS requests to the other
- Communication uses mutual TLS authentication with X.509 certificates
- Services communicate via Kubernetes DNS: `app-a.default.svc.cluster.local` and `app-b.default.svc.cluster.local`
- All communication is internal to the cluster (no external ingress required)

### Security Setup

**Certificate Management:**
- Each application has a PKCS#12 keystore (.p12) containing its private key and signed certificate
- Each application has a Java truststore (.jks) containing the shared CA certificate
- All certificates are issued by the same internal CA
- Subject Alternative Names (SANs) match Kubernetes service DNS names

**Kubernetes Configuration:**
- Keystores and truststores are stored in HashiCorp Vault
- Applications retrieve certificates from Vault at startup using Kubernetes authentication
- Certificate files are written to `/etc/security/ssl/` in each Pod
- mTLS is enforced with `server.ssl.client-auth=need` (for Spring Boot applications)

**mTLS Handshake Flow:**
1. Client presents its certificate from its keystore
2. Server validates client certificate against its truststore
3. Server presents its certificate to the client
4. Client validates server certificate against its truststore
5. Secure, mutually authenticated session is established

## Development Environment

**Target Platform:** Minikube (local Kubernetes cluster)

**Technology Stack:**
- Spring Boot 3.2.0 with Java 17
- Maven 3.6+ for multi-module project structure
- Docker (eclipse-temurin:17-jre-alpine base images)
- OpenSSL for certificate generation
- Java keytool for keystore/truststore management
- Kubernetes manifests for deployments, services, and secrets

**Windows Users:** All bash scripts (deploy.sh, generate-certs.sh, etc.) require Git Bash, WSL, or similar Unix shell environment on Windows. PowerShell is NOT supported for these scripts.

## Project Structure

```
k8s-parent/
├── app-a/              # Spring Boot application A
│   └── src/main/java/com/k8s/appa/
│       ├── AppAApplication.java           # Main class + RestTemplate SSL config
│       ├── controller/
│       │   ├── CommunicationController.java  # /api/call-app-b endpoint
│       │   └── HealthController.java         # /health endpoint
│       └── service/
│           └── AppBClient.java            # mTLS client to call App B
├── app-b/              # Spring Boot application B (mirrors app-a structure)
│   └── src/main/java/com/k8s/appb/
│       ├── AppBApplication.java           # Main class + RestTemplate SSL config
│       └── ... (same structure as app-a)
└── k8s/                # Kubernetes resources
    ├── manifests/      # K8s deployment & service YAML files
    ├── scripts/        # Certificate generation and deployment scripts
    │   ├── deploy.sh                # Full deployment automation
    │   ├── generate-certs.sh        # Certificate generation
    │   ├── build-images.sh          # Docker image build
    │   ├── create-k8s-secrets.sh    # K8s secret creation
    │   └── cleanup.sh               # Resource cleanup
    └── certs/          # Generated certificates (git-ignored)
```

## Build Commands

### Build the entire project
```bash
mvn clean package
```

### Build a specific module
```bash
mvn clean package -pl app-a
mvn clean package -pl app-b
```

### Build Docker images manually
```bash
# Build both images (from project root, after mvn package)
docker build -t app-a:1.0.0-SNAPSHOT -f k8s/Dockerfile-app-a .
docker build -t app-b:1.0.0-SNAPSHOT -f k8s/Dockerfile-app-b .

# For Minikube, use the automated script instead:
cd k8s/scripts && bash build-images.sh
```

### Run locally (without TLS, for development)
```bash
cd app-a && mvn spring-boot:run
cd app-b && mvn spring-boot:run
```

### Run tests
```bash
# Run all tests
mvn test

# Run tests for a specific module
mvn test -pl app-a
mvn test -pl app-b

# Run a specific test class
mvn test -pl app-a -Dtest=HealthControllerTest
```

## Deployment to Minikube

### Prerequisites
- Minikube installed and running: `minikube start`
- kubectl configured to use minikube context
- OpenSSL and Java keytool installed

### Complete Deployment (All Steps)
```bash
# Run the complete deployment script
cd k8s/scripts
bash deploy.sh
```

This will deploy Vault, generate certificates, upload them to Vault, build images, and deploy both applications.

### Manual Step-by-Step Deployment

**1. Deploy and Configure Vault:**
```bash
cd k8s/scripts
bash vault-deploy.sh
```
This deploys Vault, initializes it, generates certificates, and uploads them to Vault.

**2. Build Docker Images:**
```bash
bash build-images.sh
```
This builds Maven artifacts and creates Docker images in Minikube's Docker daemon.

**3. Deploy Applications:**
```bash
cd ../manifests
kubectl apply -f app-a-service.yaml
kubectl apply -f app-a-deployment.yaml
kubectl apply -f app-b-service.yaml
kubectl apply -f app-b-deployment.yaml
```

### Verify Deployment
```bash
# Check pod status
kubectl get pods -l 'app in (app-a,app-b)'

# Check services
kubectl get services -l 'app in (app-a,app-b)'

# View logs
kubectl logs -f deployment/app-a
kubectl logs -f deployment/app-b
```

### Testing mTLS Communication

**Important**: All curl commands must provide client certificates since `client-auth=need` is configured.

**Test App A health endpoint:**
```bash
kubectl exec -it deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://localhost:8443/health
```

**Test App B health endpoint:**
```bash
kubectl exec -it deployment/app-b -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://localhost:8443/health
```

**Test mTLS from App A to App B:**
```bash
kubectl exec -it deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://app-b.default.svc.cluster.local:8443/health
kubectl exec -it deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://app-b.default.svc.cluster.local:8443/api/greet
```

**Test mTLS from App B to App A:**
```bash
kubectl exec -it deployment/app-b -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://app-a.default.svc.cluster.local:8443/health
kubectl exec -it deployment/app-b -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://app-a.default.svc.cluster.local:8443/api/greet
```

**Test application-level communication endpoints:**
```bash
kubectl exec -it deployment/app-a -- curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit --cert-type P12 https://localhost:8443/api/call-app-b
kubectl exec -it deployment/app-b -- curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit --cert-type P12 https://localhost:8443/api/call-app-a
```

### Cleanup
```bash
cd k8s/scripts
bash cleanup.sh
```
This removes all deployments, services, service accounts, and Vault from the cluster.

## Application Configuration

Both applications use the same SSL configuration pattern in `application.yml`:

- **Server Port:** 8443 (HTTPS)
- **Keystore Path:** `/etc/security/ssl/<app-name>-keystore.p12`
- **Truststore Path:** `/etc/security/ssl/truststore.jks`
- **Client Auth:** Required (`need`)
- **Passwords:** Retrieved from Vault (`changeit` by default)
- **Vault Integration:** Spring Cloud Vault with Kubernetes authentication

**Certificate Retrieval:**
- An init container (`vault-init`) retrieves certificates from Vault before the application starts
- Init container authenticates using the pod's Kubernetes service account token
- Certificates are stored base64-encoded in Vault and decoded by the init container
- Written to `/etc/security/ssl/` shared volume before application container starts
- Spring Cloud Vault retrieves only SSL passwords and configuration properties (not the binary certificate files)

**RestTemplate SSL Configuration:**
- mTLS client configuration is in the main application class (`AppAApplication.java`, `AppBApplication.java`)
- Uses Apache HttpClient 5 with `SSLContextBuilder` to load keystore and truststore
- RestTemplate bean is configured with custom `HttpComponentsClientHttpRequestFactory`
- This enables mTLS for all outgoing HTTPS requests made by the application

**Health Probes and mTLS:**
- Since `client-auth=need` requires client certificates for ALL HTTPS requests
- Kubernetes health probes use `exec` commands with curl providing client certificates
- Docker images include curl for health check authentication
- Probes use: `curl -k --cert /etc/security/ssl/<app>-keystore.p12:changeit --cert-type P12 https://localhost:8443/health`

## Endpoints

**App A:**
- `GET /health` - Health check
- `GET /api/greet` - Returns greeting message
- `GET /api/call-app-b` - Calls App B and returns response

**App B:**
- `GET /health` - Health check
- `GET /api/greet` - Returns greeting message
- `GET /api/call-app-a` - Calls App A and returns response

## Troubleshooting

**Certificates:**
- Certificates are valid for 365 days
- Regenerate using `generate-certs.sh` if expired
- Verify certificate details: `openssl x509 -in k8s/certs/app-a-cert.pem -text -noout`

**Pod Issues:**
- Check logs: `kubectl logs -f deployment/app-a`
- Describe pod: `kubectl describe pod <pod-name>`
- Verify Vault is running: `kubectl get pods -l app=vault`
- Check Vault connectivity from pod: `kubectl exec -it deployment/app-a -- curl -v http://vault.default.svc.cluster.local:8200/v1/sys/health`

**Connection Refused:**
- Ensure both apps are running: `kubectl get pods`
- Check service DNS: `kubectl exec -it deployment/app-a -- nslookup app-b`
- Verify SSL configuration in application.yml

## CI/CD - GitHub Actions

The project includes three automated GitHub Actions workflows in `.github/workflows/`:

### 1. CI Build & Test (`ci.yml`)
**Triggers:** Push/PR to main or develop branches

**Jobs:**
- Builds Maven project and runs tests
- Builds Docker images for both applications
- Runs code quality checks
- Uploads build artifacts

**Usage:**
```bash
# Triggered automatically on push/PR
# Or manually via GitHub Actions UI
```

### 2. Certificate Generation Test (`certificate-generation.yml`)
**Triggers:** Changes to certificate scripts or manual dispatch

**Tests:**
- Certificate generation script execution
- CA certificate creation and validation
- Application certificate creation with correct SANs
- PKCS#12 keystore and JKS truststore creation
- Certificate chain verification

**Usage:**
```bash
# Triggered automatically when certificate scripts change
# Or manually: Actions → Certificate Generation Test → Run workflow
```

### 3. Kubernetes Integration Test (`k8s-integration-test.yml`)
**Triggers:** Push/PR to main or manual dispatch

**Tests complete end-to-end flow:**
- Maven build
- Certificate generation
- Docker image creation
- Kubernetes deployment to Minikube cluster
- Secret creation
- Pod health checks
- mTLS communication between services (App A ↔ App B)

**Infrastructure:**
- Uses Minikube (v1.28.0) with Docker driver in GitHub Actions
- Images built on host and loaded into Minikube using `minikube image load`
- Full deployment simulation matching local development environment
- Includes verification step to ensure images are loaded before deployment

**CI-Specific Configurations:**
- `imagePullPolicy: Never` - prevents pulling from external registries
- Same health probe configuration as local deployment
- 5-minute deployment timeout with detailed failure diagnostics

**Usage:**
```bash
# Triggered automatically on push to main
# Or manually: Actions → Kubernetes Integration Test → Run workflow
```

### Local Workflow Testing
Use [act](https://github.com/nektos/act) to run workflows locally:
```bash
# Install act
brew install act  # macOS
choco install act  # Windows

# Run specific workflow
act -j build -W .github/workflows/ci.yml

# Run all workflows
act
```

### Workflow Debugging
Check workflow logs in GitHub Actions tab:
- Build failures: Check Maven dependency resolution
- Certificate issues: Verify OpenSSL availability
- K8s test failures: Review pod logs in workflow output
- Docker build issues: Ensure artifacts exist before Docker build

## Additional Documentation

For more detailed information, refer to these documents:
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Detailed architecture and mTLS communication flow
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Common issues and debugging steps
- **[docs/SECURITY.md](docs/SECURITY.md)** - Security best practices and considerations
- **[docs/LOCAL_DEVELOPMENT.md](docs/LOCAL_DEVELOPMENT.md)** - Local development without Kubernetes
- **[.github/workflows/README.md](.github/workflows/README.md)** - CI/CD workflow details and troubleshooting

## HashiCorp Vault Integration

### Overview

The project now supports **HashiCorp Vault** for centralized secret management. This is the recommended approach for production-like deployments.

**Benefits of Vault Integration:**
- **Centralized Secret Management**: All SSL certificates and passwords stored securely in Vault
- **Dynamic Secret Retrieval**: Applications fetch secrets at startup using Kubernetes authentication
- **Audit Trail**: Vault provides audit logging for all secret access
- **Secret Rotation**: Easier to rotate certificates without redeploying applications
- **Production-Ready**: Follows best practices for secret management in Kubernetes

### Architecture with Vault

**Secret Storage:**
- Vault runs as a pod in the Kubernetes cluster
- SSL keystores and truststores are stored base64-encoded in Vault's KV v2 secrets engine
- Path structure: `secret/app-a/ssl` and `secret/app-b/ssl`

**Authentication Flow:**
1. Applications use Kubernetes Service Account tokens to authenticate with Vault
2. Vault validates the token against Kubernetes API
3. Based on the service account, Vault returns the appropriate secrets
4. Applications decode base64 certificates and write them to `/etc/security/ssl/` directory
5. Spring Boot uses these certificates for mTLS configuration

**Vault Configuration:**
- **Secrets Engine**: KV v2 at `secret/`
- **Auth Method**: Kubernetes auth at `auth/kubernetes`
- **Policies**: `app-a-policy` and `app-b-policy` for least-privilege access
- **Roles**: `app-a` and `app-b` bound to respective service accounts
- **RBAC**: Vault service account has ClusterRole with `tokenreviews` and `subjectaccessreviews` permissions to validate service account tokens

**Init Container Architecture:**
The deployment uses a two-container approach:
1. **Init Container** (`vault-init` using `hashicorp/vault:1.15.4` image):
   - Runs before the application container starts
   - Authenticates with Vault using the pod's service account token
   - Retrieves base64-encoded certificates from Vault
   - Decodes and writes certificates to `/etc/security/ssl/` on a shared `emptyDir` volume
   - Must complete successfully before the application container starts
2. **Application Container** (Spring Boot):
   - Reads certificates from the shared `/etc/security/ssl/` volume
   - Uses Spring Cloud Vault only for password/property injection
   - No direct Vault communication needed for certificate files

### Deployment with Vault

**Complete Vault-based Deployment:**
```bash
cd k8s/scripts
bash deploy.sh  # Vault mode is default
```

This script will:
1. Deploy Vault to Kubernetes
2. Initialize Vault (enable KV v2, configure Kubernetes auth, create policies)
3. Generate mTLS certificates
4. Upload certificates to Vault (base64-encoded)
5. Build Docker images
6. Deploy applications (they will fetch secrets from Vault at startup)

**Manual Step-by-Step with Vault:**

1. **Deploy and Configure Vault:**
```bash
cd k8s/scripts
bash vault-deploy.sh
```

2. **Build Docker Images:**
```bash
bash build-images.sh
```

3. **Deploy Applications:**
```bash
cd ../manifests
kubectl apply -f app-a-service.yaml
kubectl apply -f app-a-deployment.yaml
kubectl apply -f app-b-service.yaml
kubectl apply -f app-b-deployment.yaml
```

### Vault Management

**Access Vault UI (Development Only):**
```bash
kubectl port-forward svc/vault 8200:8200
# Open http://localhost:8200
# Token: root
```

**View Secrets in Vault:**
```bash
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")
kubectl exec -it $VAULT_POD -- vault kv get secret/app-a/ssl
kubectl exec -it $VAULT_POD -- vault kv get secret/app-b/ssl
```

**Manually Upload Certificates to Vault:**
```bash
cd k8s/scripts
bash upload-certs-to-vault.sh
```

**Re-initialize Vault Configuration:**
```bash
cd k8s/scripts
bash init-vault.sh
```

### Spring Cloud Vault Configuration

**Dependencies Added:**
- `spring-cloud-starter-vault-config` - Core Vault integration
- `spring-cloud-vault-config-kubernetes` - Kubernetes authentication support

**Application Configuration (application.yml):**
```yaml
spring:
  cloud:
    vault:
      enabled: true
      uri: http://vault.default.svc.cluster.local:8200
      authentication: KUBERNETES
      kubernetes:
        role: app-a  # or app-b
        kubernetes-path: kubernetes
        service-account-token-file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kv:
        enabled: true
        backend: secret
        application-name: app-a  # or app-b
  config:
    import: vault://
```

**Certificate Handling:**
- Certificates are stored in Vault as base64-encoded strings in paths `secret/app-a` and `secret/app-b`
- Init container retrieves and decodes certificates before the application starts:
  ```bash
  vault kv get -field=ssl.keystore secret/app-a | base64 -d > /etc/security/ssl/app-a-keystore.p12
  vault kv get -field=ssl.truststore secret/app-a | base64 -d > /etc/security/ssl/truststore.jks
  ```
- Certificates are written to an `emptyDir` volume shared between init container and application container
- Spring Boot SSL configuration references the decoded certificate files at `/etc/security/ssl/`
- Spring Cloud Vault provides SSL passwords via property injection (e.g., `${ssl.keystore-password}`)

### Why Vault for Secret Management?

This project uses HashiCorp Vault as the exclusive secret management solution for the following reasons:

**Security Benefits:**
- **Encrypted Storage**: Secrets are encrypted at rest in Vault, not just base64-encoded
- **Fine-Grained Access Control**: Vault policies provide least-privilege access per application
- **Audit Trail**: All secret access is logged for compliance and security monitoring
- **Dynamic Secrets**: Supports secret rotation without pod restarts (when using Vault Agent)

**Operational Benefits:**
- **Centralized Management**: Single source of truth for all secrets across environments
- **Kubernetes Integration**: Native Kubernetes authentication using service account tokens
- **Production-Ready**: Industry-standard solution used in enterprise environments
- **Scalability**: Can manage secrets across multiple clusters and clouds

**Developer Experience:**
- **Spring Cloud Vault**: Seamless integration with Spring Boot applications
- **Automatic Retrieval**: Certificates are fetched automatically at startup
- **Transparent**: Applications work the same way in all environments

### Troubleshooting Vault Integration

**Vault Pod Not Starting:**
```bash
kubectl describe pod -l app=vault
kubectl logs -l app=vault
```

**Application Can't Connect to Vault:**
```bash
# Check Vault service
kubectl get svc vault

# Check Vault health
kubectl exec -it deployment/vault -- vault status

# Check application logs for Vault errors
kubectl logs -f deployment/app-a | grep -i vault
```

**Authentication Failures:**
```bash
# Verify service account exists
kubectl get sa app-a app-b vault

# Check RBAC permissions for Vault
kubectl get clusterrole vault-tokenreview
kubectl get clusterrolebinding vault-tokenreview-binding

# Check Vault Kubernetes auth configuration
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")
kubectl exec -it $VAULT_POD -- vault read auth/kubernetes/config

# Verify role bindings
kubectl exec -it $VAULT_POD -- vault read auth/kubernetes/role/app-a
kubectl exec -it $VAULT_POD -- vault read auth/kubernetes/role/app-b
```

**Common Authentication Issues:**
- **403 Forbidden "permission denied"**: Vault service account lacks RBAC permissions to validate tokens via TokenReview API. Ensure `vault-tokenreview` ClusterRole and ClusterRoleBinding exist.
- **Invalid service account**: Role bindings must match the exact service account name and namespace in the pod spec.
- **Kubernetes API unreachable**: Vault must be able to reach the Kubernetes API server. Check network policies and Vault's Kubernetes auth config.

**Secrets Not Found:**
```bash
# List all secrets in Vault
kubectl exec -it $VAULT_POD -- vault kv list secret/

# Re-upload certificates
cd k8s/scripts
bash upload-certs-to-vault.sh
```

**Certificate Decoding Issues:**
- Check init container logs: `kubectl logs <pod-name> -c vault-init`
- Ensure base64 encoding is correct when uploading to Vault (use `-w 0` flag to prevent line wrapping)
- Verify the init container successfully wrote certificates before application startup
- Check that the `emptyDir` volume is properly mounted and shared between containers


## Project Purpose

This is a local development/testing environment for validating TLS configurations and secret management patterns before production deployment. It demonstrates:
- End-to-end mTLS encryption between microservices
- Service identity verification using X.509 certificates
- Centralized secret management with HashiCorp Vault
- Kubernetes-native authentication and authorization
- Prevention of unauthorized access between internal microservices
