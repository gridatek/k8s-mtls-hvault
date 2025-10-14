#!/bin/bash

# Cleanup script - removes all deployed resources including Vault

set -e

echo "========================================="
echo "Cleaning up Kubernetes resources"
echo "========================================="

echo ""
echo "Deleting application deployments..."
kubectl delete deployment app-a --ignore-not-found=true
kubectl delete deployment app-b --ignore-not-found=true

echo "Deleting application services..."
kubectl delete service app-a --ignore-not-found=true
kubectl delete service app-b --ignore-not-found=true

echo "Deleting application service accounts..."
kubectl delete serviceaccount app-a --ignore-not-found=true
kubectl delete serviceaccount app-b --ignore-not-found=true

echo ""
echo "Deleting Vault resources..."
kubectl delete deployment vault --ignore-not-found=true
kubectl delete service vault --ignore-not-found=true
kubectl delete serviceaccount vault --ignore-not-found=true
kubectl delete configmap vault-config --ignore-not-found=true
kubectl delete clusterrolebinding vault-tokenreview-binding --ignore-not-found=true
kubectl delete clusterrole vault-tokenreview --ignore-not-found=true

echo ""
echo "========================================="
echo "Cleanup Complete"
echo "========================================="
echo "All resources have been removed from the cluster."
