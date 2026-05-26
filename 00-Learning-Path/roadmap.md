# DevOps Learning Roadmap — Senior Engineer Path

## Phase 1: Foundations Mastery (Week 1)

### Linux
- File system hierarchy, permissions, ACLs
- Process management (systemd, cgroups, namespaces)
- Shell scripting (bash, sed, awk, grep)
- Performance tools: `top`, `htop`, `vmstat`, `iostat`, `strace`, `perf`
- Kernel tuning: `/proc`, `/sys`, sysctl
- Networking: `ss`, `netstat`, `tcpdump`, `iptables`, `nftables`

### Networking
- OSI model deep dive
- TCP/IP, UDP, HTTP/2, HTTP/3, gRPC
- DNS resolution, zones, records
- Load balancing algorithms
- TLS/SSL, mTLS, certificate management
- VPNs, VXLANs, SDN concepts

### Git
- Internals (objects, DAG, plumbing vs porcelain)
- Branching strategies: Git Flow, trunk-based, GitHub Flow
- Rebase, cherry-pick, bisect, reflog
- Monorepo strategies
- Git hooks, signed commits

---

## Phase 2: Containers & Orchestration (Weeks 2-3)

### Docker
- Image layers, Union FS, copy-on-write
- Multi-stage builds, BuildKit
- Networking modes: bridge, host, overlay
- Volume management
- Docker Compose v3+ features
- Security: rootless, seccomp, AppArmor

### Kubernetes
- Architecture: etcd, API server, scheduler, controller-manager, kubelet
- Workloads: Deployment, StatefulSet, DaemonSet, Job, CronJob
- Networking: Services (ClusterIP/NodePort/LoadBalancer), Ingress, NetworkPolicy
- Storage: PV, PVC, StorageClass, CSI
- RBAC, ServiceAccounts, PSA
- HPA, VPA, KEDA autoscaling
- Helm, Kustomize
- Advanced: operators, CRDs, admission webhooks
- Service meshes: Istio, Linkerd

---

## Phase 3: CI/CD & GitOps (Week 4)

### CI/CD Pipelines
- Jenkins: Declarative pipelines, shared libraries, agents
- GitHub Actions: workflows, reusable actions, matrix builds
- GitLab CI: runners, stages, artifacts, caching
- Tekton, CircleCI (concepts)

### GitOps
- ArgoCD: app of apps, sync policies, RBAC
- Flux CD: Kustomize controller, Helm controller
- Pull vs push model
- Drift detection & reconciliation

---

## Phase 4: Infrastructure as Code (Week 5)

### Terraform
- HCL syntax, providers, modules
- State management: remote backends, locking
- Workspaces, environments
- Terraform Cloud / Enterprise
- Testing: Terratest, `terraform validate`, `tflint`
- Advanced: dynamic blocks, meta-arguments, depends_on, lifecycle

### Ansible
- Playbooks, roles, inventories
- Modules, filters, lookups
- Ansible Vault
- Dynamic inventory
- AWX / Ansible Tower
- Testing: Molecule

### Pulumi (Concepts)
- Infrastructure as real code (Python, TypeScript, Go)
- Comparison with Terraform

---

## Phase 5: Cloud Platforms (Week 6, Part 1)

### AWS (Primary Focus)
- **Compute:** EC2, ECS, EKS, Lambda, Fargate
- **Networking:** VPC, subnets, Route53, ELB/ALB/NLB, CloudFront, Transit Gateway, Direct Connect
- **Storage:** S3, EBS, EFS, Glacier
- **Databases:** RDS, Aurora, DynamoDB, ElastiCache, Redshift
- **Security:** IAM, SCP, GuardDuty, SecurityHub, KMS, Secrets Manager
- **Monitoring:** CloudWatch, CloudTrail, X-Ray
- **IaC:** CloudFormation, CDK
- **Cost Optimization:** Reserved instances, Savings Plans, Spot

### GCP / Azure (Conceptual)
- GKE, Cloud Run, Anthos
- Azure AKS, Azure DevOps, ARM templates

---

## Phase 6: Monitoring & Observability (Week 6, Part 2)

### Pillars of Observability
- Metrics, Logs, Traces, Events

### Tools
- **Prometheus:** PromQL, federation, alerting rules, recording rules
- **Grafana:** dashboards, datasources, alerting
- **ELK Stack:** Elasticsearch, Logstash, Kibana, Beats
- **Loki + Promtail** (log aggregation)
- **Jaeger / Zipkin / Tempo** (distributed tracing)
- **OpenTelemetry** (unified instrumentation standard)

---

## Phase 7: Security & Compliance (Week 7, Part 1)

### DevSecOps
- Shift-left security philosophy
- SAST tools: SonarQube, Semgrep, Bandit
- DAST tools: OWASP ZAP, Burp Suite
- SCA: Snyk, Dependabot, Trivy
- Container scanning: Trivy, Clair, Twistlock
- Secrets management: HashiCorp Vault, AWS Secrets Manager
- SBOM generation: Syft, CycloneDX
- OPA/Gatekeeper (policy as code)
- Compliance: SOC 2, PCI-DSS, ISO 27001 concepts

---

## Phase 8: SRE Practices (Week 7, Part 2)

### Site Reliability Engineering
- SLI, SLO, SLA definitions and examples
- Error budgets and burn rates
- Toil measurement and elimination
- Incident management lifecycle
- Postmortem culture (blameless)
- Chaos engineering: Chaos Monkey, LitmusChaos
- Capacity planning
- On-call practices

---

## Phase 9: Projects + Interview Prep (Week 8)

- Build all 6 projects end-to-end
- Practice system design questions daily
- Mock interviews (behavioral + technical)
- Review common failure scenarios and how you solved them

---

## Key Certifications to Target

| Cert | Level | Priority |
|------|-------|---------|
| CKA (Certified Kubernetes Administrator) | Advanced | ⭐⭐⭐⭐⭐ |
| CKAD (Certified Kubernetes App Developer) | Advanced | ⭐⭐⭐⭐ |
| CKS (Certified Kubernetes Security) | Expert | ⭐⭐⭐⭐ |
| AWS Solutions Architect Professional | Advanced | ⭐⭐⭐⭐⭐ |
| Terraform Associate | Mid | ⭐⭐⭐ |
| AWS DevOps Professional | Advanced | ⭐⭐⭐⭐ |

---

## Salary Benchmarks (2025-2026, US Market)

| Role | Range |
|------|-------|
| Senior DevOps Engineer (5-8 yr) | $150K–$200K |
| Staff DevOps/Platform Engineer (8-12 yr) | $190K–$250K |
| SRE (Senior) | $175K–$230K |
| DevSecOps Engineer (Senior) | $160K–$220K |
| Principal DevOps/Infra | $220K–$300K+ |
