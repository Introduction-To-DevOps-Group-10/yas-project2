#!/bin/bash
set -x

# Set DISABLE_SERVICEMONITOR=true to skip creating ServiceMonitor resources.
DISABLE_SERVICEMONITOR="${DISABLE_SERVICEMONITOR:-true}"
SERVICE_MONITOR_ARGS=()
if [ "$DISABLE_SERVICEMONITOR" = "true" ]; then
    SERVICE_MONITOR_ARGS+=(--set backend.serviceMonitor.enabled=false)
fi

# Auto restart when change configmap or secret
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

read -rd '' DOMAIN \
< <(yq -r '.domain' ./cluster-config.yaml)

# Deploy shared ConfigMaps before services that mount them.
helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
--namespace yas --create-namespace

helm dependency build ../charts/backoffice-bff
helm upgrade --install backoffice-bff ../charts/backoffice-bff \
--namespace yas --create-namespace \
--set backend.ingress.host="backoffice.$DOMAIN" \
"${SERVICE_MONITOR_ARGS[@]}"

helm dependency build ../charts/backoffice-ui
helm upgrade --install backoffice-ui ../charts/backoffice-ui \
--namespace yas --create-namespace

sleep 20

helm dependency build ../charts/storefront-bff
helm upgrade --install storefront-bff ../charts/storefront-bff \
--namespace yas --create-namespace \
--set backend.ingress.host="storefront.$DOMAIN" \
"${SERVICE_MONITOR_ARGS[@]}"

helm dependency build ../charts/storefront-ui
helm upgrade --install storefront-ui ../charts/storefront-ui \
--namespace yas --create-namespace

sleep 20

helm upgrade --install swagger-ui ../charts/swagger-ui \
--namespace yas --create-namespace \
--set ingress.host="api.$DOMAIN"

sleep 20

for chart in {"cart","customer","inventory","location","media","order","payment","payment-paypal","product","promotion","rating","search","tax","recommendation","webhook","sampledata"} ; do
    helm dependency build ../charts/"$chart"
    helm upgrade --install "$chart" ../charts/"$chart" \
    --namespace yas --create-namespace \
    --set backend.ingress.enabled=true \
    --set backend.ingress.host="api.$DOMAIN" \
    --set backend.ingress.path="/$chart" \
    "${SERVICE_MONITOR_ARGS[@]}"
    sleep 20
done
