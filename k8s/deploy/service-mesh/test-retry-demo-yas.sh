#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-yas}"
COUNT="${COUNT:-30}"

count_codes() {
  awk '
    /^[0-9][0-9][0-9]$/ { counts[$1]++ }
    END {
      for (code in counts) {
        print code ": " counts[code]
      }
    }
  '
}

run_requests() {
  kubectl exec -n "$NAMESPACE" curl-client-cart -c curl -- sh -c "
    for i in \$(seq 1 ${COUNT}); do
      curl -s -o /dev/null -w '%{http_code}\n' http://flaky.${NAMESPACE}.svc.cluster.local/
    done
  "
}

kubectl apply -f "${SCRIPT_DIR}/curl-client-cart-yas.yaml"
kubectl wait pod/curl-client-cart -n "$NAMESPACE" --for=condition=Ready --timeout=180s

kubectl apply -f "${SCRIPT_DIR}/retry-demo-flaky-app-yas.yaml"
kubectl rollout status deployment/flaky-good -n "$NAMESPACE" --timeout=300s
kubectl rollout status deployment/flaky-bad -n "$NAMESPACE" --timeout=300s

kubectl delete -f "${SCRIPT_DIR}/retry-demo-virtualservice-yas.yaml" --ignore-not-found

echo "=== Before retry policy ==="
before="$(run_requests)"
echo "$before"
echo "--- Summary before retry ---"
echo "$before" | count_codes

kubectl apply -f "${SCRIPT_DIR}/retry-demo-virtualservice-yas.yaml"

echo "=== After retry policy ==="
after="$(run_requests)"
echo "$after"
echo "--- Summary after retry ---"
echo "$after" | count_codes

echo "Retry demo completed. Clean up with:"
echo "kubectl delete -f ${SCRIPT_DIR}/retry-demo-virtualservice-yas.yaml --ignore-not-found"
echo "kubectl delete -f ${SCRIPT_DIR}/retry-demo-flaky-app-yas.yaml --ignore-not-found"
