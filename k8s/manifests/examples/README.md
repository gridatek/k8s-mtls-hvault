# Example Kubernetes Manifests

This directory contains example deployment manifests demonstrating alternative configuration approaches for SSL/TLS in the project.

## Files

### `app-a-deployment-jvm-props.yaml`
Demonstrates how to configure mTLS using JVM system properties instead of programmatic configuration.

**Key Features:**
- Uses `JAVA_TOOL_OPTIONS` environment variable to set JVM properties
- Configures `javax.net.ssl.*` properties for keystore and truststore
- Includes both inline env configuration and ConfigMap-based configuration
- Shows how to enable SSL debugging with `-Djavax.net.debug`

**Comparison to Main Deployment:**
- Main deployment (`app-a-deployment.yaml`): Uses programmatic SSL configuration in Java code
- This example: Uses JVM system properties, no code changes required

## Usage

### Deploy with JVM Properties (Inline Configuration)

```bash
# Deploy the JVM properties version
kubectl apply -f app-a-deployment-jvm-props.yaml

# Only apply the first deployment (not the ConfigMap variant)
kubectl apply -f app-a-deployment-jvm-props.yaml --selector='!version=configmap'
```

### Deploy with JVM Properties (ConfigMap Configuration)

```bash
# Deploy the ConfigMap
kubectl apply -f app-a-deployment-jvm-props.yaml

# Deploy the ConfigMap-based deployment
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-a-configmap
# ... (copy the configmap deployment from the file)
EOF
```

### Test the Deployment

```bash
# Check pod status
kubectl get pods -l app=app-a

# View JVM options being used
kubectl exec -it deployment/app-a -- sh -c 'echo $JAVA_TOOL_OPTIONS'

# Test mTLS communication
kubectl exec -it deployment/app-a -- curl -k https://localhost:8443/health
kubectl exec -it deployment/app-a -- curl -k https://app-b.default.svc.cluster.local:8443/health
```

## When to Use Each Approach

### Use Main Deployment (Programmatic)
- Need fine-grained control over SSL configuration
- Different SSL configs for different HTTP clients
- Advanced customization (custom TrustManagers, etc.)
- Dynamic certificate rotation
- Current production deployment

### Use JVM Properties Deployment
- Simpler configuration without code changes
- All HTTP clients use the same SSL config
- Container-friendly (environment variables)
- Easier debugging with `-Djavax.net.debug`
- Standard Java clients (HttpsURLConnection)

### Use ConfigMap Approach
- Need to change JVM options without rebuilding images
- Centralized configuration management
- Different environments (dev/staging/prod) with different debug settings
- Kubernetes-native configuration management

## Enabling SSL Debugging

To enable verbose SSL debugging, modify the `JAVA_TOOL_OPTIONS` to include:

```yaml
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

Then view debug logs:

```bash
kubectl logs -f deployment/app-a | grep -A 20 "SSL handshake"
```

## Additional Resources

See [docs/JVM_SSL_CONFIGURATION.md](../../../docs/JVM_SSL_CONFIGURATION.md) for comprehensive documentation on JVM SSL/TLS configuration.
