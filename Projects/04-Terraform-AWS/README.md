# Project 4: AWS Infrastructure with Terraform

## Overview
Provision production AWS infrastructure with Terraform modules: VPC (3-tier), EKS cluster, Aurora Serverless v2, ElastiCache Redis, S3 + CloudFront, KMS, IAM/IRSA. Remote state with S3 + DynamoDB. Automated CI pipeline posts plans as PR comments and requires approval before applying.

**Skills**: Terraform modules, remote state, Aurora Serverless, IRSA, VPC Endpoints, tfsec/Checkov, OIDC-based CI auth

---

## Directory Structure

```
04-Terraform-AWS/
├── bootstrap/
│   └── state-backend.sh
├── modules/
│   ├── vpc/
│   ├── eks/
│   ├── rds-aurora/
│   ├── elasticache/
│   └── s3-cloudfront/
├── environments/
│   ├── dev/
│   └── production/
└── .github/workflows/
    └── terraform.yml
```

---

## Architecture Overview

```
Internet
   ↓
CloudFront + WAF
   ↓
ALB  (public subnet — 3 AZs)
   ↓
EKS Worker Nodes  (private subnet — 3 AZs)
   ↓                          ↓
Aurora PostgreSQL        ElastiCache Redis
(database subnet)        (database subnet)
   ↓
S3 (via VPC Gateway Endpoint — free, bypasses NAT)

AWS Services accessed privately via VPC Interface Endpoints:
  ECR, SSM, CloudWatch Logs, STS, Secrets Manager
```

---

## Key Design Decisions

### Why Modules + Environment Directories (Not Workspaces)

Terraform Workspaces share state file infrastructure and are easy to misconfigure — a CI job selecting the wrong workspace applies changes to production. Instead:

- Each environment (`dev/`, `production/`) is a separate directory with its own `backend` config pointing to a different S3 key and DynamoDB table
- Modules are shared but consumed independently per environment
- A pipeline targeting `environments/production/` can never accidentally touch `dev` state

### Remote State Backend

Before any `terraform init`, run `bootstrap/state-backend.sh` once to create:
- An S3 bucket with versioning enabled, AES-256 encryption, and all public access blocked
- A DynamoDB table with `LockID` as the partition key for state locking

If a `terraform apply` is interrupted mid-way and leaves a stale lock, use `terraform force-unlock LOCK_ID` — but verify no other apply is actually running first.

### VPC Three-Tier Layout

| Tier | CIDR Range | Contains | Internet Access |
|------|-----------|---------|----------------|
| Public | 10.0.0-2.0/24 | NAT Gateway, ALB | Direct via IGW |
| Private | 10.0.10-12.0/24 | EKS nodes, pods | Via NAT Gateway |
| Database | 10.0.20-22.0/24 | Aurora, Redis | None |

**NAT Gateway count:**
- Production: one per AZ (3 total) — zone failure does not kill egress for other zones
- Dev/Staging: single NAT Gateway — saves ~$65/month per environment

**VPC Endpoints save significant money:**

| Endpoint | Type | Cost | Benefit |
|---------|------|------|---------|
| S3 | Gateway | Free | ECR image layers bypass NAT — eliminates ~$70/month at scale |
| ECR API + Docker | Interface | ~$14/month | Private registry pulls |
| SSM | Interface | ~$14/month | Session Manager replaces bastion |
| CloudWatch Logs | Interface | ~$14/month | Pod logs without NAT cost |

### EKS Node Group Strategy

Two managed node groups:

**General pool (on-demand)**
- Instance: `m6i.xlarge`
- Min 3, Max 15
- Used for: system components, stateful workloads, anything that can't tolerate interruption
- No taints

**Spot pool**
- Instance types: `m6i.xlarge`, `m5.xlarge`, `m5a.xlarge` (diversified for availability)
- Min 0, Max 30 (scales from zero)
- Taint: `spot=true:NoSchedule` — only workloads that explicitly tolerate spot run here
- Used for: CI runners, batch jobs, stateless burst capacity
- Savings: 60-90% compared to on-demand

**Cluster Autoscaler** watches for pending pods and scales the appropriate node group up. Scales down after 10 minutes of underutilization (configurable).

### IRSA — IAM Roles for Service Accounts

No static AWS credentials on EKS pods. Instead:

1. EKS creates an OIDC identity provider (URL tied to the cluster)
2. Terraform creates an IAM role whose trust policy restricts assumption to a specific `namespace:serviceaccount` pair via the cluster's OIDC URL
3. The Kubernetes ServiceAccount is annotated with the IAM role ARN
4. When the pod starts, the projected token is mounted; the AWS SDK exchanges it for STS credentials automatically
5. Credentials are short-lived (1 hour) and scoped to exactly the permissions defined in the IAM policy

