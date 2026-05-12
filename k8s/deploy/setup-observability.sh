#!/bin/bash
set -euo pipefail
set -x

# Add observability chart repos and update
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Read configuration value from cluster-config.yaml file
DOMAIN="$(yq -r '.domain' ./cluster-config.yaml)"
POSTGRESQL_USERNAME="$(yq -r '.postgresql.username' ./cluster-config.yaml)"
POSTGRESQL_PASSWORD="$(yq -r '.postgresql.password' ./cluster-config.yaml)"
GRAFANA_USERNAME="$(yq -r '.grafana.username' ./cluster-config.yaml)"
GRAFANA_PASSWORD="$(yq -r '.grafana.password' ./cluster-config.yaml)"

# Install cert-manager, required by opentelemetry-operator webhooks.
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.0 \
  --set installCRDs=true \
  --set prometheus.enabled=false \
  --set webhook.timeoutSeconds=4 \
  --set admissionWebhooks.certManager.create=true

echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Available deployment/cert-manager-webhook \
  --namespace cert-manager \
  --timeout=120s

# Install prometheus + grafana stack
grafana_hostname="grafana.$DOMAIN" yq -i '.hostname=env(grafana_hostname)' ./observability/prometheus.values.yaml
postgresql_username="$POSTGRESQL_USERNAME" yq -i '.grafana."grafana.ini".database.user=env(postgresql_username)' ./observability/prometheus.values.yaml
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --create-namespace --namespace observability \
  -f ./observability/prometheus.values.yaml \
  --set grafana.assertNoLeakedSecrets=false \
  --set-string 'grafana.grafana\.ini.database.password'="$POSTGRESQL_PASSWORD"

# Install loki
helm upgrade --install loki grafana/loki \
  --create-namespace --namespace observability \
  -f ./observability/loki.values.yaml

# Install tempo
helm upgrade --install tempo grafana/tempo \
  --create-namespace --namespace observability \
  -f ./observability/tempo.values.yaml

# Install opentelemetry-operator
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --create-namespace --namespace observability

echo "Waiting for opentelemetry-operator to be ready..."
kubectl wait --for=condition=Available deployment/opentelemetry-operator \
  --namespace observability \
  --timeout=120s

# Install opentelemetry-collector
helm upgrade --install opentelemetry-collector ./observability/opentelemetry \
  --create-namespace --namespace observability

# Install promtail
helm upgrade --install promtail grafana/promtail \
  --create-namespace --namespace observability \
  --values ./observability/promtail.values.yaml

# Install grafana operator
helm upgrade --install grafana-operator oci://ghcr.io/grafana-operator/helm-charts/grafana-operator \
  --version v5.0.2 \
  --create-namespace --namespace observability

# Install grafana datasource and dashboard
helm upgrade --install grafana ./observability/grafana \
  --create-namespace --namespace observability \
  --set hostname="grafana.$DOMAIN" \
  --set grafana.username="$GRAFANA_USERNAME" \
  --set grafana.password="$GRAFANA_PASSWORD" \
  --set postgresql.username="$POSTGRESQL_USERNAME" \
  --set postgresql.password="$POSTGRESQL_PASSWORD"
