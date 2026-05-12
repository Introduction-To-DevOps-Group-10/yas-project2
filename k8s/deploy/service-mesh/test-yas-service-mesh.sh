#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-yas}"
RUNNING_DEPLOYMENTS=(
  backoffice-bff
  cart
  customer
  inventory
  media
  order
  product
  promotion
  recommendation
  sampledata
  storefront-bff
)
READINESS_SERVICES=(
  backoffice-bff
  cart
  customer
  inventory
  media
  order
  product
  promotion
  recommendation
  sampledata
  storefront-bff
)

wait_for_rollouts() {
  for deployment in "${RUNNING_DEPLOYMENTS[@]}"; do
    kubectl rollout status "deployment/${deployment}" -n "$NAMESPACE" --timeout=300s
  done
}

show_status() {
  kubectl get pods -n "$NAMESPACE"
  kubectl get peerauthentication,destinationrule,virtualservice -n "$NAMESPACE"
}

test_sidecars() {
  local not_ready
  not_ready="$(kubectl get pods -n "$NAMESPACE" \
    -l 'app.kubernetes.io/name in (backoffice-bff,cart,customer,inventory,media,order,product,promotion,recommendation,sampledata,storefront-bff)' \
    -o jsonpath='{range .items[?(@.status.containerStatuses)]}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.name}{","}{end}{"\n"}{end}' \
    | awk '$0 !~ /istio-proxy/ { print }')"

  if [ -n "$not_ready" ]; then
    echo "Some running YAS pods do not have istio-proxy sidecars:"
    echo "$not_ready"
    exit 1
  fi

  echo "All running YAS backend pods have istio-proxy sidecars."
}

test_readiness_from_mesh() {
  kubectl delete pod/curl-client-cart -n "$NAMESPACE" --ignore-not-found
  kubectl apply -f "${SCRIPT_DIR}/curl-client-cart-yas.yaml"
  kubectl wait pod/curl-client-cart -n "$NAMESPACE" --for=condition=Ready --timeout=180s

  for service in "${READINESS_SERVICES[@]}"; do
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

test_product_retry() {
  kubectl apply -f "${SCRIPT_DIR}/product-retry-yas.yaml"

  for i in $(seq 1 5); do
    code="$(kubectl exec -n "$NAMESPACE" curl-client-cart -c curl -- \
      curl -sS -o /dev/null -w "%{http_code}" \
      "http://product.${NAMESPACE}.svc.cluster.local/product/v3/api-docs")"
    echo "product retry baseline ${i}: ${code}"
    if [ "$code" != "200" ]; then
      echo "Product retry baseline failed."
      exit 1
    fi
  done
}

test_authorization_policy() {
  kubectl delete pod/curl-client-order -n "$NAMESPACE" --ignore-not-found
  kubectl apply -f "${SCRIPT_DIR}/curl-client-order-yas.yaml"
  kubectl wait pod/curl-client-order -n "$NAMESPACE" --for=condition=Ready --timeout=180s

  kubectl apply -f "${SCRIPT_DIR}/product-cart-only-authorizationpolicy-yas.yaml"

  cart_code="$(kubectl exec -n "$NAMESPACE" curl-client-cart -c curl -- \
    curl -sS -o /dev/null -w "%{http_code}" \
    "http://product.${NAMESPACE}.svc.cluster.local/product/v3/api-docs")"
  order_code="$(kubectl exec -n "$NAMESPACE" curl-client-order -c curl -- \
    curl -sS -o /dev/null -w "%{http_code}" \
    "http://product.${NAMESPACE}.svc.cluster.local/product/v3/api-docs")"

  kubectl delete -f "${SCRIPT_DIR}/product-cart-only-authorizationpolicy-yas.yaml" --ignore-not-found

  echo "cart -> product: ${cart_code}"
  echo "order -> product: ${order_code}"

  if [ "$cart_code" != "200" ] || [ "$order_code" != "403" ]; then
    echo "AuthorizationPolicy test failed. Expected cart=200 and order=403."
    exit 1
  fi
}

wait_for_rollouts
show_status
test_sidecars
test_readiness_from_mesh
test_strict_mtls_blocks_plaintext
test_product_retry
test_authorization_policy

echo "YAS service mesh tests passed."
