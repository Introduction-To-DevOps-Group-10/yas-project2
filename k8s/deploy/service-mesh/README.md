# YAS Service Mesh Implementation Plan

This plan is written for the assignment:

> Configure Service Mesh on Kubernetes for the YAS microservices application:
> mTLS, service-to-service connection policy, Kiali topology, retry policy and
> curl-based tests.

## Current Assessment

The current `yas` namespace is **not yet in the mesh**.

Observed state:

```text
namespace/yas labels: kubernetes.io/metadata.name=yas,name=yas
istio-injection: not enabled
pods in yas: 1/1 Running
Istio configs in yas: none
```

Meaning:

- `yas` workloads currently do not have `istio-proxy` sidecars.
- mTLS is not enforced for `yas`.
- Kiali can only show limited/non-mesh traffic for `yas`.
- The current `service-mesh` namespace is a good isolated lab, but the assignment
  wording says "for YAS microservices application", so the final implementation
  should apply to all required YAS services, preferably in `yas` after the lab is
  validated.

## Recommended Approach

Use two phases:

1. **Lab phase**: validate Istio with a smaller namespace such as `service-mesh`.
2. **Final phase**: apply the same pattern to the real `yas` namespace and all
   required YAS services.

This avoids breaking the running web app while still producing a final solution
that matches the assignment.

## Target Final Namespace

For final delivery:

```bash
export APP_NS=yas
```

For safe testing:

```bash
export APP_NS=service-mesh
```

## Services to Include

The current running YAS backends in namespace `yas` are:

- `backoffice-bff`
- `storefront-bff`
- `cart`
- `customer`
- `inventory`
- `media`
- `order`
- `product`
- `promotion`
- `recommendation`
- `sampledata`

Some deployments are currently scaled to zero:

- `backoffice-ui`
- `storefront-ui`
- `swagger-ui`
- `webhook`
- `yas-reloader`

For the assignment, focus on backend service-to-service mesh behavior. Include
the UI services only if you need Kiali to show web-entry traffic through BFF/UI.

Minimum meaningful demo set:

- `cart`
- `customer`
- `order`
- `product`

Recommended final YAS set:

- all running backend services listed above

## Deliverables Mapping

### 1. Enable mTLS

Manifests:

- `PeerAuthentication` in `STRICT` mode for the target namespace.
- `DestinationRule` with `ISTIO_MUTUAL` for each YAS service.

Evidence:

```bash
kubectl get peerauthentication -n "$APP_NS"
kubectl get destinationrule -n "$APP_NS"
kubectl get pods -n "$APP_NS"
```

Expected:

```text
PeerAuthentication default STRICT
Each meshed pod is 2/2 Running
```

### 2. Kiali Topology

Kiali requires Prometheus. Verify:

```bash
kubectl get pods -n istio-system
kubectl get svc -n istio-system
```

Expected:

```text
istiod              Running
kiali               Running
prometheus-server   Running
```

Open Kiali:

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

Open:

```text
http://localhost:20001
```

In Kiali:

- Go to `Graph`
- Select namespace: `$APP_NS`
- Select `Versioned app graph`
- Select `Traffic`
- Use `Last 5m` or `Last 10m`

Generate traffic before taking screenshots:

```bash
kubectl exec -n "$APP_NS" curl-client-cart -c curl -- sh -c '
for i in $(seq 1 100); do
  curl -s http://cart/cart/v3/api-docs > /dev/null
  curl -s http://customer/customer/v3/api-docs > /dev/null
  curl -s http://order/order/v3/api-docs > /dev/null
  curl -s http://product/product/v3/api-docs > /dev/null
  sleep 1
done
'
```

Screenshot explanation should describe:

- which namespace is selected
- which app nodes appear
- which edges represent service-to-service calls
- which edges represent app-to-database calls
- whether traffic is successful

### 3. Retryable Scenario

Manifest:

- `VirtualService` for `product`

Normal retry policy:

- attempts: `3`
- per try timeout: `2s`
- retry on: `5xx`, connection failure, gateway error, reset

Fault-injection test:

- Temporarily inject `500` responses for `/product/v3/api-docs`.
- Keep retry policy enabled.

Evidence command:

```bash
kubectl exec -n "$APP_NS" curl-client-cart -c curl -- sh -c '
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    http://product.'"$APP_NS"'.svc.cluster.local/product/v3/api-docs
done
'
```

Expected explanation:

- The application code does not implement retry.
- Envoy sidecar applies retry based on `VirtualService`.
- With fault injection, repeated requests should still show successful responses
  more often because retries occur before returning to the client.

### 4. Authorization Policy

Manifest:

- `AuthorizationPolicy` for `product`

Demo policy:

- allow `cart` service account to call `product`
- block `order` service account from calling `product`

Allowed test:

```bash
kubectl exec -n "$APP_NS" curl-client-cart -c curl -- \
  curl -s -o /dev/null -w "cart -> product: %{http_code}\n" \
  http://product.'"$APP_NS"'.svc.cluster.local/product/v3/api-docs
```

Expected:

```text
cart -> product: 200
```

Blocked test:

```bash
kubectl exec -n "$APP_NS" curl-client-order -c curl -- \
  curl -s -o /dev/null -w "order -> product: %{http_code}\n" \
  http://product.'"$APP_NS"'.svc.cluster.local/product/v3/api-docs
```

Expected:

```text
order -> product: 403
```

Important:

- mTLS decides whether workloads can communicate securely.
- AuthorizationPolicy decides which identity is allowed to call which service.
- Source identity comes from Kubernetes service account:

```text
cluster.local/ns/<namespace>/sa/<service-account>
```

Example:

```text
cluster.local/ns/yas/sa/cart
```

## Phase 1: Safe Lab Namespace

Use this phase before touching all `yas` services.

```bash
export APP_NS=service-mesh
cd k8s/deploy/service-mesh
APP_NAMESPACE="$APP_NS" ./setup-istio-kiali.sh
NAMESPACE="$APP_NS" ./apply-yas-service-mesh.sh
./test-service-mesh.sh
```

Expected:

```text
Service mesh tests passed.
```

This proves the pattern works for:

- sidecar injection
- mTLS STRICT
- retry policy
- authorization policy
- Kiali topology

## Phase 2: Apply to the Real YAS Namespace

Before applying to `yas`, confirm all required services are healthy:

```bash
kubectl get deploy,pods,svc,endpoints -n yas
```

Enable injection:

```bash
kubectl label namespace yas istio-injection=enabled --overwrite
```

Restart deployments so sidecars are injected:

```bash
kubectl rollout restart deployment -n yas
```

Wait:

```bash
kubectl rollout status deployment/backoffice-bff -n yas --timeout=300s
kubectl rollout status deployment/storefront-bff -n yas --timeout=300s
kubectl rollout status deployment/cart -n yas --timeout=300s
kubectl rollout status deployment/customer -n yas --timeout=300s
kubectl rollout status deployment/inventory -n yas --timeout=300s
kubectl rollout status deployment/media -n yas --timeout=300s
kubectl rollout status deployment/order -n yas --timeout=300s
kubectl rollout status deployment/product -n yas --timeout=300s
kubectl rollout status deployment/promotion -n yas --timeout=300s
kubectl rollout status deployment/recommendation -n yas --timeout=300s
kubectl rollout status deployment/sampledata -n yas --timeout=300s
```

Verify sidecars:

```bash
kubectl get pods -n yas
```

Expected:

```text
<service-pod> 2/2 Running
```

Apply YAS-wide mTLS policy:

```bash
kubectl apply -f yas-mesh-core.yaml
```

The YAS-wide file should contain:

- `PeerAuthentication/default` in namespace `yas`
- one `DestinationRule` per running service

Apply retry policy:

```bash
kubectl apply -f product-retry-yas.yaml
```

Apply test clients:

```bash
kubectl apply -f curl-client-cart-yas.yaml
kubectl apply -f curl-client-order-yas.yaml
```

Apply authorization policy only during the test window:

```bash
kubectl apply -f product-cart-only-authorizationpolicy-yas.yaml
```

Remove it after capturing evidence:

```bash
kubectl delete -f product-cart-only-authorizationpolicy-yas.yaml --ignore-not-found
```

## Risk Notes for Applying to All Services

Applying service mesh to all YAS services is more faithful to the assignment, but
it has more risk:

- Every pod gets an extra `istio-proxy` sidecar, increasing memory/CPU usage.
- Existing readiness/liveness probes may need more startup delay on small
  minikube nodes.
- STRICT mTLS can block traffic from non-meshed namespaces.
- Ingress traffic from nginx to meshed services may need testing.
- Some services call external namespaces such as `postgres`, `redis`, `kafka`,
  `keycloak`; these calls may appear in Kiali as edges to external namespaces.

Mitigation:

- Test in `service-mesh` first.
- Apply to `yas` during a controlled demo window.
- Keep rollback commands ready.

Rollback:

```bash
kubectl label namespace yas istio-injection- --overwrite
kubectl delete peerauthentication -n yas default --ignore-not-found
kubectl delete destinationrule -n yas --all
kubectl delete virtualservice -n yas --all
kubectl delete authorizationpolicy -n yas --all
kubectl rollout restart deployment -n yas
```

## Current File Roles

The current files are lab-focused:

- `mesh-core.yaml`: currently targets `service-mesh`.
- `service-mesh-apps.yaml`: creates four-service lab in `service-mesh`.
- `product-retry.yaml`: currently targets `service-mesh`.
- `product-cart-only-authorizationpolicy.yaml`: currently targets `service-mesh`.
- `curl-client-cart.yaml`: currently targets `service-mesh`.
- `curl-client-order.yaml`: currently targets `service-mesh`.
- `test-service-mesh.sh`: validates the lab.

For final `yas` submission, create YAS-specific copies or template namespace
values:

- `yas-mesh-core.yaml`
- `product-retry-yas.yaml`
- `product-cart-only-authorizationpolicy-yas.yaml`
- `curl-client-cart-yas.yaml`
- `curl-client-order-yas.yaml`
- `test-yas-service-mesh.sh`

## Final Evaluation Against Assignment

Current lab namespace status:

- mTLS: done for 4 services in `service-mesh`
- Kiali topology: working for `service-mesh`
- retry policy: done for `product` in `service-mesh`
- authorization policy: done for `cart -> product` allow and `order -> product` deny
- README/test plan: available

Gap against assignment wording:

- `yas` namespace itself is not yet meshed.
- Not all YAS services are included yet.

Recommended final action:

1. Keep `service-mesh` as proof-of-concept.
2. Add YAS-wide manifests.
3. Enable injection and mTLS for `yas`.
4. Capture Kiali screenshots from `yas`.
5. Capture curl logs for retry and authorization policy in `yas`.
