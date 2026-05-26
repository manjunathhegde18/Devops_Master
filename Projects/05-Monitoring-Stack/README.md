# Project 5: Full Observability Stack

## Overview
Deploy a production observability stack: Prometheus + Grafana + Loki + Tempo + Alertmanager + PagerDuty integration. Covers metrics, logs, traces, and SLO dashboards for a sample application.

**Skills**: Prometheus, Grafana, Loki, Tempo, Alertmanager, OpenTelemetry, SLO dashboards, on-call routing

---

## Architecture
```
Applications (instrumented with OTel SDK)
    │
    ├── Metrics ──► OTel Collector ──► Prometheus ──► Grafana
    │
    ├── Logs ────► Promtail/Fluent Bit ──► Loki ──► Grafana
    │
    └── Traces ──► OTel Collector ──► Tempo ──► Grafana

Grafana (single pane of glass):
  Metrics dashboards (Prometheus)
  Log explorer (Loki)
  Trace viewer (Tempo)
  SLO dashboards + burn rate
  Alerting → Alertmanager → PagerDuty + Slack
```

---

## Project Structure
```
05-Monitoring-Stack/
├── docker-compose.yml
├── prometheus/
│   ├── prometheus.yml
│   └── rules/
│       ├── api-alerts.yml
│       └── infra-alerts.yml
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yaml
│   │   └── dashboards/
│   │       └── dashboards.yaml
│   └── dashboards/
│       ├── api-overview.json
│       ├── slo-dashboard.json
│       └── infra.json
├── alertmanager/
│   └── alertmanager.yml
├── loki/
│   └── loki-config.yaml
├── tempo/
│   └── tempo-config.yaml
├── otel-collector/
│   └── otel-collector-config.yaml
├── sample-app/
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
└── scripts/
    ├── generate-load.sh
    └── test-alerting.sh
```

---

## Step 1: Stack with Docker Compose

```yaml
services:

  # ── Prometheus ──────────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:v2.51.0
    restart: unless-stopped
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=15d"
      - "--storage.tsdb.retention.size=10GB"
      - "--web.enable-lifecycle"
      - "--web.enable-admin-api"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/rules:/etc/prometheus/rules:ro
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    networks: [monitoring]

  # ── Alertmanager ────────────────────────────────────────────────
  alertmanager:
    image: prom/alertmanager:v0.27.0
    restart: unless-stopped
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"
      - "--cluster.listen-address="     # disable clustering for single instance
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertmanager-data:/alertmanager
    ports:
      - "9093:9093"
    networks: [monitoring]

  # ── Grafana ─────────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:10.4.0
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana_password
      GF_FEATURE_TOGGLES_ENABLE: "traceToMetrics"
      GF_AUTH_ANONYMOUS_ENABLED: "false"
      GF_SMTP_ENABLED: "true"
      GF_INSTALL_PLUGINS: "grafana-piechart-panel,grafana-worldmap-panel"
    secrets:
      - grafana_password
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
      - grafana-data:/var/lib/grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
      - loki
      - tempo
    networks: [monitoring]

  # ── Loki ────────────────────────────────────────────────────────
  loki:
    image: grafana/loki:2.9.5
    restart: unless-stopped
    command: -config.file=/etc/loki/loki-config.yaml
    volumes:
      - ./loki/loki-config.yaml:/etc/loki/loki-config.yaml:ro
      - loki-data:/loki
    ports:
      - "3100:3100"
    networks: [monitoring]

  # ── Tempo ───────────────────────────────────────────────────────
  tempo:
    image: grafana/tempo:2.4.0
    restart: unless-stopped
    command: -config.file=/etc/tempo/tempo-config.yaml
    volumes:
      - ./tempo/tempo-config.yaml:/etc/tempo/tempo-config.yaml:ro
      - tempo-data:/var/tempo
    ports:
      - "3200:3200"
      - "4317:4317"   # OTLP gRPC
    networks: [monitoring]

  # ── OpenTelemetry Collector ─────────────────────────────────────
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.98.0
    restart: unless-stopped
    command: ["--config=/etc/otelcol/otel-collector-config.yaml"]
    volumes:
      - ./otel-collector/otel-collector-config.yaml:/etc/otelcol/otel-collector-config.yaml:ro
    ports:
      - "4318:4318"   # OTLP HTTP
    depends_on: [tempo, prometheus]
    networks: [monitoring, app-net]

  # ── Sample Instrumented App ─────────────────────────────────────
  sample-app:
    build: ./sample-app
    restart: unless-stopped
    environment:
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4318
      OTEL_SERVICE_NAME: sample-api
      OTEL_RESOURCE_ATTRIBUTES: "environment=development,team=platform"
    networks: [monitoring, app-net]
    ports:
      - "8080:8080"

secrets:
  grafana_password:
    file: ./secrets/grafana_password.txt

volumes:
  prometheus-data:
  alertmanager-data:
  grafana-data:
  loki-data:
  tempo-data:

networks:
  monitoring:
    driver: bridge
  app-net:
    driver: bridge
```

