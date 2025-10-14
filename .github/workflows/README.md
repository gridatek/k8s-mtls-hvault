# GitHub Actions Workflows

This directory contains CI/CD workflows for testing and validating the k8s project.

## Workflows

### 1. CI - Build and Test (`ci.yml`)
**Triggers:** Push and PR to main/develop branches

**Jobs:**
- **build**: Builds Maven project, runs tests, and uploads artifacts
- **build-docker-images**: Builds Docker images for both applications
- **code-quality**: Runs Maven verify and basic code quality checks

**What it tests:**
- Maven compilation
- Unit tests
- Docker image builds
- Artifact generation

### 2. Certificate Generation Test (`certificate-generation.yml`)
**Triggers:**
- Push/PR affecting certificate generation scripts
- Manual workflow dispatch

**What it tests:**
- Certificate generation script execution
- CA certificate creation
- App A and App B certificate generation with SANs
- PKCS#12 keystore creation
- JKS truststore creation
- Certificate chain verification
- Certificate format validation

### 3. Kubernetes Integration Test (`k8s-integration-test.yml`)
**Triggers:**
- Push/PR to main branch
- Manual workflow dispatch

**What it tests:**
- Complete end-to-end deployment flow
- Certificate generation
- Maven build
- Docker image creation
- Kubernetes deployment to Minikube cluster
- Image loading into Minikube
- Secret creation
- Pod health checks
- mTLS communication between services

**Infrastructure:**
- Uses Minikube (v1.28.0) with Docker driver
- Creates ephemeral cluster for each test run
- Images built on host and loaded using `minikube image load`
- Tests actual service-to-service mTLS communication
- Matches local development environment

## Running Workflows Manually

You can trigger workflows manually from the GitHub Actions tab:
1. Go to the "Actions" tab in your repository
2. Select the workflow you want to run
3. Click "Run workflow"

## Workflow Status

Add these badges to your README.md to show workflow status:

```markdown
![CI](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/ci.yml/badge.svg)
![Certificate Generation](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/certificate-generation.yml/badge.svg)
![K8s Integration](https://github.com/gridatek/k8s-mtls-hvault/actions/workflows/k8s-integration-test.yml/badge.svg)
```

## Local Testing

To test workflows locally, you can use [act](https://github.com/nektos/act):

```bash
# Install act
brew install act  # macOS
# or
choco install act  # Windows

# Run a specific workflow
act -j build -W .github/workflows/ci.yml

# Run all workflows
act
```

## Troubleshooting

**Certificate generation fails:**
- Ensure OpenSSL is installed
- Check script permissions
- Verify certificate paths

**Docker build fails:**
- Ensure Maven artifacts are built first
- Check Dockerfile paths
- Verify base image availability

**Kubernetes tests fail:**
- Check pod logs in workflow output
- Verify resource limits
- Check secret creation
- Review service endpoints
- Ensure images are loaded into Minikube with `minikube image ls`
- Check for ImagePullBackOff errors in pod events
- Verify `imagePullPolicy: IfNotPresent` or `Never` is set in deployments

## Future Enhancements

- [ ] Add security scanning (Trivy, Snyk)
- [ ] Add SBOM generation
- [ ] Add performance testing
- [ ] Add multi-architecture builds
- [ ] Add automated releases
- [ ] Add changelog generation
