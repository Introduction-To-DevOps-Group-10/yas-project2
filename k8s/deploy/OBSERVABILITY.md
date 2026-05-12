# Observability cho YAS Project 02

Tài liệu này mô tả cách dùng Observability trong project YAS trên Kubernetes. Mục tiêu là deploy được stack Observability, truy cập Grafana, và dùng Grafana để quan sát logs, metrics, traces của các service YAS trong các namespace như `yas`, `yas-dev`, `yas-staging`.

## 1. Thành phần Observability

Stack hiện tại gồm:

- **Grafana**: giao diện chính để xem logs, metrics, traces, dashboard.
- **Prometheus**: thu thập metrics từ Kubernetes và các service YAS.
- **ServiceMonitor**: cấu hình để Prometheus biết scrape metrics từ service nào.
- **Loki**: lưu trữ logs tập trung.
- **Promtail**: đọc log từ pod/container và đẩy vào Loki.
- **Tempo**: lưu distributed traces.
- **OpenTelemetry Collector**: nhận traces từ ứng dụng YAS qua OTLP rồi gửi sang Tempo.

Luồng dữ liệu:

```text
Metrics:
YAS service /actuator/prometheus
  -> ServiceMonitor
  -> Prometheus
  -> Grafana

Logs:
Pod logs
  -> Promtail
  -> Loki
  -> Grafana

Traces:
YAS service
  -> OpenTelemetry Collector
  -> Tempo
  -> Grafana
```

## 2. Cài đặt Observability

Chạy trên node/EC2 có Kubernetes context:

```bash
cd ~/yas-project2/k8s/deploy
./setup-observability.sh
```

Kiểm tra:

```bash
kubectl get pod -n observability
kubectl get svc -n observability
kubectl get ingress -n observability
```

Các pod quan trọng cần `Running`:

```text
prometheus-grafana
prometheus-prometheus-kube-prometheus-prometheus-0
loki
promtail
tempo-0
opentelemetry-collector
```

## 3. Bật metrics cho YAS bằng ServiceMonitor

Mặc định `deploy-yas-applications.sh` không tạo `ServiceMonitor`, để app có thể deploy ngay cả khi chưa cài Observability.

Khi đã cài Observability và muốn Prometheus scrape metrics của YAS:

```bash
cd ~/yas-project2/k8s/deploy
DISABLE_SERVICEMONITOR=false ./deploy-yas-applications.sh
```

Kiểm tra:

```bash
kubectl get servicemonitor -A
```

Nếu thấy `ServiceMonitor` trong namespace `yas`, Prometheus có thể scrape metrics từ các service đó.

## 4. Dùng cho dev và staging

Nếu muốn quan sát namespace `yas-dev` hoặc `yas-staging`, cần đảm bảo:

1. App được deploy vào namespace tương ứng.
2. Chart service có bật `ServiceMonitor`.
3. Promtail đang scrape log namespace đó.
4. Grafana query đúng namespace.

Ví dụ kiểm tra:

```bash
kubectl get pod -n yas-dev
kubectl get servicemonitor -n yas-dev

kubectl get pod -n yas-staging
kubectl get servicemonitor -n yas-staging
```

Trong `promtail.values.yaml`, Promtail đang giữ log từ các namespace:

```text
yas
yas-dev
yas-staging
observability
```

Nếu thêm namespace mới, cần thêm namespace đó vào regex của Promtail rồi upgrade lại:

```bash
helm upgrade --install promtail grafana/promtail \
  --create-namespace --namespace observability \
  --values ./observability/promtail.values.yaml
```

## 5. Truy cập Grafana

Nếu dùng Ingress/hosts:

```text
http://grafana.yas.local.com
```

Tài khoản mặc định:

```text
admin / admin
```

Nếu chưa dùng được domain, port-forward:

```bash
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
```

Mở:

```text
http://localhost:3000
```

## 6. Test Loki logs

Kiểm tra Loki từ trong Grafana pod:

```bash
kubectl exec -n observability deploy/prometheus-grafana -- wget -qO- \
  http://loki-gateway.observability.svc.cluster.local/loki/api/v1/labels
```

Nếu trả JSON có các label như `namespace`, `pod`, `container`, nghĩa là Loki hoạt động.

Trong Grafana:

```text
Explore -> Loki
```

Query rộng:

```logql
{namespace=~".+"}
```

Query YAS:

```logql
{namespace="yas"}
```

Query dev:

```logql
{namespace="yas-dev"}
```

Query staging:

```logql
{namespace="yas-staging"}
```

Query log lỗi:

```logql
{namespace="yas"} |= "error"
```