---

## Step 2: Prometheus Configuration

**prometheus/prometheus.yml**
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: "local-dev"
    environment: "development"

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: sample-app
    static_configs:
      - targets: ["sample-app:8080"]
    metrics_path: /metrics

  # Discover all running Docker containers with prometheus.scrape=true label
  - job_name: docker-services
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
    relabel_configs:
      - source_labels: [__meta_docker_container_label_prometheus_scrape]
        action: keep
        regex: "true"
      - source_labels: [__meta_docker_container_label_prometheus_port]
        target_label: __address__
        replacement: "${1}:${2}"
      - source_labels: [__meta_docker_container_name]
        target_label: container
```

---

## Step 3: Alert Rules

**prometheus/rules/api-alerts.yml**
```yaml
groups:
  - name: api-slo-alerts
    interval: 30s
    rules:

      - alert: APIHighErrorRate
        expr: |
          sum(rate(http_server_requests_total{status=~"5.."}[5m])) /
          sum(rate(http_server_requests_total[5m])) * 100 > 5
        for: 2m
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "API error rate above 5% for 2 minutes"
          description: "Current error rate: {{ printf \"%.2f\" $value }}%"
          runbook: "https://runbooks.company.com/api-high-error-rate"

      - alert: APIHighLatencyP99
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_server_request_duration_seconds_bucket[5m])) by (le, handler)
          ) > 2.0
        for: 5m
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "P99 latency above 2s on handler {{ $labels.handler }}"
          description: "P99 latency is {{ printf \"%.2f\" $value }}s"

      - alert: SLOFastBurnRate
        expr: |
          (
            sum(rate(http_server_requests_total{status=~"5.."}[1h])) /
            sum(rate(http_server_requests_total[1h]))
          ) > (14.4 * 0.001)
        for: 2m
        labels:
          severity: critical
          page: "true"
        annotations:
          summary: "SLO error budget burning 14x faster than normal"
          description: "Will exhaust monthly budget in < 2 hours at current rate"

  - name: infrastructure-alerts
    rules:

      - alert: NodeMemoryPressure
        expr: |
          (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Host {{ $labels.instance }} memory above 85%"

      - alert: DiskWillFillIn4Hours
        expr: |
          predict_linear(node_filesystem_free_bytes{fstype!~"tmpfs|devtmpfs"}[2h], 4 * 3600) < 0
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Disk on {{ $labels.instance }} predicted to fill in 4 hours"

      - alert: ContainerOOMKilled
        expr: |
          increase(container_oom_events_total[5m]) > 0
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.container }} was OOMKilled"
```

---

## Step 4: Alertmanager Routing

**alertmanager/alertmanager.yml**
```yaml
global:
  resolve_timeout: 5m

templates:
  - "/etc/alertmanager/templates/*.tmpl"

route:
  receiver: default-slack
  group_by: [alertname, cluster, service]
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    - matchers:
        - severity = critical
        - page = true
      receiver: pagerduty-critical
      continue: true

    - matchers:
        - severity = critical
      receiver: slack-critical

    - matchers:
        - severity = warning
      receiver: slack-warnings

inhibit_rules:
  - source_matchers:
      - severity = critical
    target_matchers:
      - severity = warning
    equal: [alertname, cluster]

receivers:
  - name: default-slack
    slack_configs:
      - api_url: "${SLACK_WEBHOOK_URL}"
        channel: "#alerts-info"
        title: "{{ .GroupLabels.alertname }}"
        text: "{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}"
        send_resolved: true

  - name: slack-critical
    slack_configs:
      - api_url: "${SLACK_WEBHOOK_URL}"
        channel: "#alerts-critical"
        send_resolved: true

  - name: slack-warnings
    slack_configs:
      - api_url: "${SLACK_WEBHOOK_URL}"
        channel: "#alerts-warnings"

  - name: pagerduty-critical
    pagerduty_configs:
      - routing_key: "${PAGERDUTY_ROUTING_KEY}"
        description: "{{ .CommonAnnotations.summary }}"
        details:
          runbook: "{{ .CommonAnnotations.runbook }}"
          environment: "{{ .CommonLabels.environment }}"
