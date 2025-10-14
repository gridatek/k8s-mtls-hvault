# Local Development Guide

## Overview

This guide covers local development workflows, testing strategies, and debugging techniques for the mTLS service-to-service communication project.

## Prerequisites

### Required Software

| Tool | Version | Purpose |
|------|---------|---------|
| Java | 17+ | Application runtime |
| Maven | 3.6+ | Build tool |
| Docker | 20.10+ | Container runtime |
| Minikube | 1.32+ | Local Kubernetes cluster |
| kubectl | 1.28+ | Kubernetes CLI |
| OpenSSL | 1.1.1+ | Certificate generation |
| curl | 7.68+ | Testing mTLS endpoints |

### Optional Tools

- **k9s** - Kubernetes TUI dashboard
- **Lens** - Kubernetes IDE
- **HTTPie** - User-friendly HTTP client
- **Postman** - API testing (limited mTLS support)
- **IntelliJ IDEA** / **VS Code** - IDE with Spring Boot support

---

## Initial Setup

### 1. Clone and Build

```bash
# Clone repository
git clone https://github.com/kgridou/k8s-parent.git
cd k8s-parent

# Build all modules
mvn clean package

# Verify build
ls -la app-a/target/app-a-1.0.0-SNAPSHOT.jar
ls -la app-b/target/app-b-1.0.0-SNAPSHOT.jar
```

### 2. Start Minikube

```bash
# Start with adequate resources
minikube start --cpus=4 --memory=8192 --driver=docker

# Verify
minikube status
kubectl get nodes
```

### 3. Deploy to Minikube

```bash
# Complete deployment (generates certs, builds images, deploys)
cd k8s/scripts
bash deploy.sh

# Verify deployment
kubectl get pods
kubectl get services
```

---

## Development Workflows

### Workflow 1: Code → Build → Deploy

**When:** Making code changes to application logic

```bash
# 1. Make code changes in app-a or app-b

# 2. Build only the changed module
mvn clean package -pl app-a

# 3. Rebuild Docker image
eval $(minikube docker-env)
docker build -t app-a:1.0.0-SNAPSHOT -f k8s/Dockerfile-app-a .

# 4. Restart deployment (pulls new image)
kubectl rollout restart deployment/app-a

# 5. Watch pod restart
kubectl get pods -w

# 6. Check logs
kubectl logs -f deployment/app-a
```

### Workflow 2: Quick Iteration with Spring Boot DevTools

**When:** Rapid iteration during development

```xml
<!-- Add to pom.xml -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-devtools</artifactId>
    <optional>true</optional>
</dependency>
```

Run locally without Kubernetes:

```bash
# Terminal 1: Run App A (modify port to 8080 for dev)
cd app-a
mvn spring-boot:run -Dspring-boot.run.arguments="--server.port=8080 --server.ssl.enabled=false"

# Terminal 2: Run App B
cd app-b
mvn spring-boot:run -Dspring-boot.run.arguments="--server.port=8081 --server.ssl.enabled=false"

# Test without mTLS
curl http://localhost:8080/health
curl http://localhost:8081/health
```

### Workflow 3: Certificate Updates

**When:** Certificates expired or need to add new SANs

```bash
# 1. Regenerate certificates
cd k8s/scripts
bash generate-certs.sh

# 2. Update secrets in Kubernetes
bash create-k8s-secrets.sh

# 3. Restart pods to pick up new certificates
kubectl rollout restart deployment/app-a
kubectl rollout restart deployment/app-b

# 4. Verify new certificates
kubectl exec -it deployment/app-a -- \
  keytool -list -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12
```

---

## Testing Strategies

### Unit Tests

```bash
# Run all unit tests
mvn test

# Run tests for specific module
mvn test -pl app-a

# Run specific test class
mvn test -Dtest=CommunicationControllerTest

# Run with coverage
mvn test jacoco:report
open app-a/target/site/jacoco/index.html
```

### Integration Tests

```bash
# Run integration tests
mvn verify

# Skip unit tests, run only integration tests
mvn verify -DskipUnitTests

# Run with specific profile
mvn verify -P integration-test
```

### Manual Testing with curl

**Test health endpoints:**
```bash
# From outside pod (requires mTLS)
kubectl exec -it deployment/app-a -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/health

# Response: {"status":"UP"}
```

**Test API endpoints:**
```bash
# App A → App B
kubectl exec -it deployment/app-a -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/api/greet

# Response: "Hello from App B!"
```

**Test cross-service communication:**
```bash
# App A calls App B internally
kubectl exec -it deployment/app-a -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://localhost:8443/api/call-app-b

# Response: "App A says: Hello from App B!"
```

### Load Testing

Using Apache Bench (ab):
```bash
# Port-forward to local machine
kubectl port-forward deployment/app-a 8443:8443

# Run load test (note: ab doesn't support mTLS well, this won't work directly)
# Better to use a custom load test tool with mTLS support
```

