#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-yas-dev}"

if [ "$NAMESPACE" != "yas-dev" ]; then
  echo "This simplified service-mesh demo only supports NAMESPACE=yas-dev."
  exit 1
fi

kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite

kubectl apply -f "${SCRIPT_DIR}/yas-dev-mesh-core.yaml"
kubectl apply -f "${SCRIPT_DIR}/product-retry-yas-dev.yaml"
kubectl apply -f "${SCRIPT_DIR}/curl-client-cart-yas-dev.yaml"

for deployment in \
  backoffice-bff cart customer inventory media order product promotion \
  recommendation sampledata storefront-bff storefront-ui tax yas-reloader
do
  kubectl rollout status "deployment/${deployment}" -n "$NAMESPACE" --timeout=300s
done

kubectl wait pod/curl-client-cart -n "$NAMESPACE" --for=condition=Ready --timeout=180s

echo "YAS service mesh demo applied to namespace ${NAMESPACE}."
echo "Run: NAMESPACE=${NAMESPACE} ./test-yas-service-mesh.sh"
