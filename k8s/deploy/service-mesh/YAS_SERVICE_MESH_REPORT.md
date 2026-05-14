# Bao cao cau hinh Service Mesh cho YAS namespace

## 1. Muc tieu

Bao cao nay mo ta qua trinh cau hinh Istio Service Mesh cho ung dung YAS trong
namespace `yas`, bao gom:

- Bat sidecar injection cho cac workload trong namespace `yas`.
- Ap dung mTLS o che do `STRICT`.
- Cau hinh DestinationRule voi `ISTIO_MUTUAL` cho cac service YAS.
- Cau hinh retry policy cho service `product`.
- Kiem thu service-to-service authorization voi `AuthorizationPolicy`.
- Kiem thu bang `curl` tu cac pod nam trong mesh.
- Chuan bi bang chung phu hop de quan sat tren Kiali topology.

Namespace `service-mesh` truoc do chi duoc dung nhu moi truong lab. Sau khi da
chuyen sang cau hinh that cho namespace `yas`, namespace lab nay da duoc xoa de
giai phong tai nguyen cho minikube.

## 2. Pham vi ap dung

Namespace dich:

```bash
yas
```

Nhung backend YAS dang chay va duoc dua vao mesh:

- `backoffice-bff`
- `cart`
- `customer`
- `inventory`
- `media`
- `order`
- `product`
- `promotion`
- `recommendation`
- `sampledata`
- `storefront-bff`

Mot so deployment hien co nhung scale `0/0`, khong tao pod tai thoi diem test:

- `backoffice-ui`
- `storefront-ui`
- `swagger-ui`
- `webhook`
- `yas-reloader`

## 3. Cac file cau hinh da tao

Tat ca file cau hinh rieng cho namespace `yas` duoc dat tai:

```text
k8s/deploy/service-mesh/
```

Danh sach file:

- `yas-mesh-core.yaml`
- `product-retry-yas.yaml`
- `product-retry-fault-test-yas.yaml`
- `product-cart-only-authorizationpolicy-yas.yaml`
- `curl-client-cart-yas.yaml`
- `curl-client-order-yas.yaml`
- `test-yas-service-mesh.sh`
- `retry-demo-flaky-app-yas.yaml`
- `retry-demo-virtualservice-yas.yaml`
- `test-retry-demo-yas.sh`

### 3.1. `yas-mesh-core.yaml`

File nay la cau hinh loi cua service mesh cho namespace `yas`.

Thanh phan chinh:

- `PeerAuthentication/default` trong namespace `yas`.
- mTLS mode: `STRICT`.
- `DestinationRule` cho moi service YAS.
- TLS mode trong moi `DestinationRule`: `ISTIO_MUTUAL`.

Muc dich:

- Ep workload trong namespace `yas` chi chap nhan traffic mTLS.
- Dam bao client trong mesh su dung mutual TLS khi goi cac service noi bo.
- Tao nen nen tang de Envoy sidecar co the gan identity va enforce policy.

Vi du cau hinh mTLS:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: yas
spec:
  mtls:
    mode: STRICT
```

Vi du DestinationRule:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: product-mtls
  namespace: yas
spec:
  host: product.yas.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

### 3.2. `product-retry-yas.yaml`

File nay cau hinh `VirtualService` cho service `product`.

Chinh sach retry:

- `attempts: 3`
- `perTryTimeout: 2s`
- `retryOn: 5xx,connect-failure,refused-stream,gateway-error,reset`

Muc dich:

- De Envoy sidecar thuc hien retry khi request den `product` gap loi tam thoi.
- Khong can sua code ung dung.
- Chinh sach retry nam o tang service mesh.

Vi du:

```yaml
retries:
  attempts: 3
  perTryTimeout: 2s
  retryOn: 5xx,connect-failure,refused-stream,gateway-error,reset
```

### 3.3. `product-retry-fault-test-yas.yaml`

File nay dung cho kich ban test nang cao ve retry bang fault injection.

Khac voi file retry binh thuong, file nay chen loi gia lap:

```yaml
fault:
  abort:
    httpStatus: 500
    percentage:
      value: 50
