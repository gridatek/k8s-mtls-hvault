# Kubernetes Manifests

This directory contains Kubernetes deployment manifests for App A and App B.

## Files

- `app-a-deployment.yaml` - Deployment configuration for App A
- `app-a-service.yaml` - Service configuration for App A (ClusterIP, port 8443)
- `app-b-deployment.yaml` - Deployment configuration for App B
- `app-b-service.yaml` - Service configuration for App B (ClusterIP, port 8443)

## Prerequisites

Before deploying, you must:

1. **Generate certificates** (see `../scripts/generate-certs.sh`)
2. **Create Kubernetes secrets** containing keystores and truststores

```bash
# Generate certificates
cd ../scripts
bash generate-certs.sh

# Create secrets from generated certificates
kubectl create secret generic app-a-ssl-secret \
  --from-file=app-a-keystore.p12=../certs/app-a-keystore.p12 \
  --from-file=truststore.jks=../certs/truststore.jks

kubectl create secret generic app-b-ssl-secret \
  --from-file=app-b-keystore.p12=../certs/app-b-keystore.p12 \
  --from-file=truststore.jks=../certs/truststore.jks
```

## Deployment

### Quick Deploy (All Resources)

```bash
# Deploy all resources
kubectl apply -f .

# Or use the deployment script
cd ../scripts
bash deploy.sh
```

### Manual Step-by-Step

```bash
# 1. Deploy services first
kubectl apply -f app-a-service.yaml
kubectl apply -f app-b-service.yaml

# 2. Deploy applications
kubectl apply -f app-a-deployment.yaml
kubectl apply -f app-b-deployment.yaml

# 3. Check status
kubectl get pods
kubectl get services

# 4. Wait for pods to be ready
kubectl wait --for=condition=available --timeout=120s deployment/app-a
kubectl wait --for=condition=available --timeout=120s deployment/app-b
```

## Manifest Details

### Deployments

Both deployments share similar configuration:

- **Replicas**: 1
- **Image Pull Policy**: IfNotPresent
- **Container Port**: 8443 (HTTPS)
- **Resource Limits**: None (BestEffort QoS)
- **Health Probes**: `exec` with curl (mTLS authentication)
  - Readiness: 30s initial delay, 5s period
  - Liveness: 60s initial delay, 10s period
- **Volume Mounts**: `/etc/security/ssl/` (SSL certificates from secrets)

### Services

Both services expose HTTPS on port 8443:

- **Type**: ClusterIP (internal only)
- **Port**: 8443/TCP
- **Protocol**: HTTPS with mTLS
- **DNS**: `<service-name>.default.svc.cluster.local`

## Testing

**Important**: All curl commands require client certificates due to mTLS configuration.

### Test Health Endpoints

```bash
# Test App A health
kubectl exec -it deployment/app-a -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/health

# Test App B health
kubectl exec -it deployment/app-b -- \
  curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/health
```

### Test Service-to-Service Communication

```bash
# App A → App B
kubectl exec -it deployment/app-a -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/api/greet

# App B → App A
kubectl exec -it deployment/app-b -- \
  curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit \
  --cert-type P12 \
  https://app-a.default.svc.cluster.local:8443/api/greet
```

### Test Application Endpoints

```bash
# App A calls App B internally
kubectl exec -it deployment/app-a -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/api/call-app-b

# App B calls App A internally
kubectl exec -it deployment/app-b -- \
  curl -k --cert /etc/security/ssl/app-b-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/api/call-app-a
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -o wide

# Describe pod for events
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Common issues:
# - ImagePullBackOff: Set imagePullPolicy to Never or load image into Minikube
# - CrashLoopBackOff: Check application logs for startup errors
# - Secret not found: Ensure secrets are created before deployment
```

### Health Probes Failing

```bash
# Check probe configuration
kubectl describe pod <pod-name> | grep -A 5 "Liveness\|Readiness"

# Manually test health endpoint inside pod
kubectl exec -it <pod-name> -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/health

# Common issues:
# - "bad certificate" error: Health probe missing client cert (should use exec probe)
# - Timeout: Application taking too long to start (increase initialDelaySeconds)
```

### Service Communication Issues

```bash
# Test DNS resolution
kubectl exec -it deployment/app-a -- \
  nslookup app-b.default.svc.cluster.local

# Test TCP connectivity
kubectl exec -it deployment/app-a -- nc -zv app-b 8443

# Check service endpoints
kubectl get endpoints app-b

# Common issues:
# - DNS not resolving: Service may not exist or wrong namespace
# - Connection refused: Pod not ready or wrong port
# - TLS errors: Certificate mismatch or expired
```

## Configuration Reference

### Environment Variables

Both applications support these environment variables:

- `JAVA_OPTS`: JVM options (default: `-Xmx512m -Xms256m`)
- `KEYSTORE_PASSWORD`: Keystore password (if using external secret)
- `TRUSTSTORE_PASSWORD`: Truststore password (if using external secret)

### Volume Mounts

- **Path**: `/etc/security/ssl/`
- **Read-Only**: Yes
- **Contents**:
  - `app-{a|b}-keystore.p12` - Application private key and certificate
  - `truststore.jks` - CA certificate for validation

### Health Probe Commands

The health probes use `exec` commands with curl to provide client certificates:

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
```

**Why `exec` instead of `httpGet`?**
- Kubernetes `httpGet` probes cannot provide client certificates
- mTLS requires client authentication for all requests
- `exec` probe with curl allows certificate-based authentication

## Cleanup

```bash
# Delete all resources
kubectl delete -f .

# Or delete individually
kubectl delete deployment app-a app-b
kubectl delete service app-a app-b
kubectl delete secret app-a-ssl-secret app-b-ssl-secret

# Or use cleanup script
cd ../scripts
bash cleanup.sh
```

## Further Documentation

- [Architecture Documentation](../../docs/ARCHITECTURE.md)
- [Troubleshooting Guide](../../docs/TROUBLESHOOTING.md)
- [Local Development Guide](../../docs/LOCAL_DEVELOPMENT.md)
- [Security Best Practices](../../docs/SECURITY.md)
