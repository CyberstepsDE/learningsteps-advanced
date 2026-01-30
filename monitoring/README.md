# Monitoring Stack - Prometheus & Grafana

Prometheus and Grafana monitoring for your FastAPI application running on AKS.

## Quick Start

Run the automated setup script from the project root:

```bash
./monitoring/monitoring-setup.sh
```

This installs:

- **Prometheus** - Metrics collection and storage
- **Grafana** - Visualization and dashboards
- **Alertmanager** - Alert routing and management
- **Node Exporter** - Hardware and OS metrics
- **Kube State Metrics** - Kubernetes object metrics

**Installation time**: 2-3 minutes

## Access Grafana

After installation, access Grafana:

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Then open: http://localhost:3000

**Credentials**:

- Username: `admin`
- Password: `admin`

## Your Application Metrics

Your application is already configured for Prometheus scraping with annotations in [k8s/service.yaml](../k8s/service.yaml):

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/path: "/metrics"
  prometheus.io/port: "8000"
```

Prometheus automatically discovers and scrapes your `/metrics` endpoint every 30 seconds.

---

## Verify Metrics Collection

### Option 1: Check in Prometheus UI

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Open http://localhost:9090 and:

1. Go to **Status → Targets**
2. Look for your service (search "learningsteps")
3. Check if status is **UP** (green)

### Option 2: Query in Grafana

1. In Grafana, click **Explore** (compass icon in left sidebar)
2. Select **Prometheus** as data source
3. Enter query:
   ```promql
   up{namespace="learningsteps"}
   ```
4. Click **Run query**
5. If you see `value=1`, metrics are being collected

---

## Pre-Configured Dashboards

Grafana includes many pre-built Kubernetes dashboards:

1. **Kubernetes / Compute Resources / Cluster** - Cluster-wide metrics
2. **Kubernetes / Compute Resources / Namespace (Pods)** - Namespace metrics
3. **Kubernetes / Compute Resources / Pod** - Individual pod metrics

To access:

1. Click **Dashboards** in left sidebar
2. Browse **General** and **Kubernetes** folders

---

## Create Custom Dashboard

### Example Queries for Your Application

In Grafana, click **+ → Dashboard → Add visualization**, select **Prometheus**, and try these:

**HTTP Request Rate**:

```promql
rate(http_requests_total{namespace="learningsteps"}[5m])
```

**Pod CPU Usage**:

```promql
rate(container_cpu_usage_seconds_total{namespace="learningsteps",pod=~"learningsteps-api.*"}[5m])
```

**Pod Memory Usage**:

```promql
container_memory_working_set_bytes{namespace="learningsteps",pod=~"learningsteps-api.*"}
```

**Response Time (95th percentile)**:

```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{namespace="learningsteps"}[5m]))
```

---

## Troubleshooting

### Metrics Not Showing

Check if service has annotations:

```bash
kubectl get svc learningsteps-api -n learningsteps -o yaml | grep -A 3 annotations
```

Test if metrics endpoint is accessible:

```bash
POD=$(kubectl get pod -n learningsteps -l app=learningsteps-api -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n learningsteps $POD -- curl -s localhost:8000/metrics
```

### Grafana Login Issues

Reset admin password:

```bash
kubectl exec -n monitoring $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') -- grafana-cli admin reset-admin-password newpassword
```

### Check Prometheus Status

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
kubectl logs -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0
```

---

## Optional: External Access

To access Grafana externally (without port-forward):

```bash
kubectl patch svc prometheus-grafana -n monitoring -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc prometheus-grafana -n monitoring
```

Wait for `EXTERNAL-IP`, then access at `http://<EXTERNAL-IP>`.

---

## Cleanup

To remove the monitoring stack:

```bash
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring
```

---

## What's Installed

- **Prometheus**: http://localhost:9090 (port-forward)
- **Grafana**: http://localhost:3000 (port-forward)
- **Alertmanager**: http://localhost:9093 (port-forward with `svc/prometheus-kube-prometheus-alertmanager`)

## Files

```
monitoring/
├── README.md              # This file
└── monitoring-setup.sh    # Installation script
```