```

Muc dich:

- Tao 50% response loi `500` cho endpoint `/product/v3/api-docs`.
- Kiem tra Envoy retry co tac dong len request hay khong.
- Dung trong giai do demo/test, khong nen giu trong moi truong chay binh thuong.

### 3.4. `product-cart-only-authorizationpolicy-yas.yaml`

File nay cau hinh `AuthorizationPolicy` cho service `product`.

Muc tieu policy:

- Cho phep service account `cart` goi `product`.
- Chan service account `order` goi `product`.

Policy su dung principal:

```text
cluster.local/ns/yas/sa/cart
```

Dieu nay co nghia la source identity duoc lay tu Kubernetes service account,
khong phai ten pod hay IP.

Ket qua mong doi:

```text
cart -> product: 200
order -> product: 403
```

Luu y: Policy nay duoc apply trong luc test va bi xoa lai sau test de tranh lam
anh huong hanh vi ung dung.

### 3.5. `curl-client-cart-yas.yaml` va `curl-client-order-yas.yaml`

Hai file nay tao pod curl client trong namespace `yas`.

- `curl-client-cart` chay voi service account `cart`.
- `curl-client-order` chay voi service account `order`.

Muc dich:

- Tao request tu dung identity trong mesh.
- Kiem tra duoc AuthorizationPolicy theo service account.
- Kiem tra duoc mTLS vi pod curl cung duoc inject `istio-proxy`.

Do minikube gioi han CPU, pod test curl duoc gan annotation de giam resource
request cua sidecar:

```yaml
annotations:
  sidecar.istio.io/proxyCPU: 10m
  sidecar.istio.io/proxyMemory: 32Mi
  sidecar.istio.io/proxyCPULimit: 250m
  sidecar.istio.io/proxyMemoryLimit: 256Mi
```

Neu khong giam resource nay, pod test co the bi `Pending` voi loi:

```text
0/1 nodes are available: 1 Insufficient cpu.
```

### 3.6. `test-yas-service-mesh.sh`

Script nay la kich ban test tong hop cho namespace `yas`.

Script kiem tra:

- Rollout cua cac deployment dang chay.
- Trang thai pod va Istio config.
- Tat ca pod backend co sidecar `istio-proxy`.
- Readiness cua tung service thong qua curl client trong mesh.
- Plaintext request tu namespace khong nam trong mesh bi chan boi STRICT mTLS.
- Retry baseline den service `product`.
- AuthorizationPolicy `cart` duoc phep, `order` bi chan.

Lenh chay:

```bash
k8s/deploy/service-mesh/test-yas-service-mesh.sh
```

### 3.7. Retry demo files

De chung minh retry khi upstream tra loi `500`, bo file retry demo duoc them rieng,
khong dung truc tiep service `product` that:

- `retry-demo-flaky-app-yas.yaml`
- `retry-demo-virtualservice-yas.yaml`
- `test-retry-demo-yas.sh`

`retry-demo-flaky-app-yas.yaml` tao service `flaky` gom hai deployment:

- `flaky-good`: luon tra HTTP `200`.
- `flaky-bad`: luon tra HTTP `500`.

Ca hai deployment co label chung `app: flaky`, nen Kubernetes Service `flaky`
load balance request den ca endpoint tot va endpoint loi. Day la cach tao loi
upstream that de test retry, thay vi chi fault injection o client proxy.

`retry-demo-virtualservice-yas.yaml` cau hinh retry:

```yaml
retries:
  attempts: 3
  perTryTimeout: 2s
  retryOn: 5xx,connect-failure,refused-stream,gateway-error,reset
