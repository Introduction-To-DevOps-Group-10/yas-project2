# Observability cho YAS

Tai lieu nay mo ta cach cai va dung observability toi gian cho YAS tren Kubernetes.
Stack hien tai chi dung:

- Prometheus: thu thap Kubernetes metrics va application metrics.
- Grafana: xem dashboard va query Prometheus.
- ServiceMonitor: khai bao backend service nao duoc Prometheus scrape.

Khong cai Loki, Promtail, Tempo, OpenTelemetry trong phien ban toi gian nay. Neu can logs, dung `kubectl logs`. Neu can traces, co the bo sung sau.
Neu truoc do da cai stack day du, `setup-observability.sh` se uninstall cac release cu trong namespace `observability`: `loki`, `tempo`, `opentelemetry-operator`, `opentelemetry-collector`, `promtail`, `grafana-operator`, va chart `grafana` rieng.

## 1. Luong metrics

```text
Kubernetes node/pod/deployment metrics
  -> kube-prometheus-stack
  -> Prometheus
  -> Grafana

YAS backend /actuator/prometheus
  -> ServiceMonitor
  -> Prometheus
  -> Grafana
```

## 2. Cai Prometheus va Grafana

Chay tren EC2/node co Kubernetes context:

```bash
cd ~/yas-devops/k8s/deploy
chmod +x setup-observability.sh
./setup-observability.sh
```

Kiem tra:

```bash
kubectl get pods -n observability
kubectl get svc -n observability
kubectl get ingress -n observability
```

Nhung workload quan trong can san sang:

```text
deployment/prometheus-grafana
deployment/prometheus-kube-state-metrics
statefulset/prometheus-prometheus-kube-prometheus-prometheus
daemonset/prometheus-prometheus-node-exporter
```

## 3. Truy cap Grafana

Neu dung ingress va file hosts:

```text
http://grafana.yas.local.com
```

Tai khoan lay tu `cluster-config.yaml`:

```text
grafana.username
grafana.password
```

Neu chua dung duoc domain, port-forward:

```bash
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
```

Mo:

```text
http://localhost:3000
```

Neu truy cap tu Windows qua EC2, co the tao SSH tunnel:

```powershell
ssh -i E:\Devops-project-personal\devops.pem -L 3000:localhost:3000 ubuntu@13.215.243.80
```

Sau do tren EC2 chay port-forward o tren, va mo `http://localhost:3000` tren Windows.

## 4. Bat metrics cho staging

Prometheus tu dong co Kubernetes metrics cho namespace `yas-staging`, vi kube-state-metrics va node-exporter da nam trong kube-prometheus-stack.

De co application metrics cua YAS backend, cac values staging trong GitOps can bat:

```yaml
serviceMonitor:
  enabled: true
```

Nen bat cho cac backend chinh:

```text
product
customer
inventory
cart
order
location
media
promotion
rating
recommendation
sampledata
backoffice-bff
storefront-bff
```

Sau khi commit/push GitOps, ArgoCD se sync va tao ServiceMonitor trong namespace `yas-staging`.

Kiem tra:

```bash
kubectl get servicemonitor -n yas-staging
kubectl get endpoints -n yas-staging
```

## 5. Kiem tra Prometheus target

Port-forward Prometheus:

```bash
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Mo:

```text
http://localhost:9090/targets
```

Tim cac target namespace `yas-staging`. Neu target `UP`, Prometheus da scrape duoc metrics.

## 6. Query staging trong Grafana

Vao Grafana:

```text
Explore -> Prometheus
```

Kiem tra target backend:

```promql
up{namespace="yas-staging"}
```

CPU pod staging:

```promql
sum(rate(container_cpu_usage_seconds_total{namespace="yas-staging", container!="", image!=""}[5m])) by (pod)
```

Memory pod staging:

```promql
sum(container_memory_working_set_bytes{namespace="yas-staging", container!="", image!=""}) by (pod)
```

Pod restart:

```promql
sum(kube_pod_container_status_restarts_total{namespace="yas-staging"}) by (pod)
```

Deployment replicas:

```promql
kube_deployment_status_replicas_available{namespace="yas-staging"}
```

Application request rate, neu Spring actuator metrics co san:

```promql
sum(rate(http_server_requests_seconds_count{namespace="yas-staging"}[5m])) by (application)
```

HTTP 5xx rate:

```promql
sum(rate(http_server_requests_seconds_count{namespace="yas-staging", status=~"5.."}[5m])) by (application)
```

Latency trung binh:

```promql
sum(rate(http_server_requests_seconds_sum{namespace="yas-staging"}[5m])) by (application)
/
sum(rate(http_server_requests_seconds_count{namespace="yas-staging"}[5m])) by (application)
```

Neu query HTTP khong co data, kiem tra:

```bash
kubectl get servicemonitor -n yas-staging
kubectl describe servicemonitor -n yas-staging <service-name>
kubectl port-forward -n yas-staging svc/product 8090:8090
curl http://localhost:8090/actuator/prometheus
```

## 7. Dashboard nen co de demo

Trong Grafana, dung dashboard mac dinh cua kube-prometheus-stack de demo Kubernetes:

- Kubernetes / Compute Resources / Namespace / Pods
- Kubernetes / Compute Resources / Node
- Kubernetes / Networking / Namespace

Tao them dashboard rieng cho YAS Staging voi cac panel:

- Pods CPU by pod
- Pods memory by pod
- Pod restart count
- Deployment available replicas
- Backend target up/down
- HTTP request rate
- HTTP 5xx rate
- Average latency

Tat ca panel nen filter namespace:

```text
yas-staging
```

## 8. Cach theo doi staging khi release

Truoc khi chay Jenkins staging release:

```bash
kubectl get pods -n yas-staging
kubectl get applications -n argocd
kubectl get servicemonitor -n yas-staging
```

Trong luc release:

```bash
kubectl get pods -n yas-staging -w
```

Trong Grafana theo doi:

- CPU/memory pod co tang bat thuong khong.
- Pod restart co tang khong.
- Deployment available replicas co ve 0 khong.
- `up{namespace="yas-staging"}` co target nao down khong.
- HTTP 5xx rate co tang khong.

Neu service loi, dung metrics de khoanh vung truoc:

```promql
sum(kube_pod_container_status_restarts_total{namespace="yas-staging"}) by (pod)
```

Sau do moi xem log truc tiep:

```bash
kubectl logs -n yas-staging <pod-name> --tail=100
kubectl describe pod -n yas-staging <pod-name>
```

## 9. Troubleshooting

Prometheus khong thay ServiceMonitor:

```bash
kubectl get servicemonitor -A
kubectl get prometheus -n observability
```

Prometheus target DOWN:

```bash
kubectl describe servicemonitor -n yas-staging <service-name>
kubectl get svc -n yas-staging <service-name> -o yaml
kubectl get endpoints -n yas-staging <service-name>
```

Grafana khong truy cap duoc:

```bash
kubectl get pods -n observability
kubectl get svc -n observability prometheus-grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
```

Khong co HTTP metrics:

```bash
kubectl port-forward -n yas-staging svc/product 8090:8090
curl http://localhost:8090/actuator/prometheus | head
```

Neu endpoint `/actuator/prometheus` khong tra metrics, can kiem tra cau hinh Spring actuator cua service do.
