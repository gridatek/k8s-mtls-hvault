# Troubleshooting Guide

## Common Issues and Solutions

### 1. Health Probe Failures

#### Symptom
```
Liveness probe failed: Get "https://10.244.0.3:8443/health": remote error: tls: bad certificate
Readiness probe failed: Get "https://10.244.0.3:8443/health": remote error: tls: bad certificate
```

Pods keep restarting with `CrashLoopBackOff` or stay in `Not Ready` state.

#### Root Cause
- Health probes are trying to access mTLS-protected endpoints without client certificates
- Kubernetes `httpGet` probes don't support client certificate authentication

#### Solution
✅ Use `exec` probes with curl providing client certificates:

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

✅ Ensure curl is installed in the Docker image:
```dockerfile
RUN apk add --no-cache curl
```

---

### 2. Certificate Errors

#### Symptom A: Certificate Hostname Mismatch
```
javax.net.ssl.SSLHandshakeException: No subject alternative names matching IP address 10.244.0.5 found
```

#### Root Cause
- Certificate doesn't include the correct Subject Alternative Name (SAN)
- Kubernetes service DNS name doesn't match certificate

#### Solution
✅ Regenerate certificates with correct SANs:

```bash
cd k8s/scripts
bash generate-certs.sh
```

Verify SANs in certificate:
```bash
openssl x509 -in k8s/certs/app-a-cert.pem -text -noout | grep "DNS:"
```

Should show:
```
DNS:app-a, DNS:app-a.default.svc.cluster.local
```

#### Symptom B: Certificate Expired
```
sun.security.validator.ValidatorException: PKIX path validation failed:
java.security.cert.CertPathValidatorException: validity check failed
```

#### Root Cause
- Certificates have expired (365-day validity)

#### Solution
✅ Regenerate and redeploy certificates:

```bash
cd k8s/scripts
bash generate-certs.sh
bash create-k8s-secrets.sh

# Restart pods to pick up new certificates
kubectl rollout restart deployment/app-a
kubectl rollout restart deployment/app-b
```

---

### 3. ImagePullBackOff in CI/CD

#### Symptom
```
Failed to pull image "app-a:1.0.0-SNAPSHOT": rpc error: code = Unknown
desc = Error response from daemon: pull access denied for app-a, repository does not exist
```

#### Root Cause
- Kubernetes trying to pull local image from Docker Hub
- Image not loaded into Minikube's Docker daemon

#### Solution
✅ Load images explicitly into Minikube:

```bash
# Build images
docker build -t app-a:1.0.0-SNAPSHOT -f k8s/Dockerfile-app-a .
docker build -t app-b:1.0.0-SNAPSHOT -f k8s/Dockerfile-app-b .

# Load into Minikube
minikube image load app-a:1.0.0-SNAPSHOT
minikube image load app-b:1.0.0-SNAPSHOT

# Verify
minikube image ls | grep app-
```

✅ Or set `imagePullPolicy: Never` in deployment:

```yaml
spec:
  containers:
  - name: app-a
    image: app-a:1.0.0-SNAPSHOT
    imagePullPolicy: Never
```

---

### 4. Secret Not Found

#### Symptom
```
MountVolume.SetUp failed for volume "ssl-certs" : secret "app-a-ssl-secret" not found
```

#### Root Cause
- Kubernetes Secret doesn't exist or was deleted
- Certificates not generated before secret creation

#### Solution
✅ Create secrets with certificates:

```bash
# Generate certificates first
cd k8s/scripts
bash generate-certs.sh

# Create secrets
kubectl create secret generic app-a-ssl-secret \
  --from-file=app-a-keystore.p12=../certs/app-a-keystore.p12 \
  --from-file=truststore.jks=../certs/truststore.jks

kubectl create secret generic app-b-ssl-secret \
  --from-file=app-b-keystore.p12=../certs/app-b-keystore.p12 \
  --from-file=truststore.jks=../certs/truststore.jks

# Verify
kubectl get secrets
```

---

### 5. Application Fails to Start

#### Symptom
```
Caused by: java.security.UnrecoverableKeyException: failed to decrypt safe contents entry:
javax.crypto.BadPaddingException: Given final block not properly padded
```

#### Root Cause
- Incorrect keystore password in application.yml
- Keystore file corrupted

#### Solution
✅ Verify keystore password matches configuration:

```yaml
# application.yml
server:
  ssl:
    key-store-password: changeit  # Must match keystore creation password
```

✅ Test keystore manually:
```bash
keytool -list -v -keystore k8s/certs/app-a-keystore.p12 -storepass changeit
```

---

### 6. Service Communication Fails

#### Symptom
```
curl: (56) OpenSSL SSL_read: error:0A000412:SSL routines::ssl/tls alert bad certificate
```

#### Root Cause
- Client not providing certificate for mTLS authentication
- Wrong certificate being used

#### Solution
✅ Provide correct client certificate in curl commands:

```bash
# Inside pod
kubectl exec -it deployment/app-a -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health
```

✅ Verify certificates are mounted:
```bash
kubectl exec -it deployment/app-a -- ls -la /etc/security/ssl/
```

Should show:
```
-rw-r--r--  app-a-keystore.p12
-rw-r--r--  truststore.jks
```

---

### 7. DNS Resolution Fails

#### Symptom
```
java.net.UnknownHostException: app-b.default.svc.cluster.local:
Name or service not known
```

#### Root Cause
- Service not created
- Wrong service name or namespace

#### Solution
✅ Verify service exists:

```bash
kubectl get services
```

