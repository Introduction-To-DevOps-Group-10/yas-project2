#!/bin/bash
set -euo pipefail
set -x

# Add Prometheus chart repo and update.
# This project uses kube-prometheus-stack, which includes Prometheus,
# Alertmanager, Grafana, kube-state-metrics, and node-exporter.
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Read configuration value from cluster-config.yaml file
DOMAIN="$(yq -r '.domain' ./cluster-config.yaml)"
GRAFANA_USERNAME="$(yq -r '.grafana.username' ./cluster-config.yaml)"
GRAFANA_PASSWORD="$(yq -r '.grafana.password' ./cluster-config.yaml)"

# Remove optional observability components from the previous full stack.
# The minimal project scope keeps only Prometheus and Grafana.
for release in loki tempo opentelemetry-operator opentelemetry-collector promtail grafana-operator grafana; do
  helm uninstall "$release" --namespace observability --ignore-not-found || true
done

# Install Prometheus + Grafana stack.
grafana_hostname="grafana.$DOMAIN" yq -i '.hostname=env(grafana_hostname)' ./observability/prometheus.values.yaml
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --create-namespace --namespace observability \
  -f ./observability/prometheus.values.yaml \
  --set grafana.adminUser="$GRAFANA_USERNAME" \
  --set-string grafana.adminPassword="$GRAFANA_PASSWORD"

echo "Waiting for Prometheus and Grafana to be ready..."
kubectl wait --for=condition=Available deployment/prometheus-grafana \
  --namespace observability \
  --timeout=180s

kubectl wait --for=condition=Available deployment/prometheus-kube-state-metrics \
  --namespace observability \
  --timeout=180s

echo "Observability stack is ready: Prometheus + Grafana"
echo "Grafana URL: http://grafana.$DOMAIN"
echo "Port-forward fallback: kubectl port-forward -n observability svc/prometheus-grafana 3000:80"
