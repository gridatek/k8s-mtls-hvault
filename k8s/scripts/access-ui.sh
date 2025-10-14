#!/bin/bash

# UI Access Helper Script
# Provides easy access to Vault UI and Kubernetes Dashboard

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_menu() {
    echo ""
    echo "========================================="
    echo "UI Access Menu"
    echo "========================================="
    echo "1. Access Vault UI"
    echo "2. Deploy & Access Kubernetes Dashboard"
    echo "3. Get Kubernetes Dashboard Token"
    echo "4. Show All UI Access Information"
    echo "5. Exit"
    echo "========================================="
}

access_vault_ui() {
    echo ""
    echo "=== Vault UI Access ==="
    echo ""

    # Check if Vault is running
    if ! kubectl get pod -l app=vault &>/dev/null; then
        echo "Error: Vault is not deployed!"
        echo "Deploy Vault first: bash vault-deploy.sh"
        return 1
    fi

    echo "Starting port-forward to Vault..."
    echo ""
    echo "Vault UI will be available at: http://localhost:8200"
    echo "Token: root"
    echo ""
    echo "Press Ctrl+C to stop port-forwarding"
    echo ""

    kubectl port-forward svc/vault 8200:8200
}

deploy_k8s_dashboard() {
    echo ""
    echo "=== Deploying Kubernetes Dashboard ==="
    echo ""

    # Check if already deployed
    if kubectl get namespace kubernetes-dashboard &>/dev/null; then
        echo "Kubernetes Dashboard is already deployed."
        echo "Checking status..."
        kubectl get pods -n kubernetes-dashboard
    else
        echo "Deploying Kubernetes Dashboard..."
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

        echo ""
        echo "Waiting for dashboard to be ready..."
        kubectl wait --for=condition=available --timeout=120s deployment/kubernetes-dashboard -n kubernetes-dashboard

        echo ""
        echo "Creating admin service account..."
        kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -
        kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:dashboard-admin --dry-run=client -o yaml | kubectl apply -f -

        echo ""
        echo "Kubernetes Dashboard deployed successfully!"
    fi

    echo ""
    echo "Getting access token..."
    TOKEN=$(kubectl -n kubernetes-dashboard create token dashboard-admin)

    echo ""
    echo "========================================="
    echo "Kubernetes Dashboard Access Information"
    echo "========================================="
    echo ""
    echo "1. Start the proxy (in a new terminal):"
    echo "   kubectl proxy"
    echo ""
    echo "2. Access the dashboard at:"
    echo "   http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
    echo ""
    echo "3. Use this token to login:"
    echo ""
    echo "$TOKEN"
    echo ""
    echo "========================================="
    echo ""
    read -p "Press Enter to start proxy now (Ctrl+C to stop)..."

    kubectl proxy
}

get_dashboard_token() {
    echo ""
    echo "=== Kubernetes Dashboard Token ==="
    echo ""

    if ! kubectl get serviceaccount dashboard-admin -n kubernetes-dashboard &>/dev/null; then
        echo "Error: Dashboard admin account not found!"
        echo "Deploy the dashboard first using option 2."
        return 1
    fi

    TOKEN=$(kubectl -n kubernetes-dashboard create token dashboard-admin)

    echo "Copy this token to login to the dashboard:"
    echo ""
    echo "$TOKEN"
    echo ""
}

show_all_info() {
    echo ""
    echo "========================================="
    echo "All UI Access Information"
    echo "========================================="
    echo ""

    echo "=== Vault UI ==="
    echo "Command: kubectl port-forward svc/vault 8200:8200"
    echo "URL: http://localhost:8200"
    echo "Token: root"
    echo ""

    echo "=== Kubernetes Dashboard ==="
    if kubectl get namespace kubernetes-dashboard &>/dev/null; then
        echo "Status: Deployed"
        echo "Command: kubectl proxy"
        echo "URL: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
        echo ""
        if kubectl get serviceaccount dashboard-admin -n kubernetes-dashboard &>/dev/null; then
            echo "Token:"
            kubectl -n kubernetes-dashboard create token dashboard-admin
        fi
    else
        echo "Status: Not deployed"
        echo "Deploy using option 2 in the menu"
    fi
    echo ""

    echo "=== k9s (Terminal UI) ==="
    echo "Install: brew install k9s (macOS) or choco install k9s (Windows)"
    echo "Run: k9s"
    echo ""

    echo "=== Useful kubectl commands ==="
    echo "Watch pods: kubectl get pods -w"
    echo "Watch events: kubectl get events --watch"
    echo "View logs: kubectl logs -f deployment/app-a"
    echo "Describe pod: kubectl describe pod <pod-name>"
    echo ""
}

# Main menu loop
while true; do
    show_menu
    read -p "Select an option (1-5): " choice

    case $choice in
        1)
            access_vault_ui
            ;;
        2)
            deploy_k8s_dashboard
            ;;
        3)
            get_dashboard_token
            ;;
        4)
            show_all_info
            read -p "Press Enter to continue..."
            ;;
        5)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please select 1-5."
            ;;
    esac
done
