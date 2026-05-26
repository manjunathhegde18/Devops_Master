# Project 1: Production CI/CD Pipeline from Scratch

## Overview
Build a fully automated CI/CD pipeline for a Python FastAPI microservice using GitHub Actions. Covers: lint → test → security scan → docker build → push to registry → deploy to Kubernetes.

**Skills**: GitHub Actions, Docker, Trivy, SonarCloud, Helm, Kubernetes, Slack notifications

---

## Architecture
```
Developer pushes code
        ↓
GitHub Actions Trigger
        ↓
┌─────────────────────────────────┐
│  1. Lint (flake8, black, mypy)  │
│  2. Unit Tests (pytest + cov)   │
│  3. SAST (Semgrep)              │
│  4. Build Docker Image          │
│  5. Security Scan (Trivy)       │
│  6. Push to GHCR                │
│  7. Deploy to Staging (Helm)    │
│  8. Smoke Tests                 │
│  9. Manual Gate                 │
│  10. Deploy to Production       │
│  11. Slack Notification         │
└─────────────────────────────────┘
```

---

## Project Structure
```
01-CICD-Pipeline/
├── app/
│   ├── main.py
│   ├── routers/
│   │   └── items.py
│   ├── models.py
│   └── tests/
│       ├── test_main.py
│       └── test_items.py
├── Dockerfile
├── docker-compose.yml
├── helm/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values.staging.yaml
│   ├── values.production.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       └── hpa.yaml
├── .github/
│   └── workflows/
│       ├── ci.yml
│       ├── cd-staging.yml
│       └── cd-production.yml
└── scripts/
    └── smoke-test.sh
```

---

## Step 1: The FastAPI Application

**app/main.py**
```python
from fastapi import FastAPI
from app.routers import items

app = FastAPI(title="Items API", version="1.0.0")
app.include_router(items.router, prefix="/api/v1")

@app.get("/health")
async def health_check():
    return {"status": "healthy", "version": "1.0.0"}

@app.get("/ready")
async def readiness_check():
    return {"status": "ready"}
```

**app/tests/test_main.py**
```python
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_readiness():
    response = client.get("/ready")
    assert response.status_code == 200
```

---

## Step 2: Dockerfile (Multi-Stage, Production-Grade)

```dockerfile
# syntax=docker/dockerfile:1.7
FROM python:3.12-slim AS deps

WORKDIR /app
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --user --no-cache-dir -r requirements.txt

FROM python:3.12-slim AS production

RUN useradd -r -u 1001 -g 0 appuser && \
    mkdir -p /app && chown appuser:root /app

WORKDIR /app
COPY --from=deps /root/.local /root/.local
COPY --chown=appuser:root app/ ./app/

ENV PATH=/root/.local/bin:$PATH
USER 1001

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "4"]
```

---

## Step 3: GitHub Actions — CI Workflow

**.github/workflows/ci.yml**
```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  PYTHON_VERSION: "3.12"
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  lint-and-test:
    name: Lint & Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
          cache: pip

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-cov flake8 black mypy semgrep

      - name: Lint (flake8)
        run: flake8 app/ --max-line-length=100

      - name: Format check (black)
        run: black --check app/

      - name: Type check (mypy)
        run: mypy app/ --ignore-missing-imports

      - name: Run tests with coverage
        run: |
          pytest app/tests/ \
            --cov=app \
            --cov-report=xml \
            --cov-report=term-missing \
            --junitxml=test-results.xml

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          file: coverage.xml
          fail_ci_if_error: true

      - name: SAST with Semgrep
        run: semgrep scan --config=auto --error app/

  build-and-scan:
    name: Build & Security Scan
    needs: lint-and-test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      security-events: write

    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=sha-
            type=ref,event=branch
            type=semver,pattern={{version}}

      - name: Build image
        uses: docker/build-push-action@v5
        with:
          context: .
          target: production
          push: false
          load: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Scan with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}
          format: sarif
          output: trivy-results.sarif
          severity: HIGH,CRITICAL
          exit-code: 1

      - name: Upload Trivy SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-results.sarif

      - name: Push image
        if: github.ref == 'refs/heads/main'
        uses: docker/build-push-action@v5
        with:
          context: .
          target: production
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## Step 4: Helm Chart

**helm/values.yaml**
```yaml
replicaCount: 2

image:
  repository: ghcr.io/myorg/items-api
  tag: latest
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: true
  className: nginx
  host: api.example.com
  tls: true

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
```

---

## Step 5: Smoke Test Script

**scripts/smoke-test.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-staging}"
BASE_URL="${2:-https://api-staging.example.com}"
MAX_RETRIES=10
RETRY_INTERVAL=15

echo "Running smoke tests against $ENV ($BASE_URL)..."

wait_for_ready() {
    for i in $(seq 1 $MAX_RETRIES); do
        STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "$BASE_URL/health" || echo "000")
        if [[ "$STATUS" == "200" ]]; then
            echo "Service is healthy after $i attempts"
            return 0
        fi
        echo "Attempt $i/$MAX_RETRIES: Status $STATUS — waiting ${RETRY_INTERVAL}s..."
        sleep $RETRY_INTERVAL
    done
    echo "Service did not become healthy in time!"
    return 1
}

wait_for_ready

# Test health endpoint
RESPONSE=$(curl -sf "$BASE_URL/health")
echo "$RESPONSE" | grep -q '"status":"healthy"' || { echo "Health check failed"; exit 1; }

# Test API endpoint
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/items")
[[ "$HTTP_CODE" == "200" ]] || { echo "Items API returned $HTTP_CODE"; exit 1; }

echo "All smoke tests passed for $ENV!"
```

---

## Learning Goals After This Project
- [ ] Understand GitHub Actions workflow triggers and jobs
- [ ] Know how to cache Docker layers and pip dependencies in CI
- [ ] Understand how to fail CI on security vulnerabilities
- [ ] Be able to explain why multi-stage Dockerfiles matter
- [ ] Configure Helm values per environment
- [ ] Write a basic smoke test script

---

## Interview Talking Points
> "I built an end-to-end CI/CD pipeline using GitHub Actions. The pipeline enforces quality gates at each stage: linting and type checking on every commit, unit tests with coverage thresholds, SAST scanning with Semgrep, container scanning with Trivy that fails the build on CRITICAL CVEs. The pipeline uses multi-stage Docker builds with BuildKit layer caching, reducing build times from 8 minutes to under 2 minutes. Deployments use Helm with environment-specific values, and every production deployment requires a manual approval gate and passes smoke tests before completing."