```

---

## Step 5: Grafana Datasource Provisioning

**grafana/provisioning/datasources/datasources.yaml**
```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    url: http://prometheus:9090
    isDefault: true
    editable: false

  - name: Loki
    type: loki
    uid: loki
    url: http://loki:3100
    editable: false
    jsonData:
      derivedFields:
        - datasourceUid: tempo
          matcherRegex: '"trace_id":"(\w+)"'
          name: TraceID
          url: "$${__value.raw}"

  - name: Tempo
    type: tempo
    uid: tempo
    url: http://tempo:3200
    editable: false
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki
      serviceMap:
        datasourceUid: prometheus
```

---

## Step 6: Sample Instrumented Python App

**sample-app/main.py** — shows how to instrument an app with OpenTelemetry
```python
import time
import random
from fastapi import FastAPI, Request
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# Initialize tracing
tracer_provider = TracerProvider()
tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(tracer_provider)

# Initialize metrics
reader = PeriodicExportingMetricReader(OTLPMetricExporter(), export_interval_millis=5000)
meter_provider = MeterProvider(metric_readers=[reader])
metrics.set_meter_provider(meter_provider)

app = FastAPI(title="Instrumented Sample API")
FastAPIInstrumentor.instrument_app(app)

tracer = trace.get_tracer("sample-api")
meter = metrics.get_meter("sample-api")

# Custom business metrics
orders_counter = meter.create_counter("orders_created_total", description="Total orders created")
order_value_histogram = meter.create_histogram("order_value_dollars", description="Order value in dollars")

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.post("/api/orders")
async def create_order(request: Request):
    with tracer.start_as_current_span("create-order") as span:
        order_value = random.uniform(10, 500)
        
        span.set_attribute("order.value", order_value)
        span.set_attribute("user.id", "user-123")

        # Simulate DB write
        with tracer.start_as_current_span("db-write"):
            time.sleep(random.uniform(0.01, 0.05))

        # Record business metrics
        orders_counter.add(1, {"status": "success"})
        order_value_histogram.record(order_value)

        return {"order_id": f"ord-{int(time.time())}", "value": order_value}

@app.get("/api/orders/{order_id}")
async def get_order(order_id: str):
    # Simulate occasional errors for SLO testing
    if random.random() < 0.02:
        raise Exception("Database timeout")

    with tracer.start_as_current_span("db-read") as span:
        span.set_attribute("order.id", order_id)
        time.sleep(random.uniform(0.005, 0.02))

    return {"order_id": order_id, "status": "shipped"}
```

---

## Step 7: Load Generator

**scripts/generate-load.sh**
```bash
#!/usr/bin/env bash
BASE_URL="${1:-http://localhost:8080}"
RPS="${2:-10}"
DURATION="${3:-300}"

echo "Generating ${RPS} req/s against $BASE_URL for ${DURATION}s..."

end_time=$(($(date +%s) + DURATION))
while [[ $(date +%s) -lt $end_time ]]; do
    for i in $(seq 1 "$RPS"); do
        # Mix of endpoints
        case $((RANDOM % 3)) in
            0) curl -sf -X POST "$BASE_URL/api/orders" -H "Content-Type: application/json" \
                    -d '{"item":"widget","qty":1}' -o /dev/null &;;
            1) curl -sf "$BASE_URL/api/orders/ord-$(date +%s)" -o /dev/null &;;
            2) curl -sf "$BASE_URL/health" -o /dev/null &;;
        esac
    done
    sleep 1
done
wait
echo "Load test complete."
```

---

## What to Observe After Running This Project

1. Open Grafana at http://localhost:3000
2. Check the API Overview dashboard — see RED metrics (Rate, Errors, Duration)
3. Run the load generator: `./scripts/generate-load.sh http://localhost:8080 20 120`
4. Watch the P99 latency rise and requests counter increase in real time
5. Check Loki for logs: `{service="sample-api"} |= "ERROR"`
6. Open Tempo and trace a single slow request end-to-end
7. Check the SLO dashboard — watch the error budget burn rate

---

## Learning Outcomes
- [ ] Deploy the full Prometheus + Grafana + Loki + Tempo stack
- [ ] Write PromQL queries for the four golden signals
- [ ] Create custom alert rules with burn rate
- [ ] Configure Alertmanager routing to Slack and PagerDuty
- [ ] Instrument an application with OpenTelemetry
- [ ] Correlate traces ↔ logs ↔ metrics in Grafana
- [ ] Interpret error budget consumption on an SLO dashboard
