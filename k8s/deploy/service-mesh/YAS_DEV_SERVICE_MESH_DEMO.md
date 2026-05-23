# Huong dan demo Service Mesh cho `yas-dev`

File nay dung de demo phan Service Mesh: mTLS, topology Kiali, retry policy va
authorization policy. Namespace demo la:

```bash
yas-dev
```

## 1. Muc tieu can show

Khi demo, can chung minh du 4 y:

- Cac service trong `yas-dev` da vao Istio mesh.
- mTLS dang bat o che do `STRICT`.
- Kiali hien duoc topology/flow cua service.
- Co test retry va authorization policy bang `curl`.

## 1.1. Ket qua demo da verify

Lan demo thu tren `yas-dev` da pass cac diem chinh sau:

```text
istiod              1/1 Running
kiali               1/1 Running
prometheus-server   2/2 Running
```

Namespace:

```text
yas-dev   Active   istio-injection=enabled
```

Mesh config:

```text
peerauthentication.security.istio.io/default   STRICT
destinationrule.networking.istio.io/cart-mtls
destinationrule.networking.istio.io/customer-mtls
destinationrule.networking.istio.io/order-mtls
destinationrule.networking.istio.io/product-mtls
destinationrule.networking.istio.io/tax-mtls
virtualservice.networking.istio.io/product-retry
```

Readiness tu pod trong mesh:

```text
backoffice-bff readiness: 200
cart readiness: 200
customer readiness: 200
inventory readiness: 200
media readiness: 200
order readiness: 200
product readiness: 200
promotion readiness: 200
recommendation readiness: 200
sampledata readiness: 200
storefront-bff readiness: 200
tax readiness: 200
```

mTLS STRICT chan request tu pod ngoai mesh:

```text
curl: (56) Recv failure: Connection reset by peer
```

Retry baseline:

```text
product retry baseline 1: 200
product retry baseline 2: 200
product retry baseline 3: 200
product retry baseline 4: 200
product retry baseline 5: 200
```

AuthorizationPolicy demo:

```text
cart -> product: 200
order -> product: 403
```

Sau khi demo authorization, policy `product-cart-only` da duoc xoa lai de khong
anh huong flow dev.

## 2. Kiem tra control plane Istio

Lenh:

```bash
kubectl get pods -n istio-system
```

Expected output:

```text
istiod              1/1 Running
kiali               1/1 Running
prometheus-server   2/2 Running
```

Neu `kiali` va `prometheus-server` dang tat, bat lai:

```bash
kubectl scale deployment/prometheus-server -n istio-system --replicas=1
kubectl scale deployment/kiali -n istio-system --replicas=1
kubectl rollout status deployment/prometheus-server -n istio-system --timeout=240s
kubectl rollout status deployment/kiali -n istio-system --timeout=240s
```

Neu Kiali bao `Metrics are disabled`, restart Kiali sau khi Prometheus da Ready:

```bash
kubectl rollout restart deployment/kiali -n istio-system
kubectl rollout status deployment/kiali -n istio-system --timeout=180s
```

## 3. Kiem tra namespace da bat injection

Lenh:

```bash
kubectl get ns yas-dev --show-labels
```

Expected output can show:

```text
istio-injection=enabled
```

Giai thich:

- Label nay lam cho pod moi trong namespace `yas-dev` duoc inject container
  `istio-proxy`.

## 4. Kiem tra pod da co sidecar

Lenh:

```bash
kubectl get pods -n yas-dev
```

Expected output:

```text
backoffice-bff   2/2 Running
cart             2/2 Running
customer         2/2 Running
inventory        2/2 Running
media            2/2 Running
order            2/2 Running
product          2/2 Running
promotion        2/2 Running
recommendation   2/2 Running
sampledata       2/2 Running
storefront-bff   2/2 Running
storefront-ui    2/2 Running
tax              2/2 Running
yas-reloader     2/2 Running
```

Giai thich:

