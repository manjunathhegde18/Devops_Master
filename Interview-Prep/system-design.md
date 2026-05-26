# System Design for DevOps/Infrastructure Interviews

## How to Approach Any System Design Question

### The 4-Phase Framework
```
Phase 1 — Clarify (5 min)
  Ask scope questions before drawing anything:
  - Scale: How many users? RPS? Data size? Regions?
  - Availability: SLO target? 99.9% or 99.99%?
  - Team: How big? Skill set? On-call model?
  - Constraints: Budget? Existing stack? Migration vs greenfield?
  
Phase 2 — High-Level Design (10 min)
  Whiteboard top-down architecture:
  DNS → CDN → Load Balancer → Services → Data → Monitoring
  
Phase 3 — Deep Dive (20 min)
  Interviewer will focus on 1-2 areas — go deep there
  Show tradeoffs: why X over Y?
  
Phase 4 — Evolution (5 min)
  What would you change at 10x, 100x scale?
  Where would you invest first?
```

---

## Design 1: Production CI/CD Platform for 200 Engineers

### Clarify
- Team size: 200 engineers, 50+ microservices
- Deployment frequency target: 50+ deploys/day
- Current state: manual, Jenkins on-prem
- Requirements: self-service, secure, fast feedback

### High-Level Architecture
```
Developer pushes to Git
        ↓
GitHub / GitLab (source control)
        ↓
CI Platform (GitHub Actions or GitLab CI)
  ├── Lint + Test (parallel, per-service)
  ├── Security scanning (SAST, SCA, container scan)
  ├── Build + Push to registry
  └── Trigger CD
        ↓
ArgoCD (GitOps CD layer)
  ├── Staging sync (automatic, on merge to develop)
  ├── Production sync (manual approval or scheduled)
  └── Drift detection + auto-remediation
        ↓
Kubernetes clusters (staging + production, multi-AZ)
        ↓
Monitoring + Alerting → Slack + PagerDuty
```

### Key Design Decisions

**Why ArgoCD over push-based CD?**
- Pull model: cluster pulls from Git, no need to grant CI outbound access to K8s
- Git is the single source of truth — every cluster state is auditable
- Drift detection: if someone `kubectl apply` directly, ArgoCD detects and corrects
- Multi-cluster support: one ArgoCD instance managing many clusters

**Scaling CI runners**
- GitHub Actions self-hosted runners on K8s (ARC — Actions Runner Controller)
- Runners auto-scale based on queue depth
- Spot instances for cost (stateless, OK to be interrupted)
- Caching strategy: Docker layer cache in ECR, pip/npm cache in S3

**Deployment strategies per risk level**
- Internal tools: Direct rolling update
- Customer-facing: Canary → 5% → 25% → 100% with automated rollback on error rate
- DB migrations: Feature flags + backwards-compatible migrations first, code second

**Security gates**
- Every build: SAST, SCA, container scan — fail on CRITICAL
- Image signing: Cosign with OIDC, Kyverno enforces at admission
- Secrets: Never in CI env vars — pull from Vault/Secrets Manager

---

## Design 2: Multi-Region Kubernetes Platform

### Clarify
- Active-active or active-passive across regions?
- RTO/RPO requirements?
- Stateful workloads?
- Data residency requirements (GDPR)?

### Architecture
```
                   Route53 (Latency-based routing)
                       /              \
              us-east-1               eu-west-1
            EKS Cluster             EKS Cluster
           (primary region)       (secondary region)
                  │                       │
        RDS Aurora              RDS Aurora
        (write endpoint)   ←── (read replica, promoted if needed)
                  │
          Global shared: 
            S3 + CRR (cross-region replication)
            ECR (replicated)
            Route53 health checks
```

### Single-Region vs Multi-Region Decision Tree
```
Traffic regional distribution matters?  → Multi-region latency-routing
Compliance (GDPR, data sovereignty)?    → Multi-region required
99.99%+ SLO required?                  → Multi-region or multi-AZ + fast failover
Team < 20 engineers?                   → Multi-AZ is enough, multi-region is operationally complex
Cost budget limited?                   → Multi-AZ with DR plan
```

### Key Tradeoffs
- **Active-Active**: Higher complexity, data consistency challenges (distributed writes), higher cost, true zero-downtime failover
- **Active-Passive (warm standby)**: Simpler, some downtime during failover (minutes), RDS Aurora failover < 30s

---

## Design 3: Observability Platform for 100+ Services

### Scale Requirements
- 100 services, each emitting metrics, logs, traces
- ~50,000 metrics/min ingestion rate
- Log volume: 50GB/day
- Trace sampling: 1% of requests with 100% of errors

### Architecture
```
Applications (OTel SDK)
        ↓
OTel Collector (DaemonSet) — receives, filters, batches
    ├── Metrics → Prometheus → Thanos (long-term, S3-backed)
    ├── Logs → Fluent Bit → Loki (index-free, S3-backed)
    └── Traces → Tempo (S3-backed)
        ↓
Grafana (single pane of glass)
  - Unified dashboards
  - Log ↔ Trace ↔ Metric correlation
  - SLO dashboards with burn rate

Alerting:
Prometheus rules → Alertmanager → PagerDuty + Slack
Grafana alerts for business metrics
```