```

`test-retry-demo-yas.sh` se:

1. Deploy `flaky-good`, `flaky-bad`, service `flaky`, va DestinationRule mTLS.
2. Chay 30 request khi chua co retry policy.
3. Apply `VirtualService/flaky-retry`.
4. Chay lai 30 request sau khi co retry policy.
5. In summary so luong HTTP code truoc va sau retry.

## 4. Cac buoc cau hinh

### 4.1. Xoa namespace lab `service-mesh`

Namespace `service-mesh` chi dung de test truoc khi ap dung that cho `yas`.
Sau khi da chuyen sang namespace `yas`, namespace lab duoc xoa:

```bash
kubectl delete namespace service-mesh
```

Expected output:

```text
namespace "service-mesh" deleted
```

Kiem tra lai:

```bash
kubectl get ns service-mesh
```

Expected output:

```text
Error from server (NotFound): namespaces "service-mesh" not found
```

### 4.2. Bat Istio sidecar injection cho namespace `yas`

```bash
kubectl label namespace yas istio-injection=enabled --overwrite
```

Expected output:

```text
namespace/yas labeled
```

### 4.3. Restart deployments de inject sidecar

```bash
kubectl rollout restart deployment -n yas
```

Expected output:

```text
deployment.apps/backoffice-bff restarted
deployment.apps/cart restarted
deployment.apps/customer restarted
deployment.apps/inventory restarted
deployment.apps/media restarted
deployment.apps/order restarted
deployment.apps/product restarted
deployment.apps/promotion restarted
deployment.apps/recommendation restarted
deployment.apps/sampledata restarted
deployment.apps/storefront-bff restarted
```

Sau rollout, pod backend can co dang:

```text
<pod-name>   2/2   Running
```

Vi du output mong doi:

```text
cart-56f79776cc-nhxmc             2/2   Running
customer-cfbc558d-xw2lb           2/2   Running
order-5cdbbbb44c-989l4            2/2   Running
product-6b546d9cb4-sp8lc          2/2   Running
```

### 4.4. Ap dung mTLS va DestinationRule

```bash
kubectl apply -f k8s/deploy/service-mesh/yas-mesh-core.yaml
```

Expected output:

```text
peerauthentication.security.istio.io/default created
destinationrule.networking.istio.io/backoffice-bff-mtls created
destinationrule.networking.istio.io/cart-mtls created
destinationrule.networking.istio.io/customer-mtls created
destinationrule.networking.istio.io/inventory-mtls created
destinationrule.networking.istio.io/media-mtls created
destinationrule.networking.istio.io/order-mtls created
destinationrule.networking.istio.io/product-mtls created
destinationrule.networking.istio.io/promotion-mtls created
destinationrule.networking.istio.io/recommendation-mtls created
destinationrule.networking.istio.io/sampledata-mtls created
destinationrule.networking.istio.io/storefront-bff-mtls created
```

Kiem tra:

```bash
kubectl get peerauthentication,destinationrule -n yas
```

Expected output quan trong:

```text
NAME                                           MODE
peerauthentication.security.istio.io/default   STRICT

NAME                                                      HOST
destinationrule.networking.istio.io/cart-mtls             cart.yas.svc.cluster.local
destinationrule.networking.istio.io/customer-mtls         customer.yas.svc.cluster.local
destinationrule.networking.istio.io/order-mtls            order.yas.svc.cluster.local
destinationrule.networking.istio.io/product-mtls          product.yas.svc.cluster.local
```

### 4.5. Ap dung retry policy cho `product`

```bash
kubectl apply -f k8s/deploy/service-mesh/product-retry-yas.yaml
```

Expected output:

```text
virtualservice.networking.istio.io/product-retry created
```

Kiem tra:

```bash
kubectl get virtualservice -n yas
```

Expected output:

```text
NAME            GATEWAYS   HOSTS
product-retry              ["product","product.yas.svc.cluster.local"]
```

## 5. Chien thuat test

### 5.1. Test 1: Kiem tra sidecar injection

Muc tieu:

- Dam bao moi workload backend dang chay trong `yas` co container `istio-proxy`.
- Xac nhan namespace da thuc su vao mesh.

Lenh:

```bash
kubectl get pods -n yas
```

Expected output:

```text
backoffice-bff-...   2/2   Running
cart-...             2/2   Running
customer-...         2/2   Running
inventory-...        2/2   Running
media-...            2/2   Running
order-...            2/2   Running
product-...          2/2   Running
promotion-...        2/2   Running
recommendation-...   2/2   Running
sampledata-...       2/2   Running
storefront-bff-...   2/2   Running
```

Trong script, logic test se fail neu pod backend nao khong co `istio-proxy`.

Expected script output:

```text
All running YAS backend pods have istio-proxy sidecars.
```

### 5.2. Test 2: Kiem tra readiness qua mesh

Muc tieu:

- Tao request tu `curl-client-cart`, mot pod nam trong mesh.
- Goi endpoint readiness cua tung backend qua service DNS noi bo.
- Dam bao mesh khong lam hong traffic noi bo.

Lenh mau:

```bash
kubectl exec -n yas curl-client-cart -c curl -- \
  curl -sS -o /dev/null -w "%{http_code}" \
  http://product.yas.svc.cluster.local:8090/actuator/health/readiness