- `2/2` nghia la moi pod co app container va `istio-proxy`.
- Neu pod chi `1/1` thi pod do chua vao mesh.

Lenh chi tiet hon de show ten container:

```bash
kubectl get pods -n yas-dev -o jsonpath='{range .items[*]}{.metadata.name}{" | "}{range .status.containerStatuses[*]}{.name}{":"}{.ready}{","}{end}{"\n"}{end}'
```

Expected output co dang:

```text
cart-xxxxx | cart:true,istio-proxy:true,
product-xxxxx | product:true,istio-proxy:true,
```

## 5. Apply manifest Service Mesh

Neu chua apply, chay:

```bash
kubectl apply -f k8s/deploy/service-mesh/yas-dev-mesh-core.yaml
kubectl apply -f k8s/deploy/service-mesh/product-retry-yas-dev.yaml
```

Kiem tra:

```bash
kubectl get peerauthentication,destinationrule,virtualservice -n yas-dev
```

Expected output can show:

```text
peerauthentication.security.istio.io/default   STRICT
destinationrule.networking.istio.io/cart-mtls
destinationrule.networking.istio.io/customer-mtls
destinationrule.networking.istio.io/order-mtls
destinationrule.networking.istio.io/product-mtls
virtualservice.networking.istio.io/product-retry
```

Giai thich:

- `PeerAuthentication/default STRICT`: bat mTLS bat buoc trong namespace.
- `DestinationRule ... ISTIO_MUTUAL`: client trong mesh goi service bang mutual TLS.
- `VirtualService/product-retry`: retry policy cho service `product`.

## 6. Test readiness tu pod trong mesh

Tao curl client nam trong mesh:

```bash
kubectl apply -f k8s/deploy/service-mesh/curl-client-cart-yas-dev.yaml
kubectl wait pod/curl-client-cart -n yas-dev --for=condition=Ready --timeout=180s
```

Chay readiness test:

```bash
kubectl exec -n yas-dev curl-client-cart -c curl -- sh -c '
for svc in backoffice-bff cart customer inventory media order product promotion recommendation sampledata storefront-bff tax; do
  code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 8 http://${svc}.yas-dev.svc.cluster.local:8090/actuator/health/readiness || true)
  echo "$svc readiness: $code"
done
'
```

Expected output:

```text
backoffice-bff readiness: 200
cart readiness: 200
customer readiness: 200
inventory readiness: 200
media readiness: 200
order readiness: 200
product readiness: 200
promotion readiness: 200
recommendation readiness: 200
sampledata readiness: 200
storefront-bff readiness: 200
tax readiness: 200
```

Giai thich:

- Request xuat phat tu `curl-client-cart`, pod nay co sidecar.
- Traffic di qua Envoy sidecar va mTLS.

## 7. Test STRICT mTLS chan pod ngoai mesh

Chay curl tu namespace `default`, pod nay khong co sidecar:

```bash
kubectl run yas-dev-no-mesh-check \
  -n default \
  --image=curlimages/curl:8.10.1 \
  --restart=Never \
  --rm -i \
  --command -- sh -c \
  'curl -sS --max-time 5 http://product.yas-dev.svc.cluster.local:8090/actuator/health/readiness'
```

Expected output:

```text
curl: (56) Recv failure: Connection reset by peer
```

Hoac request fail/timeout.

Giai thich:

- Namespace `default` khong nam trong mesh.
- Request khong co mTLS certificate.
- `yas-dev` dang `PeerAuthentication STRICT`, nen product sidecar tu choi plaintext.

## 8. Test retry policy cho `product`

Baseline test:

```bash
kubectl exec -n yas-dev curl-client-cart -c curl -- sh -c '
for i in $(seq 1 5); do
  curl -sS -o /dev/null -w "product retry baseline $i: %{http_code}\n" --max-time 8 http://product.yas-dev.svc.cluster.local/product/v3/api-docs
done
'
```