### Key Decisions

**Why Thanos over just Prometheus?**
- Prometheus stores data locally — limited retention, no HA
- Thanos: S3 object storage → unlimited retention at low cost
- Query federation across multiple Prometheus instances
- Global view across clusters from single query endpoint

**Why Loki over Elasticsearch?**
- Loki indexes only labels, not full text → 10-30x cheaper storage
- At 50GB/day: Elasticsearch ~$500/mo vs Loki ~$50/mo
- Tradeoff: Full-text regex search slower vs indexed Elasticsearch
- Acceptable when logs are well-structured JSON with good labels

**Cardinality control**
- High-cardinality labels (user_id, request_id) belong in traces/logs, NOT metrics
- Recording rules for frequently-queried heavy expressions
- Drop irrelevant metrics at collector level (reduce by 40-60%)

---

## Design 4: Zero-Downtime Deployment Strategy

### Question
"How would you design deployment pipelines for an e-commerce site that cannot tolerate downtime?"

### Strategy Matrix
```
Risk Level | Strategy           | Rollback Time | Notes
──────────────────────────────────────────────────────────────
Low risk   | Rolling Update     | 5-10 min      | maxUnavailable: 0
Medium     | Blue-Green         | < 1 min       | Switch LB target group
High       | Canary             | < 1 min       | Automated on error rate spike
DB changes | Expand-Contract    | N/A           | Multi-step: add → migrate → remove
Hotfix     | Feature Flag off   | Seconds       | Kill switch without deploy
```

### Canary Deployment Flow
```
v1 (100%) running in production
      ↓ Deploy v2 to canary (5% traffic via weighted routing)
      ↓ Monitor for 10 minutes:
        - Error rate < baseline + 0.5%
        - P99 latency < baseline + 50ms
      ↓ Pass → promote to 25% → 50% → 100%
      ↓ Fail → automatic rollback to 100% v1 (< 60 seconds)
```

### Database Migration Pattern (Expand-Contract)
```
Problem: ALTER TABLE on 100M row table = 30min lock = unacceptable downtime

Solution — 3 phases:
  Phase 1 (Expand):
    - Add new column (nullable, no constraint)
    - Deploy code that writes to BOTH old and new column
    - Backfill old rows in batches (pt-online-schema-change or gh-ost)
    
  Phase 2 (Migrate):
    - Deploy code that reads from new column, writes to both
    - Add NOT NULL constraint after backfill complete
    
  Phase 3 (Contract):
    - Deploy code that only uses new column
    - Drop old column
    
Each phase: separate deployment, verified working before next
```

---

## Design 5: Secrets Management at Scale

### Question
"Design a secrets management system for 50 services across 3 environments."

### Architecture
```
HashiCorp Vault (HA — 3 nodes + Raft storage)
    │
    ├── Auth: Kubernetes OIDC per cluster
    ├── Auth: AWS IAM for EC2/Lambda
    ├── Auth: AppRole for CI systems
    │
    ├── KV v2: Static secrets (API keys, certs)
    ├── Database: Dynamic credentials for each service
    │       └── Postgres short-lived creds (TTL: 1hr)
    └── PKI: Internal TLS certificates
    
Access pattern (K8s):
  ServiceAccount → OIDC token → Vault token → read secret
  Vault Agent sidecar → file injection into pod
  OR: External Secrets Operator → K8s Secret (encrypted etcd)
  
Access pattern (CI/CD):
  GitHub Actions → OIDC → Vault AppRole → secret at runtime
  Never stored in GitHub env vars
```

### Key Principles
1. **Never store secrets in Git, CI config, or container images**
2. **Use dynamic secrets over static** — auto-expiring DB creds eliminate revocation problem
3. **Least privilege per service** — each service gets its own Vault policy
4. **Audit everything** — every secret read logged with service identity
5. **Auto-rotation** — static secrets rotate automatically via Vault leases
6. **Break-glass** — emergency access procedure: logged, time-limited, requires two approvals

---

## Common Design Anti-Patterns to Avoid

| Anti-Pattern | Why it's Bad | Better Approach |
|-------------|-------------|----------------|
| Single region, single AZ | SPOF | Multi-AZ minimum |
| Static long-lived credentials | Can't be rotated if leaked | Dynamic secrets / IRSA |
| All-in-one monolith CI/CD | Blast radius too large | Per-team or per-service pipelines |
| No deployment strategy | Downtime on every deploy | Rolling/Canary/Blue-Green |
| Manual on-call, no runbooks | Slow MTTR, burnout | Automated + runbooks for every alert |
| Monitoring as afterthought | Flying blind | Instrument before ship |
| Push-only deployments to K8s | No drift detection | GitOps with ArgoCD/Flux |
