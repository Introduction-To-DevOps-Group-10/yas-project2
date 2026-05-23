#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-yas-dev}"
COUNT="${COUNT:-30}"

manifest_for() {
  local name="$1"
  local manifest="${SCRIPT_DIR}/${name}-yas-dev.yaml"

  if [ ! -f "$manifest" ]; then
    echo "Missing manifest: $manifest" >&2
    exit 1
  fi

  echo "$manifest"
}

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

curl_manifest="$(manifest_for curl-client-cart)"
flaky_manifest="$(manifest_for retry-demo-flaky-app)"
retry_manifest="$(manifest_for retry-demo-virtualservice)"

if [ "$NAMESPACE" != "yas-dev" ]; then
  echo "This simplified retry demo only supports NAMESPACE=yas-dev."
  exit 1
fi

kubectl apply -f "$curl_manifest"
kubectl wait pod/curl-client-cart -n "$NAMESPACE" --for=condition=Ready --timeout=180s

kubectl apply -f "$flaky_manifest"
kubectl rollout status deployment/flaky-good -n "$NAMESPACE" --timeout=300s
kubectl rollout status deployment/flaky-bad -n "$NAMESPACE" --timeout=300s

kubectl delete -f "$retry_manifest" --ignore-not-found

echo "=== Before retry policy ==="
before="$(run_requests)"
echo "$before"
echo "--- Summary before retry ---"
echo "$before" | count_codes

kubectl apply -f "$retry_manifest"

echo "=== After retry policy ==="
after="$(run_requests)"
echo "$after"
echo "--- Summary after retry ---"
echo "$after" | count_codes

echo "Retry demo completed. Clean up with:"
echo "kubectl delete -f ${retry_manifest} --ignore-not-found"
echo "kubectl delete -f ${flaky_manifest} --ignore-not-found"