Expected output:

```text
product retry baseline 1: 200
product retry baseline 2: 200
product retry baseline 3: 200
product retry baseline 4: 200
product retry baseline 5: 200
```

Show manifest retry:

```bash
kubectl get virtualservice product-retry -n yas-dev -o yaml
```

Can chi ra phan:

```yaml
retries:
  attempts: 3
  perTryTimeout: 2s
  retryOn: 5xx,connect-failure,refused-stream,gateway-error,reset
```

Giai thich:

- Retry khong nam trong code ung dung.
- Envoy sidecar ap dung retry dua tren `VirtualService`.

## 9. Demo retry voi service tra 500 that

Neu can evidence manh hon baseline, dung retry demo flaky.

Apply va chay test:

```bash
NAMESPACE=yas-dev k8s/deploy/service-mesh/test-retry-demo-yas.sh
```

Script nay da duoc rut gon cho demo `yas-dev`, nen chi dung cac manifest `*-yas-dev.yaml`.

Expected output truoc retry:

```text
--- Summary before retry ---
200: 12
500: 18
```

Expected output sau retry:

```text
--- Summary after retry ---
200: 30
```

Giai thich:

- Demo tao service `flaky` co endpoint `good` tra `200` va endpoint `bad` tra `500`.
- Truoc retry, request bi load balance vao ca endpoint loi nen co `500`.
- Sau retry, Envoy gap `500` se thu lai toi endpoint khac, nen ty le `200` tang manh.
- Manifest demo flaky dung CPU request rat nho va `strategy: Recreate` de tranh ket node minikube khi YAS dang chay day du.

Don resource demo sau khi chup output:

```bash
kubectl delete -f k8s/deploy/service-mesh/retry-demo-virtualservice-yas-dev.yaml --ignore-not-found
kubectl delete -f k8s/deploy/service-mesh/retry-demo-flaky-app-yas-dev.yaml --ignore-not-found
```

## 10. Demo AuthorizationPolicy

Muc tieu:

- Chi cho `cart` goi `product`.
- Chan `order` goi `product`.

Luu y:

- Khong nen de policy nay bat lau trong moi truong dev vi co the chan flow that.
- Chi apply trong luc demo, sau do delete.

Tao curl client identity `order`:

```bash
kubectl apply -f k8s/deploy/service-mesh/curl-client-order-yas-dev.yaml
kubectl wait pod/curl-client-order -n yas-dev --for=condition=Ready --timeout=180s
```

Apply policy demo:

```bash
kubectl apply -f k8s/deploy/service-mesh/product-cart-only-authorizationpolicy-yas-dev.yaml
```

Test allowed:

```bash
kubectl exec -n yas-dev curl-client-cart -c curl -- \
  curl -sS -o /dev/null -w "cart -> product: %{http_code}\n" \
  http://product.yas-dev.svc.cluster.local/product/v3/api-docs
```

Expected:

```text
cart -> product: 200
```

Test blocked:

```bash
kubectl exec -n yas-dev curl-client-order -c curl -- \
  curl -sS -o /dev/null -w "order -> product: %{http_code}\n" \
  http://product.yas-dev.svc.cluster.local/product/v3/api-docs
```

Expected:

```text
order -> product: 403
```

Delete policy sau demo:

```bash
kubectl delete -f k8s/deploy/service-mesh/product-cart-only-authorizationpolicy-yas-dev.yaml --ignore-not-found
```

Can giai thich:

- Istio AuthorizationPolicy dung workload identity.
- Source principal cua cart la:

```text
cluster.local/ns/yas-dev/sa/cart
```

- Source principal cua order la:

```text
cluster.local/ns/yas-dev/sa/order
```

## 11. Mo Kiali topology

Port-forward Kiali:

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

Expected terminal output:

```text
Forwarding from 127.0.0.1:20001 -> 20001
Forwarding from [::1]:20001 -> 20001
```

Mo tren browser:

