# YAS Dev Service Mesh Demo

Folder nay chi giu cau hinh Service Mesh cho namespace `yas-dev`.

Muc tieu demo:

- Istio sidecar injection cho cac service trong `yas-dev`.
- mTLS `STRICT` bang `PeerAuthentication`.
- Service-to-service mTLS bang `DestinationRule` `ISTIO_MUTUAL`.
- Retry policy cho `product` bang `VirtualService`.
- AuthorizationPolicy demo: `cart` duoc goi `product`, `order` bi chan.
- Kiali topology cho namespace `yas-dev`.

## Files

Core manifests:

```text
yas-dev-mesh-core.yaml
product-retry-yas-dev.yaml
curl-client-cart-yas-dev.yaml
curl-client-order-yas-dev.yaml
product-cart-only-authorizationpolicy-yas-dev.yaml
```

Retry demo manifests:

```text
retry-demo-flaky-app-yas-dev.yaml
retry-demo-virtualservice-yas-dev.yaml
```

Scripts:

```text
setup-istio-kiali.sh
apply-yas-service-mesh.sh
test-yas-service-mesh.sh
test-retry-demo-yas.sh
```

Docs:

```text
YAS_DEV_SERVICE_MESH_DEMO.md
```

## Apply

```bash
cd k8s/deploy/service-mesh
./apply-yas-service-mesh.sh
```

## Test

```bash
./test-yas-service-mesh.sh
```

Expected highlights:

```text
All running YAS backend pods have istio-proxy sidecars.
Expected: plaintext request from non-mesh pod failed under STRICT mTLS.
product retry baseline 1: 200
cart -> product: 200
order -> product: 403
YAS service mesh tests passed.
```

## Retry Demo

```bash
./test-retry-demo-yas.sh
```

Expected highlights:

```text
--- Summary before retry ---
200: <some>
500: <some>
--- Summary after retry ---
200: 30
```

Cleanup retry demo:

```bash
kubectl delete -f retry-demo-virtualservice-yas-dev.yaml --ignore-not-found
kubectl delete -f retry-demo-flaky-app-yas-dev.yaml --ignore-not-found
```

## Kiali

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

Open:

```text
http://localhost:20001/kiali/
```

If running from EC2, create an SSH tunnel from your local machine:

```bash
ssh -L 20001:localhost:20001 ubuntu@<EC2_PUBLIC_IP>
```

Generate topology traffic:

```bash
kubectl exec -n yas-dev curl-client-cart -c curl -- sh -c '
for i in $(seq 1 100); do
  curl -s http://cart.yas-dev.svc.cluster.local/cart/v3/api-docs > /dev/null
  curl -s http://customer.yas-dev.svc.cluster.local/customer/v3/api-docs > /dev/null
  curl -s http://order.yas-dev.svc.cluster.local/order/v3/api-docs > /dev/null
  curl -s http://product.yas-dev.svc.cluster.local/product/v3/api-docs > /dev/null
  curl -s http://tax.yas-dev.svc.cluster.local/tax/v3/api-docs > /dev/null
  sleep 1
done
'
```

Kiali settings:

```text
Graph -> Namespace: yas-dev -> Last 10m -> Versioned app graph
```

## Rollback

```bash
kubectl delete peerauthentication -n yas-dev default --ignore-not-found
kubectl delete destinationrule -n yas-dev --all
kubectl delete virtualservice -n yas-dev --all
kubectl delete authorizationpolicy -n yas-dev --all
kubectl delete pod curl-client-cart curl-client-order -n yas-dev --ignore-not-found
kubectl label namespace yas-dev istio-injection- --overwrite
kubectl rollout restart deployment -n yas-dev
```
