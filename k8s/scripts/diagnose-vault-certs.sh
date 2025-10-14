#!/bin/bash

# Diagnostic script to verify certificate integrity in Vault

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"

echo "=== Certificate Integrity Diagnostic ==="
echo ""

# Get Vault pod name
VAULT_POD=$(kubectl get pod -l app=vault -o jsonpath="{.items[0].metadata.name}")
echo "Vault pod: $VAULT_POD"
echo ""

# Check original certificate file
echo "1. Original certificate file:"
ls -lh "${CERTS_DIR}/app-a-keystore.p12"
ORIGINAL_SIZE=$(stat -c%s "${CERTS_DIR}/app-a-keystore.p12" 2>/dev/null || stat -f%z "${CERTS_DIR}/app-a-keystore.p12")
echo "   Size: $ORIGINAL_SIZE bytes"
echo ""

# Check base64 size of original
echo "2. Base64 encoded size of original:"
ORIGINAL_B64_SIZE=$(base64 -w 0 "${CERTS_DIR}/app-a-keystore.p12" | wc -c)
echo "   Size: $ORIGINAL_B64_SIZE characters"
echo ""

# Check what's stored in Vault
echo "3. Vault stored data:"
VAULT_B64_SIZE=$(kubectl exec $VAULT_POD -- env VAULT_TOKEN=root vault kv get -format=json secret/app-a | jq -r '.data.data."ssl.keystore"' | wc -c)
echo "   Size: $VAULT_B64_SIZE characters"
echo ""

# Compare sizes
if [ "$ORIGINAL_B64_SIZE" -eq "$VAULT_B64_SIZE" ]; then
  echo "✓ Sizes match! Data appears intact."
else
  echo "✗ Size mismatch! Data is corrupted."
  echo "   Expected: $ORIGINAL_B64_SIZE"
  echo "   Got: $VAULT_B64_SIZE"
  echo "   Difference: $((VAULT_B64_SIZE - ORIGINAL_B64_SIZE)) characters"
fi
echo ""

# Test decoding from Vault
echo "4. Testing decode from Vault:"
kubectl exec $VAULT_POD -- env VAULT_TOKEN=root vault kv get -format=json secret/app-a | \
  jq -r '.data.data."ssl.keystore"' | base64 -d > /tmp/test-decode.p12

DECODED_SIZE=$(stat -c%s /tmp/test-decode.p12 2>/dev/null || stat -f%z /tmp/test-decode.p12)
echo "   Decoded file size: $DECODED_SIZE bytes"

if [ "$ORIGINAL_SIZE" -eq "$DECODED_SIZE" ]; then
  echo "✓ Decoded size matches original!"
else
  echo "✗ Decoded size mismatch!"
  echo "   Expected: $ORIGINAL_SIZE"
  echo "   Got: $DECODED_SIZE"
fi
echo ""

# Test if decoded file is valid PKCS12
echo "5. Testing PKCS12 validity:"
if openssl pkcs12 -info -in /tmp/test-decode.p12 -passin pass:changeit -noout 2>&1 | grep -q "MAC:"; then
  echo "✓ Decoded file is a valid PKCS12 keystore!"
else
  echo "✗ Decoded file is NOT a valid PKCS12 keystore!"
  echo "   First 32 bytes (hex):"
  od -An -tx1 -N 32 /tmp/test-decode.p12
fi
echo ""

# Check first few bytes
echo "6. Comparing first 32 bytes:"
echo "   Original:"
od -An -tx1 -N 32 "${CERTS_DIR}/app-a-keystore.p12"
echo "   Decoded from Vault:"
od -An -tx1 -N 32 /tmp/test-decode.p12
echo ""

# Cleanup
rm -f /tmp/test-decode.p12

echo "=== Diagnostic Complete ==="