```text
http://localhost:20001/kiali/
```

Neu dang dung EC2 va can SSH tunnel tu may local:

```bash
ssh -L 20001:localhost:20001 ubuntu@<EC2_PUBLIC_IP>
```

Sau do van mo:

```text
http://localhost:20001/kiali/
```

Neu Kiali mo duoc nhung Graph bao `Metrics are disabled`, kiem tra Kiali status:

```bash
curl -sS http://127.0.0.1:20001/kiali/api/status
```

Expected trong JSON:

```text
"name": "Prometheus"
"version": "3.11.3"
```

Neu chua thay Prometheus, restart Kiali sau khi Prometheus da Ready:

```bash
kubectl rollout restart deployment/kiali -n istio-system
kubectl rollout status deployment/kiali -n istio-system --timeout=180s
```

Sau do mo lai port-forward.

Trong Kiali:

- Chon `Graph`.
- Namespace: `yas-dev`.
- Graph type: `Versioned app graph`.
- Time range: `Last 5m` hoac `Last 10m`.
- Bat options hien thi Traffic/Security neu can.

## 12. Tao traffic de Kiali hien topology

Chay:

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

Sau do refresh Kiali Graph.

Can chup screenshot:

- Graph namespace `yas-dev`.
- Thay node `curl-client-cart`.
- Thay cac node service: `cart`, `customer`, `order`, `product`, `tax`.
- Thay cac edge request tu curl client toi cac service.
- Neu Kiali hien icon khoa/mTLS, chi ra traffic dang secure.

Expected tren Kiali:

```text
Namespace: yas-dev
Graph type: Versioned app graph hoac Service graph
Time range: Last 5m hoac Last 10m
Nodes: curl-client-cart, cart, customer, order, product, tax
Edges: curl-client-cart -> cart/customer/order/product/tax
```

Neu Kiali hien thong ke kieu:

```text
11 apps
11 versions
3 services
12 edges
```

thi van hop le. `apps`/`versions` la workload nodes; `services` la so Kubernetes
Service nodes ma Kiali render trong graph mode hien tai, khong phai tong so
microservice dang chay.

## 13. Checklist lay diem

Truoc khi demo:

```bash
kubectl get pods -n istio-system
kubectl get pods -n yas-dev
kubectl get peerauthentication,destinationrule,virtualservice -n yas-dev
kubectl get pod curl-client-cart -n yas-dev
```

Trong demo can show:

- `istiod`, `kiali`, `prometheus-server` Running.
- Namespace `yas-dev` co `istio-injection=enabled`.
- Pod app `2/2 Running`.
- `PeerAuthentication default STRICT`.
- `DestinationRule` co `ISTIO_MUTUAL`.
- `VirtualService product-retry` co retry policy.
- Curl trong mesh tra `200`.
- Curl ngoai mesh bi reject.
- AuthorizationPolicy demo co `cart -> product: 200`, `order -> product: 403`.
- Kiali Graph co topology.

## 14. Cleanup sau demo

Neu chi muon tat Kiali/Prometheus de giai phong tai nguyen:

```bash
kubectl scale deployment/kiali -n istio-system --replicas=0
kubectl scale deployment/prometheus-server -n istio-system --replicas=0
```

Khong tat `istiod` neu namespace `yas-dev` van dang dung sidecar va mTLS.

Neu muon rollback service mesh cua `yas-dev`:

```bash
kubectl delete peerauthentication -n yas-dev default --ignore-not-found
kubectl delete destinationrule -n yas-dev --all
kubectl delete virtualservice -n yas-dev --all
kubectl delete authorizationpolicy -n yas-dev --all
kubectl delete pod curl-client-cart curl-client-order -n yas-dev --ignore-not-found
kubectl label namespace yas-dev istio-injection- --overwrite
kubectl rollout restart deployment -n yas-dev
```

Sau rollback, pod se quay ve dang:

```text
<pod-name> 1/1 Running
```