✅ Test DNS resolution:
```bash
kubectl exec -it deployment/app-a -- nslookup app-b.default.svc.cluster.local
```

✅ Verify service endpoints:
```bash
kubectl get endpoints app-b
```

---

### 8. Multiple Rolling Updates

#### Symptom
```
Replicas: 1 desired | 1 updated | 4 total | 0 available | 4 unavailable
OldReplicaSets: app-a-545b96dfc4, app-a-69f6577677, app-a-6d98496585
NewReplicaSet: app-a-588576db64
```

Multiple ReplicaSets created, pods never become ready.

#### Root Cause
- Multiple `kubectl patch` commands each triggering a separate rolling update
- Old pods can't terminate because new pods never become ready

#### Solution
✅ Combine patches into a single operation:

```bash
kubectl patch deployment app-a --type=strategic -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "app-a",
          "imagePullPolicy": "Never"
        }]
      }
    }
  }
}'
```

❌ Don't do this:
```bash
kubectl patch deployment app-a -p '{"spec":{"template":{"spec":{"containers":[{"name":"app-a","imagePullPolicy":"Never"}]}}}}'
kubectl patch deployment app-a -p '{"spec":{"template":{"spec":{"containers":[{"name":"app-a","readinessProbe":{"initialDelaySeconds":45}}]}}}}'
kubectl patch deployment app-a -p '{"spec":{"template":{"spec":{"containers":[{"name":"app-a","livenessProbe":{"initialDelaySeconds":90}}]}}}}'
```

---

## Debugging Commands

### Check Pod Status
```bash
# List all pods
kubectl get pods -o wide

# Describe specific pod
kubectl describe pod app-a-xxxxx

# Get pod logs
kubectl logs app-a-xxxxx

# Previous pod logs (if crashed)
kubectl logs app-a-xxxxx --previous

# Follow logs
kubectl logs -f deployment/app-a
```

### Check Events
```bash
# All events sorted by time
kubectl get events --sort-by='.lastTimestamp'

# Events for specific pod
kubectl get events --field-selector involvedObject.name=app-a-xxxxx
```

### Check Certificates
```bash
# Inside pod - list certificates
kubectl exec -it deployment/app-a -- \
  keytool -list -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12

# Check truststore
kubectl exec -it deployment/app-a -- \
  keytool -list -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit
```

### Network Debugging
```bash
# Test connectivity
kubectl exec -it deployment/app-a -- nc -zv app-b 8443

# DNS lookup
kubectl exec -it deployment/app-a -- nslookup app-b.default.svc.cluster.local

# Curl with verbose output
kubectl exec -it deployment/app-a -- \
  curl -vk --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health
```

### Check Secrets
```bash
# List secrets
kubectl get secrets

# Describe secret
kubectl describe secret app-a-ssl-secret

# Verify secret data
kubectl get secret app-a-ssl-secret -o jsonpath='{.data}'
```

### Minikube Specific
```bash
# Check Minikube status
minikube status

# SSH into Minikube node
minikube ssh

# Check images in Minikube
minikube image ls | grep app-

# Load image into Minikube
minikube image load app-a:1.0.0-SNAPSHOT
```

---

## Performance Issues

### Slow Application Startup

#### Symptom
- Pods take 60+ seconds to become ready
- Health probes timing out

#### Solutions
✅ Increase initial delay for probes:
```yaml
readinessProbe:
  initialDelaySeconds: 45  # Give app more time to start
```

✅ Adjust JVM heap:
```yaml
env:
- name: JAVA_OPTS
  value: "-Xmx512m -Xms256m"
```

✅ Profile application startup:
```bash
java -XX:+PrintFlagsFinal -jar app.jar | grep InitialHeapSize
```

### TLS Handshake Timeouts

#### Symptom
```
java.net.SocketTimeoutException: Read timed out
```

#### Solutions
✅ Increase connection timeout:
```java
RequestConfig requestConfig = RequestConfig.custom()
    .setConnectTimeout(5000)
    .setSocketTimeout(5000)
    .build();
```

✅ Enable connection pooling:
```java
PoolingHttpClientConnectionManager cm = new PoolingHttpClientConnectionManager();
cm.setMaxTotal(100);
cm.setDefaultMaxPerRoute(20);
```

---

## Prevention Best Practices

1. **Always verify certificates before deployment:**
   ```bash
   openssl x509 -in k8s/certs/app-a-cert.pem -text -noout
   ```

2. **Test locally before CI/CD:**
   ```bash
   bash k8s/scripts/deploy.sh
   ```

3. **Monitor certificate expiry:**
   ```bash
   openssl x509 -in k8s/certs/app-a-cert.pem -noout -enddate
   ```

4. **Use health checks in development:**
   ```bash
   curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
     --cert-type P12 https://localhost:8443/health
   ```

5. **Keep dependencies updated:**
   ```bash
   mvn versions:display-dependency-updates
   ```

---

## Getting Help

If you're still stuck after trying these solutions:

1. **Collect diagnostics:**
   ```bash
   kubectl get all
   kubectl describe pod app-a-xxxxx > pod-describe.txt
   kubectl logs app-a-xxxxx > pod-logs.txt
   kubectl get events > events.txt
   ```

2. **Check GitHub Issues:**
   - Search for similar issues in the repository
   - Create a new issue with diagnostics attached

3. **Review logs systematically:**
   - Application logs
   - Kubernetes events
   - Minikube logs (if applicable)

4. **Isolate the problem:**
   - Does it work locally but not in CI?
   - Does it work with one app but not the other?
   - Can you reproduce it consistently?
