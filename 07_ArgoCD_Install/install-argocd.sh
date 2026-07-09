#!/bin/bash
set -e

echo "[1/5] Creating namespace: argocd"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "[2/5] Installing ArgoCD core components (using Server-Side Apply)..."
kubectl apply -n argocd \
  --server-side \
  --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "[3/5] Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment argocd-server -n argocd --timeout=180s

echo "[4/5] Fetching default admin password..."
DEFAULT_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode)

echo ""
echo "========================================"
echo "✅ ArgoCD installed successfully!"
echo "========================================"
echo ""
echo "Access ArgoCD UI:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "    → Open https://localhost:8080"
echo ""
echo "Login credentials:"
echo "    Username: admin"
echo "    Password: $DEFAULT_PASSWORD"
echo ""
echo "CLI login:"
echo "    argocd login localhost:8080 --username admin --password $DEFAULT_PASSWORD --insecure"