```

Expected output:

```text
200
```

Output thuc te tu script:

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
```

Ket luan:

- Cac service trong mesh van giao tiep thanh cong.
- mTLS khong chan traffic hop le giua cac workload da inject sidecar.

### 5.3. Test 3: Kiem tra STRICT mTLS chan plaintext

Muc tieu:

- Tao pod curl tam thoi trong namespace `default`.
- Namespace `default` khong co sidecar mesh.
- Goi thang service `product` trong namespace `yas`.
- Neu STRICT mTLS hoat dong dung, request plaintext se that bai.

Lenh:

```bash
kubectl run curl-no-mesh \
  -n default \
  --image=curlimages/curl:8.10.1 \
  --restart=Never \
  --rm -i \
  --command -- sh -c \
  "curl -sS --max-time 5 http://product.yas.svc.cluster.local:8090/actuator/health/readiness"
```

Expected behavior:

- Lenh khong tra ve thanh cong.
- Request bi chan do workload dich yeu cau mTLS.

Expected script output:

```text
Expected: plaintext request from non-mesh pod failed under STRICT mTLS.
```

Ket luan:

- `PeerAuthentication STRICT` dang co hieu luc.
- Traffic ngoai mesh khong the noi plaintext den workload trong `yas`.

### 5.4. Test 4: Kiem tra retry baseline cho `product`

Muc tieu:

- Xac nhan `VirtualService/product-retry` khong lam hong traffic binh thuong.
- Goi endpoint `/product/v3/api-docs` nhieu lan.
- Tat ca request baseline phai thanh cong.

Lenh mau:

```bash
kubectl exec -n yas curl-client-cart -c curl -- \
  curl -sS -o /dev/null -w "%{http_code}" \
  http://product.yas.svc.cluster.local/product/v3/api-docs
```

Expected output:

```text
200
```

Output thuc te tu script:

```text
product retry baseline 1: 200
product retry baseline 2: 200
product retry baseline 3: 200
product retry baseline 4: 200
product retry baseline 5: 200
```

Ket luan:

- Retry policy da duoc cau hinh.
- Traffic binh thuong toi `product` van thanh cong.
- Retry duoc thuc thi boi Envoy sidecar, khong phu thuoc vao code ung dung.

### 5.4.1. Test retry voi upstream tra loi 500 that

Muc tieu:

- Chung minh Envoy sidecar retry khi upstream service tra HTTP `500`.
- Tao service demo `flaky` co mot endpoint tot va mot endpoint loi.
- So sanh ket qua truoc va sau khi apply `VirtualService` retry.

Lenh chay:

```bash
k8s/deploy/service-mesh/test-retry-demo-yas.sh
```

Ket qua truoc khi apply retry policy:

```text
=== Before retry policy ===
500
500
500
500
200
200
200
200
500
500
500
500
200
200
500
500
500
500
200
200
200
500
500
500
200
500
500
200
500
500
--- Summary before retry ---
200: 11
500: 19
```

Ket qua sau khi apply retry policy:

```text
virtualservice.networking.istio.io/flaky-retry created
=== After retry policy ===
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
200
--- Summary after retry ---
200: 30
```

Ket luan:

- Khi chua co retry policy, request bi load balance vao endpoint loi va co nhieu
  ket qua `500`.
