#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-service-mesh}"
SERVICES=(cart customer order product)

wait_for_rollouts() {
  for service in "${SERVICES[@]}"; do
    kubectl rollout status "deployment/${service}" -n "$NAMESPACE" --timeout=300s
  done
}

show_status() {
  kubectl get pods -n "$NAMESPACE"
  kubectl get svc,endpoints -n "$NAMESPACE" cart customer order product
  kubectl get peerauthentication,destinationrule,virtualservice -n "$NAMESPACE"
}

test_readiness_from_mesh() {
  kubectl apply -f "${SCRIPT_DIR}/curl-client-cart.yaml"
  kubectl wait pod/curl-client-cart -n "$NAMESPACE" --for=condition=Ready --timeout=180s

  for service in "${SERVICES[@]}"; do
    code="$(kubectl exec -n "$NAMESPACE" curl-client-cart -c curl -- \
      curl -sS -o /dev/null -w "%{http_code}" \
      "http://${service}.${NAMESPACE}.svc.cluster.local:8090/actuator/health/readiness")"
    echo "${service} readiness: ${code}"
    if [ "$code" != "200" ]; then
      echo "Readiness check failed for ${service}."
      exit 1
    fi
  done
}

test_strict_mtls_blocks_plaintext() {
  set +e
  output="$(kubectl run curl-no-mesh \
    -n default \
    --image=curlimages/curl:8.10.1 \
    --restart=Never \
    --rm -i \
    --command -- sh -c \
    "curl -sS --max-time 5 http://product.${NAMESPACE}.svc.cluster.local:8090/actuator/health/readiness" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "Unexpected: plaintext request from default namespace succeeded."
    echo "$output"
    exit 1
  fi

  echo "Expected: plaintext request from non-mesh pod failed under STRICT mTLS."
}

test_authorization_policy() {
  kubectl apply -f "${SCRIPT_DIR}/curl-client-order.yaml"
  kubectl wait pod/curl-client-order -n "$NAMESPACE" --for=condition=Ready --timeout=180s

  kubectl apply -f "${SCRIPT_DIR}/product-cart-only-authorizationpolicy.yaml"

  cart_code="$(kubectl exec -n "$NAMESPACE" curl-client-cart -c curl -- \
    curl -sS -o /dev/null -w "%{http_code}" \
    "http://product.${NAMESPACE}.svc.cluster.local/product/v3/api-docs")"
  order_code="$(kubectl exec -n "$NAMESPACE" curl-client-order -c curl -- \
    curl -sS -o /dev/null -w "%{http_code}" \
    "http://product.${NAMESPACE}.svc.cluster.local/product/v3/api-docs")"

  kubectl delete -f "${SCRIPT_DIR}/product-cart-only-authorizationpolicy.yaml" --ignore-not-found

  echo "cart -> product: ${cart_code}"
  echo "order -> product: ${order_code}"

  if [ "$cart_code" != "200" ] || [ "$order_code" != "403" ]; then
    echo "AuthorizationPolicy test failed. Expected cart=200 and order=403."
    exit 1
  fi
}

wait_for_rollouts
show_status
test_readiness_from_mesh
test_strict_mtls_blocks_plaintext
test_authorization_policy

echo "Service mesh tests passed."