Custom load test with Java:
```java
// LoadTest.java
public class LoadTest {
    public static void main(String[] args) throws Exception {
        SSLContext sslContext = SSLContextBuilder.create()
            .loadKeyMaterial(
                new File("/path/to/keystore.p12"),
                "changeit".toCharArray(),
                "changeit".toCharArray()
            )
            .loadTrustMaterial(new File("/path/to/truststore.jks"), "changeit".toCharArray())
            .build();

        try (CloseableHttpClient httpClient = HttpClients.custom()
                .setSSLContext(sslContext)
                .build()) {

            for (int i = 0; i < 1000; i++) {
                HttpGet request = new HttpGet("https://localhost:8443/health");
                httpClient.execute(request, response -> {
                    System.out.println("Response: " + response.getCode());
                    return null;
                });
            }
        }
    }
}
```

---

## Debugging

### Debug Application in Kubernetes

**1. Enable Java Debug Port:**

```yaml
# Modify deployment temporarily
env:
- name: JAVA_TOOL_OPTIONS
  value: "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
```

```bash
# Redeploy
kubectl apply -f k8s/manifests/app-a-deployment.yaml

# Port-forward debug port
kubectl port-forward deployment/app-a 5005:5005

# Attach debugger in IDE to localhost:5005
```

**2. IntelliJ IDEA Configuration:**

1. Run → Edit Configurations
2. Add New → Remote JVM Debug
3. Host: localhost, Port: 5005
4. Click Debug

### Debug with Logs

**Increase logging level:**

```yaml
# application.yml
logging:
  level:
    root: INFO
    com.k8s.appa: DEBUG
    org.springframework.web: DEBUG
    org.apache.http: DEBUG
    javax.net.ssl: DEBUG  # TLS debugging
```

**Enable SSL debugging:**

```yaml
env:
- name: JAVA_OPTS
  value: "-Djavax.net.debug=ssl:handshake:verbose"
```

**Stream logs:**
```bash
# Follow logs
kubectl logs -f deployment/app-a

# Tail last 100 lines
kubectl logs deployment/app-a --tail=100

# Show logs from previous container (if crashed)
kubectl logs deployment/app-a --previous

# Show logs from all pods with label
kubectl logs -l app=app-a --all-containers=true
```

### Debug Networking

**1. DNS Resolution:**
```bash
kubectl exec -it deployment/app-a -- nslookup app-b.default.svc.cluster.local

# Expected output:
# Server:    10.96.0.10
# Address:   10.96.0.10:53
#
# Name:   app-b.default.svc.cluster.local
# Address: 10.100.200.50
```

**2. Network Connectivity:**
```bash
# Test TCP connection
kubectl exec -it deployment/app-a -- nc -zv app-b 8443

# Output: Connection to app-b 8443 port [tcp/*] succeeded!
```

**3. TLS Handshake:**
```bash
kubectl exec -it deployment/app-a -- \
  openssl s_client -connect app-b.default.svc.cluster.local:8443 \
  -cert /etc/security/ssl/app-a-cert.pem \
  -key /etc/security/ssl/app-a-key.pem \
  -CAfile /etc/security/ssl/ca-cert.pem
```

### Debug Certificates

**Check certificate validity:**
```bash
# Get certificate info
openssl x509 -in k8s/certs/app-a-cert.pem -text -noout

# Check expiration
openssl x509 -in k8s/certs/app-a-cert.pem -noout -enddate

# Verify certificate chain
openssl verify -CAfile k8s/certs/ca-cert.pem k8s/certs/app-a-cert.pem
```

**Verify certificates in pod:**
```bash
# List keystore contents
kubectl exec -it deployment/app-a -- \
  keytool -list -v -keystore /etc/security/ssl/app-a-keystore.p12 \
  -storepass changeit -storetype PKCS12

# Check truststore
kubectl exec -it deployment/app-a -- \
  keytool -list -v -keystore /etc/security/ssl/truststore.jks \
  -storepass changeit
```

---

## IDE Setup

### IntelliJ IDEA

**1. Import Project:**
- File → Open → Select `pom.xml`
- Import as Maven project
- Wait for indexing

**2. Spring Boot Configuration:**
- Run → Edit Configurations → Add New → Spring Boot
- Main class: `com.k8s.appa.AppAApplication`
- Active profiles: `dev` (optional)
- VM options: `-Dserver.port=8080 -Dserver.ssl.enabled=false`

**3. Kubernetes Plugin:**
- Settings → Plugins → Install "Kubernetes"
- Configure kubectl path
- Connect to Minikube cluster

**4. Code Style:**
```xml
<!-- Add to .idea/codeStyles/Project.xml -->
<code_scheme name="Project">
  <option name="LINE_SEPARATOR" value="&#10;" />
  <option name="RIGHT_MARGIN" value="120" />
</code_scheme>
```