- Sau khi apply `VirtualService` retry, Envoy sidecar retry request bi `500`.
- Trong lan test nay, 30/30 request tra ve `200`.
- Retry khong nam trong code ung dung, ma duoc thuc thi tai tang service mesh.

Sau khi lay evidence, resource demo duoc xoa de tranh ton tai nguyen:

```bash
kubectl delete -f k8s/deploy/service-mesh/retry-demo-virtualservice-yas.yaml --ignore-not-found
kubectl delete -f k8s/deploy/service-mesh/retry-demo-flaky-app-yas.yaml --ignore-not-found
```

### 5.5. Test 5: Kiem tra AuthorizationPolicy

Muc tieu:

- Chung minh policy dua tren service account identity.
- `cart` duoc phep goi `product`.
- `order` bi chan khi goi `product`.

Chuan bi:

```bash
kubectl apply -f k8s/deploy/service-mesh/curl-client-cart-yas.yaml
kubectl apply -f k8s/deploy/service-mesh/curl-client-order-yas.yaml
kubectl apply -f k8s/deploy/service-mesh/product-cart-only-authorizationpolicy-yas.yaml
```

Test allowed path:

```bash
kubectl exec -n yas curl-client-cart -c curl -- \
  curl -sS -o /dev/null -w "cart -> product: %{http_code}\n" \
  http://product.yas.svc.cluster.local/product/v3/api-docs
```

Expected output:

```text
cart -> product: 200
```

Test blocked path:

```bash
kubectl exec -n yas curl-client-order -c curl -- \
  curl -sS -o /dev/null -w "order -> product: %{http_code}\n" \
  http://product.yas.svc.cluster.local/product/v3/api-docs
```

Expected output:

```text
order -> product: 403
```

Output thuc te tu script:

```text
authorizationpolicy.security.istio.io/product-cart-only created
authorizationpolicy.security.istio.io "product-cart-only" deleted from yas namespace
cart -> product: 200
order -> product: 403
```

Ket luan:

- Service account `cart` co identity:

```text
cluster.local/ns/yas/sa/cart
```

- Service account `order` co identity:

```text
cluster.local/ns/yas/sa/order
```

- Policy chi allow principal cua `cart`, nen request tu `order` bi tra ve `403`.

Luu y van hanh:

- Policy nay co tinh demo/test.
- Script se xoa policy sau test:

```bash
kubectl delete -f k8s/deploy/service-mesh/product-cart-only-authorizationpolicy-yas.yaml --ignore-not-found
```

## 6. Ket qua test tong hop

Lenh chay:

```bash
k8s/deploy/service-mesh/test-yas-service-mesh.sh
```

Output quan trong:

```text
deployment "backoffice-bff" successfully rolled out
deployment "cart" successfully rolled out
deployment "customer" successfully rolled out
deployment "inventory" successfully rolled out
deployment "media" successfully rolled out
deployment "order" successfully rolled out
deployment "product" successfully rolled out
deployment "promotion" successfully rolled out
deployment "recommendation" successfully rolled out
deployment "sampledata" successfully rolled out
deployment "storefront-bff" successfully rolled out
All running YAS backend pods have istio-proxy sidecars.
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
Expected: plaintext request from non-mesh pod failed under STRICT mTLS.
product retry baseline 1: 200
product retry baseline 2: 200
product retry baseline 3: 200
product retry baseline 4: 200
product retry baseline 5: 200
cart -> product: 200
order -> product: 403
YAS service mesh tests passed.
```

Ket luan tong hop:

- Namespace `yas` da duoc dua vao Istio service mesh.
- Cac backend dang chay da co sidecar.
- mTLS STRICT hoat dong dung.
- DestinationRule voi `ISTIO_MUTUAL` da duoc ap dung.
- Retry policy cho `product` da duoc ap dung va khong pha traffic binh thuong.
- AuthorizationPolicy hoat dong dung theo service account identity.

## 7. Chien thuat quan sat voi Kiali

Kiali da co trong namespace `istio-system`.

Kiem tra:

```bash
kubectl get pods -n istio-system
kubectl get svc -n istio-system
```

Expected output quan trong:

