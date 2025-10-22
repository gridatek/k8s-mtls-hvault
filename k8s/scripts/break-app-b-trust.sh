#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"
PASSWORD="changeit"

echo "=== Creating Invalid Truststore for App B ==="

# Create certs directory if it doesn't exist
mkdir -p "${CERTS_DIR}"

# Generate a fake CA certificate that is NOT the one used to sign app-a and app-b
echo "Generating fake CA certificate..."
openssl req -new -x509 -keyout "${CERTS_DIR}/fake-ca-key.pem" -out "${CERTS_DIR}/fake-ca-cert.pem" -days 365 -nodes \
  -subj "/C=US/ST=Fake/L=Fake/O=Fake CA/CN=Fake CA"

# Create a truststore with the WRONG CA certificate
echo "Creating invalid truststore for app-b (with wrong CA)..."
keytool -import -trustcacerts -noprompt \
  -alias fake-ca \
  -file "${CERTS_DIR}/fake-ca-cert.pem" \
  -keystore "${CERTS_DIR}/app-b-bad-truststore.jks" \
  -storepass "${PASSWORD}" \
  -storetype JKS

echo ""
echo "=== Invalid Truststore Created ==="
echo "File: ${CERTS_DIR}/app-b-bad-truststore.jks"
echo ""
echo "This truststore contains a fake CA certificate and will NOT trust:"
echo "  - Certificates signed by the real CA used for app-a and app-b"
echo "  - This will cause mTLS handshake failures when app-b tries to validate app-a's certificate"
echo ""
echo "Next step: Run upload-bad-trust-to-vault.sh to upload this to Vault"
