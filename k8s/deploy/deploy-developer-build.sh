#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="${NAMESPACE:-yas}"
DOMAIN="${DOMAIN:-$(yq -r '.domain' ./cluster-config.yaml)}"
TARGET_SERVICE="${TARGET_SERVICE:-}"
TARGET_BRANCH="${TARGET_BRANCH:-}"
TARGET_IMAGE_TAG="${TARGET_IMAGE_TAG:-${GIT_COMMIT:-}}"
DEFAULT_IMAGE_TAG="${DEFAULT_IMAGE_TAG:-}"
DEV_HOST="${DEV_HOST:-}"
DISABLE_SERVICEMONITOR="${DISABLE_SERVICEMONITOR:-true}"

if [[ -z "$TARGET_SERVICE" ]]; then
  echo "TARGET_SERVICE is required."
  exit 1
fi

if [[ -z "$TARGET_IMAGE_TAG" ]]; then
  if [[ -n "$TARGET_BRANCH" ]]; then
    TARGET_IMAGE_TAG="$(git rev-parse "origin/${TARGET_BRANCH}" 2>/dev/null || true)"
  fi
fi

if [[ -z "$TARGET_IMAGE_TAG" && -n "$TARGET_BRANCH" ]]; then
  TARGET_IMAGE_TAG="$(git rev-parse "$TARGET_BRANCH" 2>/dev/null || true)"
fi

if [[ -z "$TARGET_IMAGE_TAG" ]]; then
  TARGET_IMAGE_TAG="$(git rev-parse HEAD 2>/dev/null || true)"
fi

if [[ -z "$TARGET_IMAGE_TAG" ]]; then
  echo "TARGET_IMAGE_TAG is required. Pass the commit SHA built by CI."
  exit 1
fi

if [[ -z "$DEV_HOST" ]]; then
  DEV_HOST="${TARGET_SERVICE}-dev.${DOMAIN}"
fi

case "$TARGET_SERVICE" in
  backoffice-bff|storefront-bff|backoffice-ui|storefront-ui|swagger-ui|cart|customer|inventory|location|media|order|payment|payment-paypal|product|promotion|rating|search|tax|recommendation|webhook|sampledata)
    ;;
  *)
    echo "Unsupported TARGET_SERVICE: $TARGET_SERVICE"
    exit 1
    ;;
esac

SERVICE_MONITOR_ARGS=()
if [[ "$DISABLE_SERVICEMONITOR" == "true" ]]; then
  SERVICE_MONITOR_ARGS+=(--set backend.serviceMonitor.enabled=false)
fi

helm repo add stakater https://stakater.github.io/stakater-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

deploy_backend_chart() {
  local release="$1"
  local chart_path="$2"
  local ingress_host="$3"
  local ingress_path="$4"
  local image_tag="${5:-}"
  local use_nodeport="${6:-false}"
  local extra_args=()

  if [[ -n "$image_tag" ]]; then
    extra_args+=(--set-string backend.image.tag="$image_tag")
  fi

  if [[ "$use_nodeport" == "true" ]]; then
    extra_args+=(--set backend.service.type=NodePort)
    extra_args+=(--set backend.ingress.enabled=false)
  else
    extra_args+=(--set backend.ingress.enabled=true)
    extra_args+=(--set-string backend.ingress.host="$ingress_host")
    extra_args+=(--set-string backend.ingress.path="$ingress_path")
  fi

  helm dependency build "$chart_path"
  helm upgrade --install "$release" "$chart_path" \
    --namespace "$NAMESPACE" --create-namespace \
    --wait --atomic \
    "${extra_args[@]}" \
    "${SERVICE_MONITOR_ARGS[@]}"
}

deploy_ui_chart() {
  local release="$1"
  local chart_path="$2"
  local image_tag="${3:-}"
  local use_nodeport="${4:-false}"
  local extra_args=()

  if [[ -n "$image_tag" ]]; then
    extra_args+=(--set-string ui.image.tag="$image_tag")
  fi

  if [[ "$use_nodeport" == "true" ]]; then
    extra_args+=(--set ui.service.type=NodePort)
    extra_args+=(--set ui.ingress.enabled=false)
  fi

  helm dependency build "$chart_path"
  helm upgrade --install "$release" "$chart_path" \
    --namespace "$NAMESPACE" --create-namespace \
    --wait --atomic \
    "${extra_args[@]}"
}

deploy_swagger_chart() {
  local image_tag="${1:-}"
  local use_nodeport="${2:-false}"
  local extra_args=()

  if [[ -n "$image_tag" ]]; then
    extra_args+=(--set-string image.tag="$image_tag")
  fi

  if [[ "$use_nodeport" == "true" ]]; then
    extra_args+=(--set service.type=NodePort)
    extra_args+=(--set ingress.enabled=false)
  fi

  helm dependency build ../charts/swagger-ui
  helm upgrade --install swagger-ui ../charts/swagger-ui \
    --namespace "$NAMESPACE" --create-namespace \
    --wait --atomic \
    "${extra_args[@]}"
}

resolve_target_flag() {
  local release="$1"
  if [[ "$release" == "$TARGET_SERVICE" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

resolve_service_tag() {
  local release="$1"
  if [[ "$release" == "$TARGET_SERVICE" ]]; then
    echo "$TARGET_IMAGE_TAG"
  elif [[ -n "$DEFAULT_IMAGE_TAG" ]]; then
    echo "$DEFAULT_IMAGE_TAG"
  else
    echo ""
  fi
}

helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
  --namespace "$NAMESPACE" --create-namespace \
  --wait --atomic

deploy_backend_chart backoffice-bff ../charts/backoffice-bff "backoffice.$DOMAIN" "/" \
  "$(resolve_service_tag backoffice-bff)" "$(resolve_target_flag backoffice-bff)"

deploy_ui_chart backoffice-ui ../charts/backoffice-ui \
  "$(resolve_service_tag backoffice-ui)" "$(resolve_target_flag backoffice-ui)"

sleep 20

deploy_backend_chart storefront-bff ../charts/storefront-bff "storefront.$DOMAIN" "/" \
  "$(resolve_service_tag storefront-bff)" "$(resolve_target_flag storefront-bff)"

deploy_ui_chart storefront-ui ../charts/storefront-ui \
  "$(resolve_service_tag storefront-ui)" "$(resolve_target_flag storefront-ui)"

sleep 20

deploy_swagger_chart "$(resolve_service_tag swagger-ui)" "$(resolve_target_flag swagger-ui)"

sleep 20

for chart in cart customer inventory location media order payment payment-paypal product promotion rating search tax recommendation webhook sampledata; do
  ingress_host="api.$DOMAIN"
  ingress_path="/$chart"
  target_tag="$(resolve_service_tag "$chart")"
  target_nodeport="$(resolve_target_flag "$chart")"

  deploy_backend_chart "$chart" "../charts/$chart" "$ingress_host" "$ingress_path" \
    "$target_tag" "$target_nodeport"

  sleep 20
done

if [[ "$TARGET_SERVICE" == "swagger-ui" ]]; then
  release_name="swagger-ui"
elif [[ "$TARGET_SERVICE" == "backoffice-ui" || "$TARGET_SERVICE" == "storefront-ui" ]]; then
  release_name="$TARGET_SERVICE"
else
  release_name="$TARGET_SERVICE"
fi

node_port="$(kubectl -n "$NAMESPACE" get svc "$release_name" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || true)"
if [[ -n "$node_port" ]]; then
  echo "Developer test URL: http://${DEV_HOST}:${node_port}"
else
  echo "Service $release_name was not exposed as NodePort, so no developer URL was generated."
fi
