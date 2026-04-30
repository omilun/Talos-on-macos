# Observability

The cluster ships a full observability stack out of the box — no setup wizard, no manual datasource wiring.
Everything is pre-configured and running after `tofu apply`.

## URLs

| Service | URL | Credentials |
|---|---|---|
| Grafana | https://grafana.talos-tart-ha.talos-on-macos.com | admin / `change-me` |
| Prometheus | https://prometheus.talos-tart-ha.talos-on-macos.com | — |
| Alertmanager | https://alertmanager.talos-tart-ha.talos-on-macos.com | — |

> Grafana password is set in `gitops/infrastructure/monitoring/`. Change it by updating the HelmRelease values.

---

## Grafana

Grafana is pre-loaded with dashboards for every component in the stack.

### Pre-installed dashboards

| Dashboard | What it shows |
|---|---|
| **Kubernetes / Nodes** | CPU, memory, disk, network per node |
| **Kubernetes / Pods** | Resource usage per pod, restarts, OOMKills |
| **Kubernetes / Namespaces** | Aggregate resource usage per namespace |
| **Flux** | Reconciliation status, errors, lag |
| **Loki** | Log volume by namespace/pod |
| **Cilium** | Drop rates, policy verdicts, endpoint health |
| **CoreDNS** | Query rate, errors, cache hits |
| **cert-manager** | Certificate expiry, renewal events |
| **Tempo** | Trace ingest rate, span counts, service map |

### Changing the admin password

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

To change it permanently, update the HelmRelease values in `gitops/infrastructure/monitoring/`.

### Adding a custom dashboard

Drop a ConfigMap with the label `grafana_dashboard: "1"` into any namespace:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  my-dashboard.json: |
    { ... Grafana dashboard JSON ... }
```

Grafana's sidecar auto-discovers it within ~30 seconds.

### Adding a datasource for your app

Grafana already has Prometheus and Loki as datasources.
To add your own (e.g. a Redis exporter), create a `GrafanaDatasource` CR or add a ConfigMap
with label `grafana_datasource: "1"`.

---

## Prometheus

Prometheus scrapes metrics from every component automatically via `ServiceMonitor` and `PodMonitor` CRDs.

### Key pre-configured scrape targets

```bash
# See all active targets
open https://prometheus.talos-tart-ha.talos-on-macos.com/targets
```

| Target | Metrics |
|---|---|
| kube-state-metrics | Deployment/Pod/Node object state |
| node-exporter | Host CPU, memory, disk, network |
| kubelet / cAdvisor | Container resource usage |
| Cilium agent | eBPF network metrics |
| CoreDNS | DNS query metrics |
| Flux controllers | Reconciliation duration, errors |
| Argo Workflows | Workflow/step counts |
| Zot | Registry push/pull rates |

### Querying metrics

Open Prometheus → **Graph** tab. Example queries:

```promql
# Pod CPU usage (cores)
rate(container_cpu_usage_seconds_total{namespace="pulse"}[5m])

# Memory per pod
container_memory_working_set_bytes{namespace="pulse"}

# Flux reconciliation errors
gotk_reconcile_condition{type="Ready",status="False"}

# HTTP request rate to pulse API
rate(http_requests_total{namespace="pulse"}[1m])
```

### Adding a ServiceMonitor for your app

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: my-app
  labels:
    release: kube-prometheus-stack   # must match the Prometheus selector
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
```

Prometheus picks it up automatically — no restart needed.

---

## Alertmanager

Alertmanager receives firing alerts from Prometheus and routes them.

### Default alerts

The `kube-prometheus-stack` ships ~80 pre-configured alerts covering:
- Node pressure (CPU, memory, disk)
- Pod crash-looping, OOMKilled, pending
- PVC almost full
- Kubernetes control-plane health
- cert-manager certificate expiry

```bash
# See all active alerts
open https://alertmanager.talos-tart-ha.talos-on-macos.com
```

### Configuring a receiver (Slack, email, PagerDuty)

Add a `PrometheusRule` or patch the Alertmanager config via the HelmRelease values in
`gitops/infrastructure/monitoring/`:

```yaml
alertmanager:
  config:
    receivers:
      - name: slack
        slack_configs:
          - api_url: https://hooks.slack.com/services/...
            channel: '#alerts'
    route:
      receiver: slack
```

---

## Loki

Loki aggregates logs from every pod in the cluster via Promtail.
Logs are queryable in Grafana using **LogQL**.

### Querying logs in Grafana

1. Open Grafana → **Explore** → select **Loki** datasource
2. Use the label browser or type LogQL directly

### Useful LogQL queries

```logql
# All logs from the pulse namespace
{namespace="pulse"}

# Logs from a specific pod
{namespace="pulse", pod=~"auth-service.*"}

# Error logs only
{namespace="argo"} |= "error"

# Flux reconciliation errors
{namespace="flux-system"} |= "error"

# BuildKit build logs
{namespace="buildkit"} | json

# Argo Workflows step logs
{namespace="argo", container="main"} |= "failed"
```

### Log retention

Loki stores logs on local PVC. Default retention: 24h (configurable in the Loki HelmRelease values).
For longer retention, increase the PVC size and set `limits_config.retention_period`.

---

## Distributed Tracing (Tempo + OTel)

The cluster ships [Grafana Tempo](https://grafana.com/oss/tempo/) and the [OpenTelemetry Operator](https://opentelemetry.io/docs/kubernetes/operator/) out of the box. Applications instrumented with OTel SDKs send traces to the in-cluster OTel Collector, which forwards them to Tempo and stores them for 48 hours.

### Architecture

```
App (OTel SDK)
  └── OTel Collector (opentelemetry ns)     ← gRPC :4317 / HTTP :4318
        ├── → Tempo (traces, 48h retention)
        ├── → Prometheus (metrics via remote write)
        └── → Loki (logs via OTLP HTTP)
```

### Querying traces in Grafana

1. Open Grafana → **Explore** → select **Tempo** datasource
2. Search by service name, trace ID, or span attributes
3. Click a trace to see the full span waterfall with timing and attributes

### Connecting your app

Set these environment variables on your pods:

| Variable | Value |
|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `otel-collector-collector.<namespace>.svc.cluster.local:4317` (gRPC, no `http://`) |
| `OTEL_SERVICE_NAME` | your service name (shows up in Tempo's service map) |

For HTTP (e.g. Next.js), use port `4318` with `http://` prefix.

> **Note:** The OTel Operator creates a service named `{cr-name}-collector`. With the default CR name `otel-collector`, the service is `otel-collector-collector` in the `opentelemetry` namespace.

---

## Hubble UI

Hubble is Cilium's network observability layer. It shows live network flows between pods,
policy verdicts (allowed/dropped), and DNS queries.

> The Hubble UI is not exposed via an HTTPRoute in this cluster. Use the CLI below or run
> `kubectl port-forward -n kube-system svc/hubble-ui 8080:80` to access the UI locally.

### CLI

```bash
# Stream live flows from your Mac
hubble observe --namespace pulse --follow

# Show dropped flows
hubble observe --verdict DROPPED

# Show flows to a specific pod
hubble observe --to-pod pulse/auth-service-xxx
```

> Requires `hubble` CLI: `brew install hubble`
