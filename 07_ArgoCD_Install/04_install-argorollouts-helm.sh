#!/bin/bash
set -e

echo "[1/5] Adding Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "[2/5] Creating namespace: argo-rollouts"
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -

echo "[3/5] Installing Argo Rollouts via Helm..."
helm upgrade --install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --wait \
  --timeout 5m

echo "[4/5] Waiting for Argo Rollouts controller to be ready..."
kubectl rollout status deployment argo-rollouts -n argo-rollouts --timeout=180s

echo "[5/5] Checking installation status..."
kubectl get pods -n argo-rollouts

helm upgrade argo-rollouts argo/argo-rollouts -n argo-rollouts --set dashboard.enabled=true

echo ""
echo "========================================"
echo "✅ Argo Rollouts installed successfully via Helm!"
echo "========================================"
echo ""
echo "Release name: argo-rollouts (in namespace argo-rollouts)"
echo ""
echo "To check status:"
echo "  helm status argo-rollouts -n argo-rollouts"
echo "  kubectl get pods -n argo-rollouts"
echo ""
echo "Optional: Enable the dashboard"
echo "  helm upgrade argo-rollouts argo/argo-rollouts -n argo-rollouts --set dashboard.enabled=true"
echo ""
echo "To access the dashboard (after enabling):"
echo "  kubectl argo rollouts dashboard"
echo "  → Open http://localhost:3100/rollouts"
echo ""
echo "To uninstall:"
echo "  helm uninstall argo-rollouts -n argo-rollouts"