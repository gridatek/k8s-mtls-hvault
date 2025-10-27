# JVM SSL/TLS Configuration with System Properties

This document explains how to configure mTLS using JVM system properties instead of programmatic configuration. This approach uses the JVM's built-in SSL/TLS support through system properties.

## Table of Contents
- [Overview](#overview)
- [JVM SSL System Properties](#jvm-ssl-system-properties)
- [Configuration Approaches](#configuration-approaches)
- [Implementation Examples](#implementation-examples)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Testing and Verification](#testing-and-verification)
- [Comparison: JVM Properties vs Programmatic](#comparison-jvm-properties-vs-programmatic)
- [Troubleshooting](#troubleshooting)

---

## Overview

The JVM provides system properties for configuring SSL/TLS at the JVM level. When these properties are set, they apply globally to all SSL/TLS connections made by the application, including:
- HTTPS clients (HttpsURLConnection, RestTemplate, WebClient)
- HTTPS servers (Tomcat, Jetty, etc.)
- Database connections over TLS
- Any other SSL/TLS-enabled protocols

### Current Project Approach vs JVM Properties

**Current Implementation** (Programmatic):
- SSL configuration in Java code (`AppAApplication.java`, `AppBApplication.java`)
- Uses `SSLContextBuilder` to load keystore and truststore
- RestTemplate bean configured with custom `HttpComponentsClientHttpRequestFactory`
- More control and flexibility, but requires code changes

**JVM Properties Approach** (System-wide):
- SSL configuration via JVM arguments (`-Djavax.net.ssl.*`)
- No code changes required
- Applies to entire JVM process
- Simpler for containers and microservices

---

## JVM SSL System Properties

### Core Properties

#### Keystore Configuration (Client Authentication)
```bash
# Keystore location (PKCS12 or JKS)
-Djavax.net.ssl.keyStore=/path/to/keystore.p12

# Keystore password
-Djavax.net.ssl.keyStorePassword=changeit

# Keystore type (PKCS12, JKS, etc.)
-Djavax.net.ssl.keyStoreType=PKCS12

# Key manager algorithm (SunX509, NewSunX509)
-Djavax.net.ssl.keyManagerAlgorithm=SunX509
```

#### Truststore Configuration (Server Validation)
```bash
# Truststore location
-Djavax.net.ssl.trustStore=/path/to/truststore.jks

# Truststore password
-Djavax.net.ssl.trustStorePassword=changeit

# Truststore type
-Djavax.net.ssl.trustStoreType=JKS

# Trust manager algorithm
-Djavax.net.ssl.trustManagerAlgorithm=SunX509
```

#### Debugging Properties
```bash
# Enable SSL/TLS debugging (verbose output)
-Djavax.net.debug=ssl,handshake

# Or all SSL debug info
-Djavax.net.debug=all

# Less verbose - just handshake
-Djavax.net.debug=ssl:handshake:verbose
```

#### TLS Protocol Configuration
```bash
# Specify enabled TLS protocols (comma-separated)
-Djdk.tls.client.protocols=TLSv1.3,TLSv1.2

# Disable specific TLS versions
-Djdk.tls.disabledAlgorithms=SSLv3,TLSv1,TLSv1.1
```

---

## Configuration Approaches

### Approach 1: JVM Command Line Arguments

Set properties when starting the Java application:

```bash
java -Djavax.net.ssl.keyStore=/etc/security/ssl/app-a-keystore.p12 \
     -Djavax.net.ssl.keyStorePassword=changeit \
     -Djavax.net.ssl.keyStoreType=PKCS12 \
     -Djavax.net.ssl.trustStore=/etc/security/ssl/truststore.jks \
     -Djavax.net.ssl.trustStorePassword=changeit \
     -Djavax.net.ssl.trustStoreType=JKS \
     -jar app.jar
```

### Approach 2: Environment Variable (JAVA_TOOL_OPTIONS)

The JVM automatically picks up options from the `JAVA_TOOL_OPTIONS` environment variable:

```bash
export JAVA_TOOL_OPTIONS="-Djavax.net.ssl.keyStore=/etc/security/ssl/app-a-keystore.p12 \
-Djavax.net.ssl.keyStorePassword=changeit \
-Djavax.net.ssl.keyStoreType=PKCS12 \
-Djavax.net.ssl.trustStore=/etc/security/ssl/truststore.jks \
-Djavax.net.ssl.trustStorePassword=changeit \
-Djavax.net.ssl.trustStoreType=JKS"

java -jar app.jar
```

### Approach 3: JAVA_OPTS (Custom Script)

Many deployment scripts support `JAVA_OPTS`:

```bash
export JAVA_OPTS="-Djavax.net.ssl.keyStore=/etc/security/ssl/app-a-keystore.p12 \
-Djavax.net.ssl.keyStorePassword=changeit \
-Djavax.net.ssl.keyStoreType=PKCS12 \
-Djavax.net.ssl.trustStore=/etc/security/ssl/truststore.jks \
-Djavax.net.ssl.trustStorePassword=changeit"

java $JAVA_OPTS -jar app.jar
```

### Approach 4: Spring Boot application.properties

Spring Boot allows setting system properties via `application.properties`:

```properties
# This does NOT work for JVM system properties!
# Spring Boot properties are different from JVM system properties
# You must use JAVA_OPTS or JAVA_TOOL_OPTIONS
```

**Note**: `server.ssl.*` properties in Spring Boot are for the embedded server (Tomcat), not for the JVM-wide SSL context used by clients.

### Approach 5: Programmatic Configuration (Current Approach)

Set system properties in Java code before any SSL connections:

```java
@SpringBootApplication
public class AppAApplication {

    static {
        // Set JVM SSL properties before Spring Boot starts
        System.setProperty("javax.net.ssl.keyStore", "/etc/security/ssl/app-a-keystore.p12");
        System.setProperty("javax.net.ssl.keyStorePassword", "changeit");
        System.setProperty("javax.net.ssl.keyStoreType", "PKCS12");
        System.setProperty("javax.net.ssl.trustStore", "/etc/security/ssl/truststore.jks");
        System.setProperty("javax.net.ssl.trustStorePassword", "changeit");
        System.setProperty("javax.net.ssl.trustStoreType", "JKS");
    }

    public static void main(String[] args) {
        SpringApplication.run(AppAApplication.class, args);
    }
}
```

---

## Implementation Examples

### Example 1: Minimal Code Changes for JVM Properties

If you want to use JVM system properties instead of the current programmatic approach, you can simplify the application code:

**Before (Current Approach):**
```java
@Bean
public RestTemplate restTemplate() throws Exception {
    KeyStore keyStore = KeyStore.getInstance("PKCS12");
    keyStore.load(new FileInputStream(keystorePath), keystorePassword.toCharArray());

    KeyStore trustStore = KeyStore.getInstance("JKS");
    trustStore.load(new FileInputStream(truststorePath), truststorePassword.toCharArray());

    SSLContext sslContext = SSLContextBuilder.create()
        .loadKeyMaterial(keyStore, keystorePassword.toCharArray())
        .loadTrustMaterial(trustStore, null)
        .build();

    // ... configure RestTemplate with SSL context
}
```

**After (JVM Properties Approach):**
```java
@Bean
public RestTemplate restTemplate() {
    // No SSL configuration needed - JVM handles it
    return new RestTemplate();
}
```

When using JVM system properties, the default `RestTemplate` will automatically use the configured keystore and truststore.

### Example 2: Hybrid Approach

You can also use JVM properties for some connections and programmatic configuration for others:

```java
@Bean
@Primary
public RestTemplate defaultRestTemplate() {
    // Uses JVM system properties
    return new RestTemplate();
}

@Bean("customRestTemplate")
public RestTemplate customRestTemplate() throws Exception {
    // Uses custom SSL configuration
    SSLContext sslContext = SSLContextBuilder.create()
        .loadKeyMaterial(customKeyStore, password)
        .loadTrustMaterial(customTrustStore, null)
        .build();

    // ... configure with custom SSL
}
```

### Example 3: Server-Side Configuration

For the embedded Tomcat server, you still need `application.yml` configuration:

```yaml
server:
  port: 8443
  ssl:
    enabled: true
    key-store: /etc/security/ssl/app-a-keystore.p12
    key-store-password: ${ssl.keystore-password}
    key-store-type: PKCS12
    trust-store: /etc/security/ssl/truststore.jks
    trust-store-password: ${ssl.truststore-password}
    trust-store-type: JKS
    client-auth: need
```

**Important**: `server.ssl.*` properties configure the server (Tomcat), while `javax.net.ssl.*` properties configure the client (outgoing requests).

---

## Kubernetes Deployment

### Option 1: Environment Variables in Deployment YAML

Add `JAVA_TOOL_OPTIONS` to your deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-a
spec:
  template:
    spec:
      containers:
      - name: app-a
        image: app-a:1.0.0-SNAPSHOT
        env:
        - name: JAVA_TOOL_OPTIONS
          value: >-
            -Djavax.net.ssl.keyStore=/etc/security/ssl/app-a-keystore.p12
            -Djavax.net.ssl.keyStorePassword=changeit
            -Djavax.net.ssl.keyStoreType=PKCS12
            -Djavax.net.ssl.trustStore=/etc/security/ssl/truststore.jks
            -Djavax.net.ssl.trustStorePassword=changeit
            -Djavax.net.ssl.trustStoreType=JKS
        volumeMounts:
        - name: ssl-certs
          mountPath: /etc/security/ssl
          readOnly: true
      volumes:
      - name: ssl-certs
        emptyDir: {}
```

### Option 2: ConfigMap for JVM Options

Create a ConfigMap with JVM options:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: jvm-ssl-config
data:
  JAVA_TOOL_OPTIONS: |
    -Djavax.net.ssl.keyStore=/etc/security/ssl/app-a-keystore.p12
    -Djavax.net.ssl.keyStorePassword=changeit
    -Djavax.net.ssl.keyStoreType=PKCS12
    -Djavax.net.ssl.trustStore=/etc/security/ssl/truststore.jks
    -Djavax.net.ssl.trustStorePassword=changeit
    -Djavax.net.ssl.trustStoreType=JKS
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-a
spec:
  template:
    spec:
      containers:
      - name: app-a
        image: app-a:1.0.0-SNAPSHOT
        envFrom:
        - configMapRef:
            name: jvm-ssl-config
```

### Option 3: Dockerfile ENTRYPOINT

Bake JVM options into the Docker image:

```dockerfile
FROM eclipse-temurin:17-jre-alpine

ENV JAVA_TOOL_OPTIONS="-Djavax.net.ssl.keyStore=/etc/security/ssl/app-a-keystore.p12 \
-Djavax.net.ssl.keyStorePassword=changeit \
-Djavax.net.ssl.keyStoreType=PKCS12 \
-Djavax.net.ssl.trustStore=/etc/security/ssl/truststore.jks \
-Djavax.net.ssl.trustStorePassword=changeit \
-Djavax.net.ssl.trustStoreType=JKS"

COPY app.jar /app.jar

ENTRYPOINT ["java", "-jar", "/app.jar"]
```

---

## Testing and Verification

### Verify JVM Properties Are Applied

Check that the JVM picks up the properties:

```bash
# Inside the container
kubectl exec -it deployment/app-a -- sh -c 'echo $JAVA_TOOL_OPTIONS'

# Check Java process arguments
kubectl exec -it deployment/app-a -- ps aux | grep java
```

### Enable SSL Debug Logging

Add debug flag to see SSL handshake details:

```yaml
env:
- name: JAVA_TOOL_OPTIONS
  value: >-
    -Djavax.net.ssl.keyStore=/etc/security/ssl/app-a-keystore.p12
    -Djavax.net.ssl.keyStorePassword=changeit
    -Djavax.net.ssl.keyStoreType=PKCS12
    -Djavax.net.ssl.trustStore=/etc/security/ssl/truststore.jks
    -Djavax.net.ssl.trustStorePassword=changeit
    -Djavax.net.ssl.trustStoreType=JKS
    -Djavax.net.debug=ssl:handshake:verbose
```

Then check logs:

```bash
kubectl logs -f deployment/app-a | grep -A 20 "SSL handshake"
```

### Test mTLS with JVM Properties

```bash
# Test from App A to App B
kubectl exec -it deployment/app-a -- curl -v https://app-b.default.svc.cluster.local:8443/health

# If the JVM properties are set correctly, the client will automatically
# use the keystore for client authentication and truststore for server validation
```

### Verify Keystore and Truststore Locations

```bash
# List certificates in the container
kubectl exec -it deployment/app-a -- ls -la /etc/security/ssl/

# Verify keystore
kubectl exec -it deployment/app-a -- keytool -list -keystore /etc/security/ssl/app-a-keystore.p12 -storepass changeit -storetype PKCS12

# Verify truststore
kubectl exec -it deployment/app-a -- keytool -list -keystore /etc/security/ssl/truststore.jks -storepass changeit -storetype JKS
```

---

## Comparison: JVM Properties vs Programmatic

| Aspect | JVM System Properties | Programmatic (Current) |
|--------|----------------------|------------------------|
| **Configuration Location** | JVM args / environment variables | Java code |
| **Scope** | Entire JVM process | Specific beans/components |
| **Code Changes** | None (uses default clients) | Requires SSL context setup |
| **Flexibility** | Global, one configuration | Per-client customization |
| **Testing** | Harder to override in tests | Easier to mock/inject |
| **Container-Friendly** | Very (env vars) | Requires code deployment |
| **Spring Cloud Compatibility** | Works with default RestTemplate | Requires custom bean |
| **Debugging** | `-Djavax.net.debug` flag | Must add logging in code |
| **Password Security** | Visible in env vars / process list | Can use Vault injection |
| **Certificate Rotation** | Restart required | Could implement dynamic reload |

### When to Use Each Approach

**Use JVM System Properties When:**
- All HTTP clients need the same SSL configuration
- Running in containers with environment variable support
- Simplicity is preferred over flexibility
- Using standard Java HTTP clients (HttpsURLConnection)
- No need for multiple SSL configurations in one app

**Use Programmatic Configuration When:**
- Need different SSL configs for different endpoints
- Advanced customization (custom TrustManagers, HostnameVerifiers)
- Dynamic certificate rotation without restart
- Better security (passwords not in env vars)
- Using frameworks like Apache HttpClient or OkHttp

### Hybrid Approach (Recommended for Production)

Use JVM properties for the **default** SSL configuration, and programmatic for **special cases**:

```java
// Default RestTemplate uses JVM properties (set via JAVA_TOOL_OPTIONS)
@Bean
@Primary
public RestTemplate restTemplate() {
    return new RestTemplate();
}

// Special RestTemplate for external APIs with different certificates
@Bean("externalApiRestTemplate")
public RestTemplate externalApiRestTemplate() throws Exception {
    SSLContext sslContext = SSLContextBuilder.create()
        .loadKeyMaterial(externalKeyStore, password)
        .loadTrustMaterial(externalTrustStore, null)
        .build();

    // Custom configuration...
}
```

---

## Troubleshooting

### Common Issues

**1. "PKCS12 KeyStore not available"**
- Ensure `-Djavax.net.ssl.keyStoreType=PKCS12` is set
- Verify Java version supports PKCS12 (Java 9+)

**2. "Keystore was tampered with, or password was incorrect"**
- Check password matches the one used during keystore creation
- Verify base64 encoding/decoding didn't corrupt the keystore
- Use `diagnose-vault-certs.sh` to verify integrity

**3. "HTTPS hostname wrong: should be <expected>"**
- Certificate SAN doesn't match the hostname
- Add `-Djavax.net.ssl.hostname.verifier=ALLOW_ALL` (testing only!)
- Regenerate certificates with correct SANs

**4. "No subject alternative names present"**
- Certificate missing SAN extension
- Regenerate certificates with SAN: `DNS:app-a.default.svc.cluster.local`

**5. "Unable to find valid certification path to requested target"**
- Truststore doesn't contain the CA that signed the server certificate
- Verify CA cert is in truststore: `keytool -list -keystore truststore.jks`

**6. "Received fatal alert: bad_certificate"**
- Client certificate not trusted by server
- Server's truststore doesn't contain the CA that signed the client certificate

**7. JVM properties not being picked up**
- Check `JAVA_TOOL_OPTIONS` is exported: `echo $JAVA_TOOL_OPTIONS`
- Verify process has the properties: `ps aux | grep java`
- Ensure properties are set before JVM starts (not in Java code after startup)

### Debug Commands

**Enable full SSL debugging:**
```bash
export JAVA_TOOL_OPTIONS="-Djavax.net.debug=all"
```

**Check which keystore/truststore the JVM is using:**
```bash
# Add this to your application
System.out.println("Keystore: " + System.getProperty("javax.net.ssl.keyStore"));
System.out.println("Truststore: " + System.getProperty("javax.net.ssl.trustStore"));
```

**Test SSL connection with verbose curl:**
```bash
kubectl exec -it deployment/app-a -- curl -v \
  --cert /etc/security/ssl/app-a-keystore.p12:changeit \
  --cert-type P12 \
  --cacert /etc/security/ssl/ca-cert.pem \
  https://app-b.default.svc.cluster.local:8443/health
```

### Verification Checklist

- [ ] Keystore and truststore files exist at the specified paths
- [ ] File permissions allow the Java process to read the files
- [ ] Keystore contains the private key and certificate for client auth
- [ ] Truststore contains the CA certificate that signed the server certificate
- [ ] Passwords are correct for both keystore and truststore
- [ ] Certificate SANs match the hostname being connected to
- [ ] JVM properties are set before the application starts
- [ ] `JAVA_TOOL_OPTIONS` environment variable is exported
- [ ] No conflicting programmatic SSL configuration in code

---

## Additional Resources

**Java SSL/TLS Documentation:**
- [JSSE Reference Guide](https://docs.oracle.com/javase/8/docs/technotes/guides/security/jsse/JSSERefGuide.html)
- [Java Secure Socket Extension (JSSE) API](https://docs.oracle.com/javase/8/docs/technotes/guides/security/jsse/JSSERefGuide.html#InstallationAndCustomization)

**Debugging:**
- [Debugging SSL/TLS Connections](https://docs.oracle.com/javase/8/docs/technotes/guides/security/jsse/ReadDebug.html)

**Keytool Commands:**
- [keytool - Key and Certificate Management Tool](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/keytool.html)

**Spring Boot SSL:**
- [Spring Boot - Configure SSL](https://docs.spring.io/spring-boot/docs/current/reference/html/howto.html#howto.webserver.configure-ssl)

---

## Example: Converting Current Project to JVM Properties

### Step 1: Remove Programmatic SSL Configuration

**Current `AppAApplication.java`:**
```java
@Bean
public RestTemplate restTemplate() throws Exception {
    // Remove all this SSL configuration code
}
```

**New `AppAApplication.java`:**
```java
@Bean
public RestTemplate restTemplate() {
    // Simple default RestTemplate - uses JVM properties
    return new RestTemplate();
}
```

### Step 2: Update Deployment YAML

**Add to `k8s/manifests/app-a-deployment.yaml`:**
```yaml
spec:
  template:
    spec:
      containers:
      - name: app-a
        env:
        - name: JAVA_TOOL_OPTIONS
          value: >-
            -Djavax.net.ssl.keyStore=/etc/security/ssl/app-a-keystore.p12
            -Djavax.net.ssl.keyStorePassword=changeit
            -Djavax.net.ssl.keyStoreType=PKCS12
            -Djavax.net.ssl.trustStore=/etc/security/ssl/truststore.jks
            -Djavax.net.ssl.trustStorePassword=changeit
            -Djavax.net.ssl.trustStoreType=JKS
```

### Step 3: Test

```bash
# Rebuild and redeploy
cd k8s/scripts
bash build-images.sh
kubectl rollout restart deployment/app-a

# Test mTLS
kubectl exec -it deployment/app-a -- curl -k https://localhost:8443/api/call-app-b
```

---

## Conclusion

JVM system properties provide a simple, container-friendly way to configure SSL/TLS for Java applications. While the current project uses programmatic configuration for greater control, JVM properties offer a valid alternative that reduces code complexity and works well in containerized environments.

Choose the approach that best fits your operational and security requirements. For many microservice deployments, JVM properties provide sufficient functionality with less complexity.