Query theo container:

```logql
{namespace="yas", container="product"}
```

## 7. Test Prometheus metrics

Trong Grafana:

```text
Explore -> Prometheus
```

Query cơ bản:

```promql
up
```

Query YAS:

```promql
up{namespace="yas"}
```

Query dev/staging:

```promql
up{namespace="yas-dev"}
up{namespace="yas-staging"}
```

Tìm metrics HTTP:

```promql
{__name__=~".*http.*", namespace="yas"}
```

Kiểm tra target trực tiếp trong Prometheus:

```bash
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Mở:

```text
http://localhost:9090/targets
```

Target namespace `yas` nên ở trạng thái `UP`.

## 8. Test Tempo traces

YAS được cấu hình gửi trace tới:

```text
http://opentelemetry-collector.observability:4318/v1/traces
```

Tạo request thử:

```bash
kubectl run curl-test -n yas --rm -it --image=curlimages/curl -- sh
```

Trong pod:

```sh
curl http://product:8090/actuator/health
curl http://cart:8090/actuator/health
curl http://customer:8090/actuator/health
exit
```

Kiểm tra collector:

```bash
kubectl logs -n observability deploy/opentelemetry-collector --tail=100
```

Trong Grafana:

```text
Explore -> Tempo
```

Tìm trace gần đây theo service hoặc thời gian.

## 9. Các tiện ích thực tế hay dùng

### Xem service lỗi nhiều

Prometheus:

```promql
sum(rate(http_server_requests_seconds_count{status=~"5..", namespace="yas"}[5m])) by (application)
```

### Xem request rate

```promql
sum(rate(http_server_requests_seconds_count{namespace="yas"}[5m])) by (application)
```

### Xem logs lỗi trong 1 namespace

Loki:

```logql
{namespace="yas"} |= "ERROR"
```

Hoặc:

```logql
{namespace="yas"} |~ "(?i)error|exception|failed"
```

### Xem log theo pod

```logql
{namespace="yas", pod=~"product.*"}
```

### Debug pod restart

```bash
kubectl get pod -n yas
kubectl describe pod -n yas <pod-name>
kubectl logs -n yas <pod-name> --previous
```

Sau đó đối chiếu log trong Grafana Loki theo `pod`.

### Kiểm tra health actuator

Actuator chạy ở port `8090`:

```bash
kubectl run curl-test -n yas --rm -it --image=curlimages/curl -- sh
```

Trong pod:

```sh
curl http://product:8090/actuator/health
curl http://product:8090/actuator/prometheus | head
exit
```

## 10. Troubleshooting

### Loki không resolve được

Kiểm tra service:

```bash
kubectl get svc -n observability | grep loki
```

Test từ Grafana:

```bash
kubectl exec -n observability deploy/prometheus-grafana -- nslookup loki-gateway.observability.svc.cluster.local
```

### Promtail lỗi too many open files

Tăng limit trên node:

```bash
sudo sysctl -w fs.file-max=2097152
sudo sysctl -w fs.inotify.max_user_watches=1048576
sudo sysctl -w fs.inotify.max_user_instances=1024
sudo sysctl -w fs.inotify.max_queued_events=32768
```

Sau đó restart Promtail:

```bash
kubectl delete pod -n observability -l app.kubernetes.io/name=promtail
```

### Grafana Loki query No data

Thử query rộng:

```logql
{namespace=~".+"}
```

Tăng time range lên:

```text
Last 1 hour
Last 6 hours
```

Kiểm tra Promtail:

```bash
kubectl logs -n observability daemonset/promtail --tail=100
```

### Prometheus không thấy app

Kiểm tra ServiceMonitor:

```bash
kubectl get servicemonitor -A
```

Nếu chưa có, redeploy app:

```bash
DISABLE_SERVICEMONITOR=false ./deploy-yas-applications.sh
```

### Sau khi stop/start EC2

Kiểm tra cluster:

```bash
kubectl get nodes
kubectl get pod -A
```

Nếu dùng Minikube:

```bash
minikube status
minikube start
```

Kiểm tra Observability:

```bash
kubectl get pod -n observability
```

## 11. Checklist demo

Trước khi demo, chụp hoặc kiểm tra:

```bash
kubectl get pod -n observability
kubectl get pod -n yas
kubectl get servicemonitor -A
```

Trong Grafana:

- Loki query: `{namespace="yas"}`
- Prometheus query: `up{namespace="yas"}`
- Tempo datasource connected hoặc có trace gần đây
- Dashboard metrics load được

Nếu các mục trên chạy được, phần Observability đạt yêu cầu deploy và truy cập được.