### VS Code

**1. Extensions:**
- Extension Pack for Java
- Spring Boot Extension Pack
- Kubernetes
- Docker

**2. Launch Configuration (`.vscode/launch.json`):**
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java",
      "name": "Debug App A",
      "request": "launch",
      "mainClass": "com.k8s.appa.AppAApplication",
      "projectName": "app-a",
      "args": "--server.port=8080 --server.ssl.enabled=false"
    }
  ]
}
```

**3. Tasks (`.vscode/tasks.json`):**
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Maven Build",
      "type": "shell",
      "command": "mvn",
      "args": ["clean", "package"],
      "group": "build"
    },
    {
      "label": "Deploy to Minikube",
      "type": "shell",
      "command": "bash",
      "args": ["k8s/scripts/deploy.sh"],
      "group": "test"
    }
  ]
}
```

---

## Common Development Tasks

### Add New Endpoint

**1. Create controller method:**
```java
@RestController
@RequestMapping("/api")
public class MyController {

    @GetMapping("/new-endpoint")
    public ResponseEntity<String> newEndpoint() {
        return ResponseEntity.ok("New endpoint response");
    }
}
```

**2. Add test:**
```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class MyControllerTest {

    @Autowired
    private TestRestTemplate restTemplate;

    @Test
    void testNewEndpoint() {
        ResponseEntity<String> response = restTemplate.getForEntity("/api/new-endpoint", String.class);
        assertEquals(HttpStatus.OK, response.getStatusCode());
    }
}
```

**3. Build and deploy:**
```bash
mvn clean package -pl app-a
eval $(minikube docker-env)
docker build -t app-a:1.0.0-SNAPSHOT -f k8s/Dockerfile-app-a .
kubectl rollout restart deployment/app-a
```

### Update Dependencies

```bash
# Check for updates
mvn versions:display-dependency-updates

# Update specific dependency
mvn versions:use-latest-versions -Dincludes=org.springframework.boot:*

# Update Spring Boot version
mvn versions:set-property -Dproperty=spring-boot.version -DnewVersion=3.2.1
```

### Add New Environment Variable

**1. Update `application.yml`:**
```yaml
app:
  custom:
    setting: ${CUSTOM_SETTING:default-value}
```

**2. Update deployment:**
```yaml
env:
- name: CUSTOM_SETTING
  value: "production-value"
```

**3. Redeploy:**
```bash
kubectl apply -f k8s/manifests/app-a-deployment.yaml
```

---

## Performance Profiling

### JVM Profiling

**1. Enable JMX:**
```yaml
env:
- name: JAVA_OPTS
  value: >
    -Dcom.sun.management.jmxremote
    -Dcom.sun.management.jmxremote.port=9010
    -Dcom.sun.management.jmxremote.authenticate=false
    -Dcom.sun.management.jmxremote.ssl=false
```

**2. Port-forward and connect:**
```bash
kubectl port-forward deployment/app-a 9010:9010
jconsole localhost:9010
```

### Spring Boot Actuator

**1. Enable actuator endpoints:**
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
```

**2. Access metrics:**
```bash
kubectl port-forward deployment/app-a 8443:8443

# View metrics (with mTLS)
curl -k --cert /path/to/app-a-keystore.p12:changeit --cert-type P12 \
  https://localhost:8443/actuator/metrics
```

---

## Tips & Tricks

### Quick Commands

```bash
# Rebuild and restart everything
alias redeploy="mvn clean package && cd k8s/scripts && bash deploy.sh && cd ../.."

# Get pod shell
alias app-a-shell="kubectl exec -it deployment/app-a -- /bin/sh"

# Quick logs
alias app-a-logs="kubectl logs -f deployment/app-a"

# Cleanup and restart Minikube
alias fresh-start="minikube delete && minikube start --cpus=4 --memory=8192"
```

### Useful Scripts

**Quick Test Script (`test-mtls.sh`):**
```bash
#!/bin/bash
POD=$(kubectl get pod -l app=app-a -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -- \
  curl -k --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  https://app-b.default.svc.cluster.local:8443/health
```

### Troubleshooting Checklist

- [ ] Minikube is running: `minikube status`
- [ ] Pods are ready: `kubectl get pods`
- [ ] Services exist: `kubectl get services`
- [ ] Secrets exist: `kubectl get secrets`
- [ ] Certificates are valid: `openssl x509 -in k8s/certs/app-a-cert.pem -noout -enddate`
- [ ] DNS works: `kubectl exec -it deployment/app-a -- nslookup app-b`
- [ ] Images are in Minikube: `minikube image ls | grep app-`

---

## Next Steps

- Review [ARCHITECTURE.md](ARCHITECTURE.md) for system design
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
- See [SECURITY.md](SECURITY.md) for security best practices
- Explore [GitHub Actions workflows](../.github/workflows/README.md) for CI/CD
