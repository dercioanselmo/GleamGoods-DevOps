#!/bin/bash
set -e

echo "[1/5] Adding Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "[2/5] Creating namespace: argo-rollouts"
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -

echo "[3/5] Installing Argo Rollouts via Helm (with Dashboard)..."
helm upgrade --install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --set dashboard.enabled=true \
  --wait \
  --timeout 5m

echo "[4/5] Waiting for Argo Rollouts controller and dashboard to be ready..."
kubectl rollout status deployment argo-rollouts -n argo-rollouts --timeout=180s
kubectl rollout status deployment argo-rollouts-dashboard -n argo-rollouts --timeout=180s 2>/dev/null || true

echo "[5/5] Checking installation status..."
kubectl get pods -n argo-rollouts

echo ""
echo "========================================"
echo "✅ Argo Rollouts installed successfully via Helm!"
echo "========================================"
echo ""
echo "Release name: argo-rollouts (in namespace argo-rollouts)"
echo ""
echo "Access the Argo Rollouts Dashboard:"
echo "  kubectl port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3100:3100"
echo "  or kubectl argo rollouts dashboard"
echo "  → Open http://localhost:3100/rollouts"
echo ""
echo "Useful commands:"
echo "  kubectl get pods -n argo-rollouts"
echo "  helm status argo-rollouts -n argo-rollouts"
echo ""
echo "CLI Plugin (recommended):"
echo "  kubectl argo rollouts version"
echo ""
echo "To uninstall:"
echo "  helm uninstall argo-rollouts -n argo-rollouts"