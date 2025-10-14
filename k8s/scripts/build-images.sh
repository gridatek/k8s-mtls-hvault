#!/bin/bash

# Build Docker images for App A and App B
# This script builds the applications and creates Docker images for Minikube

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
VERSION="1.0.0-SNAPSHOT"

echo "=== Building Docker Images for Minikube ==="

# Check if running in Minikube context
if ! kubectl config current-context | grep -q minikube; then
    echo "Warning: Not using minikube context. Current context:"
    kubectl config current-context
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Use Minikube's Docker daemon
echo "Configuring Docker to use Minikube's daemon..."
eval $(minikube docker-env)

# Build the project
echo ""
echo "Building Maven project..."
cd "${PROJECT_ROOT}"
mvn clean package -DskipTests

# Build App A Docker image
echo ""
echo "Building Docker image for App A..."
docker build -t app-a:${VERSION} -f k8s/Dockerfile-app-a .

# Build App B Docker image
echo ""
echo "Building Docker image for App B..."
docker build -t app-b:${VERSION} -f k8s/Dockerfile-app-b .

# Verify images
echo ""
echo "=== Docker Images Built Successfully ==="
docker images | grep -E "app-a|app-b"

echo ""
echo "Next steps:"
echo "1. Ensure secrets are created: ./create-k8s-secrets.sh"
echo "2. Deploy to Kubernetes: kubectl apply -f k8s/manifests/"
