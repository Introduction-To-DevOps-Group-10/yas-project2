#!/usr/bin/env bash
set -euo pipefail

ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
APP_NAMESPACE="${APP_NAMESPACE:-yas}"

helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kiali https://kiali.org/helm-charts
helm repo update

helm upgrade --install istio-base istio/base \
  --namespace "$ISTIO_NAMESPACE" \
  --create-namespace \
  --wait

helm upgrade --install istiod istio/istiod \
  --namespace "$ISTIO_NAMESPACE" \
  --wait

helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace "$ISTIO_NAMESPACE" \
  --wait \
  --set alertmanager.enabled=false \
  --set kube-state-metrics.enabled=false \
  --set prometheus-node-exporter.enabled=false \
  --set prometheus-pushgateway.enabled=false \
  --set server.persistentVolume.enabled=false

helm upgrade --install kiali-server kiali/kiali-server \
  --namespace "$ISTIO_NAMESPACE" \
  --wait \
  --set auth.strategy=anonymous \
  --set deployment.ingress.enabled=false \
  --set external_services.prometheus.url="http://prometheus-server.${ISTIO_NAMESPACE}.svc.cluster.local"

kubectl label namespace "$APP_NAMESPACE" istio-injection=enabled --overwrite

echo "Istio, Prometheus and Kiali are ready."
echo "Open Kiali with: kubectl -n ${ISTIO_NAMESPACE} port-forward svc/kiali 20001:20001"