```text
istiod              Running
kiali               Running
prometheus-server   Running
```

Mo Kiali:

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001
```

Truy cap:

```text
http://localhost:20001
```

Trong Kiali:

- Chon namespace: `yas`.
- Chon Graph.
- Chon graph type: `Versioned app graph`.
- Chon thoi gian: `Last 5m` hoac `Last 10m`.
- Bat hien thi traffic/security neu can.

Tao traffic cho Kiali:

```bash
kubectl exec -n yas curl-client-cart -c curl -- sh -c '
for i in $(seq 1 100); do
  curl -s http://cart/cart/v3/api-docs > /dev/null
  curl -s http://customer/customer/v3/api-docs > /dev/null
  curl -s http://order/order/v3/api-docs > /dev/null
  curl -s http://product/product/v3/api-docs > /dev/null
  sleep 1
done
'
```

Noi dung can mo ta khi chup screenshot Kiali:

- Namespace dang chon la `yas`.
- Cac node ung voi service/app YAS.
- Cac edge the hien traffic giua curl client va backend service.
- Traffic thanh cong co mau/trang thai OK.
- Security indicator the hien traffic nam trong mesh va dung mTLS.

## 8. Van de gap phai va cach xu ly

### 8.1. Minikube thieu CPU sau khi them sidecar

Sau khi bat sidecar injection cho tat ca service, mot so pod bi `Pending`:

```text
0/1 nodes are available: 1 Insufficient cpu.
```

Nguyen nhan:

- Moi workload co them `istio-proxy`.
- Trong rolling update, Kubernetes tam thoi chay pod cu va pod moi song song.
- Minikube chi co mot node nen de cham gioi han CPU.

Cach xu ly:

- Xoa namespace lab `service-mesh` de giai phong tai nguyen.
- Cho rollout tiep tuc sau khi tai nguyen duoc giai phong.
- Giam resource sidecar cho pod curl test bang annotation.

### 8.2. Pod curl test bi Pending

Ban dau `curl-client-order` bi `Pending` do sidecar mac dinh van request CPU cao.

Loi:

```text
0/1 nodes are available: 1 Insufficient cpu.
```

Cach xu ly:

- Them annotation resource cho `curl-client-cart-yas.yaml`.
- Them annotation resource cho `curl-client-order-yas.yaml`.

Ket qua:

- Pod curl client schedule thanh cong.
- Full test pass.

### 8.3. `sampledata` va `storefront-bff` rollout cham

Hai service nay tung bi `ProgressDeadlineExceeded` do pod moi mat thoi gian schedule
va readiness probe co delay.

Sau khi xoa namespace lab va cho them thoi gian, ca hai pod moi deu Ready:

```text
sampledata       1/1
storefront-bff   1/1
```

Pod thuc te trong mesh:

```text
sampledata-...       2/2   Running
storefront-bff-...   2/2   Running
```

## 9. Rollback

Neu can go service mesh khoi namespace `yas`, co the dung cac lenh sau:

```bash
kubectl label namespace yas istio-injection- --overwrite
kubectl delete peerauthentication -n yas default --ignore-not-found
kubectl delete destinationrule -n yas --all
kubectl delete virtualservice -n yas --all
kubectl delete authorizationpolicy -n yas --all
kubectl delete pod curl-client-cart curl-client-order -n yas --ignore-not-found
kubectl rollout restart deployment -n yas
```

Sau rollback, pod se quay ve dang khong co sidecar:

```text
<pod-name>   1/1   Running
```

## 10. Ket luan

Cau hinh Service Mesh da duoc ap dung thanh cong cho namespace `yas`.

Cac yeu cau chinh da dat:

- mTLS STRICT cho namespace `yas`.
- DestinationRule `ISTIO_MUTUAL` cho cac service YAS.
- Sidecar injection cho cac backend dang chay.
- Retry policy cho `product`.
- AuthorizationPolicy demo cho `cart -> product` allow va `order -> product` deny.
- Kich ban test curl tu trong mesh va ngoai mesh.
- Full test script ket thuc voi:

```text
YAS service mesh tests passed.
```