No key rotation needed. No credentials to leak.

### Aurora Serverless v2

| Mode | Always-on cost | Scales? | Failover |
|------|---------------|---------|---------|
| RDS db.t3.medium | ~$50/month | Manual, downtime | 60-120 seconds |
| Aurora Provisioned | ~$150/month | Read replicas | < 30 seconds |
| Aurora Serverless v2 | 0.5 ACU min = ~$4/month idle | Automatic, sub-second | < 30 seconds |

Configuration:
- `min_capacity = 2.0` ACU for production (approx 2 vCPU, 4 GB RAM floor)
- `max_capacity = 64.0` ACU burst without pre-provisioning
- `manage_master_user_password = true` — Secrets Manager handles credential rotation automatically
- `deletion_protection = true` in production — prevents accidental `terraform destroy`
- `backup_retention_period = 30` days — full PITR (Point-in-Time Recovery)

---

## CI/CD Pipeline

### Authentication: OIDC (No Static AWS Keys)

GitHub Actions uses OIDC federation to assume an IAM role. The IAM trust policy is scoped to:
- Specific GitHub organization and repository
- `refs/heads/main` branch only (for apply)
- Any branch (for plan-only)

Zero long-lived credentials stored in GitHub Secrets — only the AWS Account ID is needed.

### Pipeline Flow

**On every pull request:**
1. `terraform fmt -check -recursive` — fail if any file is unformatted
2. `terraform validate` — syntax and schema check
3. `tfsec` — fail on HIGH or CRITICAL security findings
4. `checkov` — fail on misconfigurations (open security groups, unencrypted resources)
5. `terraform plan -out=tfplan` — generate plan
6. Post the full plan output as a PR comment (humans review exact changes)

**After merge to main (with required reviewer approval):**
7. GitHub Environment gate — named reviewers must approve
8. `terraform apply tfplan` — apply the exact plan that was reviewed
9. Slack notification with summary of changes applied

### Security Checks That Block CI

| Check | Tool | Example Finding |
|-------|------|----------------|
| No encryption at rest | tfsec | S3 bucket without SSE enabled |
| Public S3 bucket | Checkov | `block_public_acls = false` |
| Open security group | tfsec | Ingress `0.0.0.0/0` on port 22 |
| Unversioned S3 | Checkov | State bucket without versioning |
| No CloudTrail | Checkov | Account without audit logging |
| RDS no deletion protection | tfsec | Production DB missing protection |

---

## Cost Optimization Built In

| Resource | Optimization | Estimated Saving |
|----------|-------------|-----------------|
| EKS nodes | 30-50% Spot for stateless workloads | $200-400/month |
| Aurora | Serverless v2 (scales to low ACU at night) | $100-200/month |
| NAT Gateway | VPC endpoints for S3/ECR remove bulk of NAT data charges | $50-150/month |
| Dev environment | Single NAT Gateway vs 3 | $130/month |
| S3 data | Intelligent-Tiering lifecycle policy | $30-100/month |

**Infracost** can be added to the CI pipeline to post estimated monthly cost impact of each PR as a comment alongside the Terraform plan.

---

## Learning Outcomes

- [ ] Bootstrap a Terraform remote state backend from scratch with proper security
- [ ] Write Terraform modules with variables, outputs, and locals
- [ ] Know when to use `for_each` vs `count` (and why `count` breaks on list changes)
- [ ] Configure IRSA end-to-end — understand the token exchange flow
- [ ] Implement `lifecycle` blocks: `prevent_destroy`, `ignore_changes`, `create_before_destroy`
- [ ] Understand the difference between `depends_on` (explicit) vs reference-based (implicit) dependencies
- [ ] Run tfsec and Checkov and interpret findings against AWS security benchmarks
- [ ] Set up OIDC-based auth from GitHub Actions to AWS — no static credentials

## Interview Talking Points

> "I structure Terraform as reusable modules consumed by per-environment directories rather than workspaces — workspaces share the same code path and a misselected workspace in CI can cause production changes. State is stored in S3 with versioning and DynamoDB locking; if state is ever corrupted I restore from S3 version history. The CI pipeline uses OIDC federation — GitHub's runner proves its identity to AWS via a signed JWT, which STS exchanges for temporary credentials scoped to the role's permissions. No long-lived keys anywhere. Every PR gets an automated plan posted as a comment with tfsec and Checkov findings, so the reviewer sees both the infrastructure impact and any security regressions before approving."
