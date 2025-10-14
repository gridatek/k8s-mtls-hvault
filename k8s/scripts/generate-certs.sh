#!/bin/bash

# Certificate Generation Script for mTLS
# This script generates CA certificate, application certificates, keystores, and truststores

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"
VALIDITY_DAYS=365
PASSWORD="changeit"

# Create certs directory if it doesn't exist
mkdir -p "${CERTS_DIR}"
cd "${CERTS_DIR}"

echo "=== Generating Certificates for mTLS ==="
echo "Output directory: ${CERTS_DIR}"

# Clean up old certificates
echo "Cleaning up old certificates..."
rm -f *.pem *.crt *.key *.csr *.p12 *.jks

# 1. Generate CA (Certificate Authority)
echo ""
echo "Step 1: Generating CA certificate..."
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days ${VALIDITY_DAYS} -key ca-key.pem -out ca-cert.pem \
  -subj "/C=US/ST=State/L=City/O=K8S/OU=CA/CN=k8s-ca"

echo "CA certificate generated: ca-cert.pem"

# 2. Generate App A certificate
echo ""
echo "Step 2: Generating App A certificate..."
openssl genrsa -out app-a-key.pem 2048
openssl req -new -key app-a-key.pem -out app-a.csr \
  -subj "/C=US/ST=State/L=City/O=K8S/OU=AppA/CN=app-a.default.svc.cluster.local"

# Create SAN config for App A
cat > app-a-san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = app-a
DNS.2 = app-a.default
DNS.3 = app-a.default.svc
DNS.4 = app-a.default.svc.cluster.local
DNS.5 = localhost
IP.1 = 127.0.0.1
EOF

openssl x509 -req -in app-a.csr -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out app-a-cert.pem -days ${VALIDITY_DAYS} \
  -extensions v3_req -extfile app-a-san.cnf

echo "App A certificate generated: app-a-cert.pem"

# 3. Generate App B certificate
echo ""
echo "Step 3: Generating App B certificate..."
openssl genrsa -out app-b-key.pem 2048
openssl req -new -key app-b-key.pem -out app-b.csr \
  -subj "/C=US/ST=State/L=City/O=K8S/OU=AppB/CN=app-b.default.svc.cluster.local"

# Create SAN config for App B
cat > app-b-san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = app-b
DNS.2 = app-b.default
DNS.3 = app-b.default.svc
DNS.4 = app-b.default.svc.cluster.local
DNS.5 = localhost
IP.1 = 127.0.0.1
EOF

openssl x509 -req -in app-b.csr -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out app-b-cert.pem -days ${VALIDITY_DAYS} \
  -extensions v3_req -extfile app-b-san.cnf

echo "App B certificate generated: app-b-cert.pem"

# 4. Create PKCS12 keystores for each application
echo ""
echo "Step 4: Creating PKCS12 keystores..."

# App A keystore
openssl pkcs12 -export -in app-a-cert.pem -inkey app-a-key.pem \
  -out app-a-keystore.p12 -name app-a -passout pass:${PASSWORD}
echo "App A keystore created: app-a-keystore.p12"

# App B keystore
openssl pkcs12 -export -in app-b-cert.pem -inkey app-b-key.pem \
  -out app-b-keystore.p12 -name app-b -passout pass:${PASSWORD}
echo "App B keystore created: app-b-keystore.p12"

# 5. Create Java truststore (JKS) with CA certificate
echo ""
echo "Step 5: Creating Java truststore..."
keytool -import -trustcacerts -file ca-cert.pem -alias ca \
  -keystore truststore.jks -storepass ${PASSWORD} -noprompt
echo "Truststore created: truststore.jks"

# 6. Verify certificates
echo ""
echo "Step 6: Verifying certificates..."
echo "App A certificate:"
openssl x509 -in app-a-cert.pem -noout -subject -issuer -ext subjectAltName
echo ""
echo "App B certificate:"
openssl x509 -in app-b-cert.pem -noout -subject -issuer -ext subjectAltName

# List generated files
echo ""
echo "=== Certificate Generation Complete ==="
echo "Generated files in ${CERTS_DIR}:"
ls -lh *.p12 *.jks 2>/dev/null || true

echo ""
echo "Next steps:"
echo "1. Upload certificates to Vault: ./upload-certs-to-vault.sh"
echo "2. Build Docker images: ./build-images.sh"
echo "3. Deploy applications: kubectl apply -f ../manifests/"
echo ""
echo "Or use the complete deployment script: ./deploy.sh"
