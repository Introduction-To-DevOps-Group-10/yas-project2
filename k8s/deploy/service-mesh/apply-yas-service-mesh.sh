#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-service-mesh}"
CHART_ROOT="${SCRIPT_DIR}/../../charts"

kubectl apply -f "${SCRIPT_DIR}/mesh-core.yaml"

helm upgrade --install yas-configuration-sm "${CHART_ROOT}/yas-configuration" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait

kubectl apply -f "${SCRIPT_DIR}/service-mesh-apps.yaml"
kubectl apply -f "${SCRIPT_DIR}/product-retry.yaml"

for deployment in cart customer order product; do
  kubectl rollout status "deployment/${deployment}" -n "$NAMESPACE" --timeout=300s
done

echo "YAS service mesh lab applied to namespace ${NAMESPACE}."
echo "Run ./test-service-mesh.sh to verify sidecars, mTLS and demo traffic."
