#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-yas}"

kubectl apply -f "${SCRIPT_DIR}/mesh-core.yaml"
kubectl apply -f "${SCRIPT_DIR}/product-retry.yaml"

kubectl rollout restart deployment -n "$NAMESPACE"

while IFS= read -r deployment; do
  kubectl rollout status "$deployment" -n "$NAMESPACE" --timeout=300s
done < <(kubectl get deployment -n "$NAMESPACE" -o name)

echo "YAS service mesh policies applied to namespace ${NAMESPACE}."
