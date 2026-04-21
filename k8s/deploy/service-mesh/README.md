# YAS Service Mesh

This folder contains an Istio + Kiali setup for the `yas` namespace.

What is included:
- Namespace-wide sidecar injection for `yas`
- Strict mTLS between YAS services in Kubernetes
- `DestinationRule` resources for the YAS services, excluding `search` and `payment-paypal`
- Retry policy for `product`
- A dedicated `AuthorizationPolicy` test manifest that allows only `cart` to call `product`
- Two curl-based test pods that let you verify allow and deny behavior from inside the cluster

## Files

- `setup-istio-kiali.sh`: installs Istio, Prometheus and Kiali
- `apply-yas-service-mesh.sh`: applies the core YAS mesh policies and restarts deployments
- `mesh-core.yaml`: namespace label, strict mTLS and service `DestinationRule` resources
- `product-retry.yaml`: retry policy for calls to `product`
- `product-retry-fault-test.yaml`: retry test version that injects `500` responses on `/product/v3/api-docs`
- `product-cart-only-authorizationpolicy.yaml`: only allows calls to `product` when the source service account is `cart`
- `curl-client-cart.yaml`: debug pod that runs with the `cart` service account
- `curl-client-order.yaml`: debug pod that runs with the `order` service account

## Install Istio and Kiali

Run:

```bash
cd k8s/deploy/service-mesh
chmod +x setup-istio-kiali.sh apply-yas-service-mesh.sh
./setup-istio-kiali.sh
```

Then apply the mesh to YAS:

```bash
./apply-yas-service-mesh.sh
```

## Verify mTLS

1. Check that sidecars were injected into YAS pods. Every meshed pod should contain an `istio-proxy` container:

```bash
kubectl get pods -n yas -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'
```

2. Confirm that `search` and `payment-paypal` are excluded. If they are deployed, they should not have `istio-proxy`.

3. Confirm the namespace policy is strict:

```bash
kubectl get peerauthentication -n yas
kubectl get destinationrule -n yas
```

## Open Kiali and view the topology

Start a local tunnel:

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

Open `http://localhost:20001`, choose namespace `yas`, then open the Graph page.

If the graph is empty, generate traffic first:

```bash
kubectl apply -f curl-client-cart.yaml
kubectl exec -n yas curl-client-cart -c curl -- curl -s http://product.yas.svc.cluster.local/product/v3/api-docs > /dev/null
kubectl exec -n yas curl-client-cart -c curl -- curl -s http://cart.yas.svc.cluster.local/cart/v3/api-docs > /dev/null
```

## Test retry policy

Apply the retry test manifest:

```bash
kubectl apply -f product-retry-fault-test.yaml
```

Create the cart test pod if needed:

```bash
kubectl apply -f curl-client-cart.yaml
```

Run several requests from inside the cluster:

```bash
kubectl exec -n yas curl-client-cart -c curl -- sh -c 'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code}\n" http://product.yas.svc.cluster.local/product/v3/api-docs; done'
```

Expected behavior:
- Istio injects `500` for part of the calls on the first try
- The retry policy retries automatically up to 3 times
- You should still see successful `200` responses in repeated runs instead of frequent failures

When the retry test is done, restore the normal retry policy:

```bash
kubectl apply -f product-retry.yaml
```

## Test the authorization policy

Warning: this policy is intentionally restrictive. Once applied, only `cart` is allowed to call `product`. Other services such as `order`, `promotion`, `inventory` and `recommendation` will be blocked from `product` until the policy is removed.

Apply the test clients:

```bash
kubectl apply -f curl-client-cart.yaml
kubectl apply -f curl-client-order.yaml
```

Apply the policy:

```bash
kubectl apply -f product-cart-only-authorizationpolicy.yaml
```

Test allowed traffic from `cart`:

```bash
kubectl exec -n yas curl-client-cart -c curl -- curl -I http://product.yas.svc.cluster.local/product/v3/api-docs
```

Expected result: `HTTP/1.1 200`

Test blocked traffic from `order`:

```bash
kubectl exec -n yas curl-client-order -c curl -- curl -I http://product.yas.svc.cluster.local/product/v3/api-docs
```

Expected result: `HTTP/1.1 403`

Remove the restrictive policy when you finish:

```bash
kubectl delete -f product-cart-only-authorizationpolicy.yaml
```

## Cleanup test pods

```bash
kubectl delete -f curl-client-cart.yaml --ignore-not-found
kubectl delete -f curl-client-order.yaml --ignore-not-found
```
