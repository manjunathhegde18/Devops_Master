# Kubernetes — Interview Questions & Answers (Senior Level)

---

## Architecture & Internals

**Q1: Walk through what happens when you run `kubectl apply -f deployment.yaml`.**

Step-by-step:
1. kubectl serializes YAML and sends HTTP request to kube-apiserver
2. API server authenticates (certificate, bearer token, OIDC), authorizes (RBAC check)
3. Mutating admission webhooks run first (inject sidecars, set defaults)
4. Object schema validation runs
5. Validating admission webhooks run (OPA/Gatekeeper, PSA)
6. Object persisted to etcd, response returned
7. Deployment controller watches etcd events, detects new/changed Deployment
8. Creates/patches ReplicaSet to match desired state
9. ReplicaSet controller creates Pod objects (no node assigned yet)
10. Scheduler watches for unscheduled Pods, runs filtering + scoring, binds Pod to Node
11. kubelet on selected node watches for bound Pods
12. kubelet calls containerd via CRI, which calls runc to create container
13. kubelet monitors probes, reports status back to API server

---

**Q2: Explain etcd's role. What happens if etcd goes down?**

etcd is the distributed key-value store — the single source of truth for all cluster state. It uses the Raft consensus algorithm, requiring a quorum (majority) of members to function.

- If etcd goes down: no new resources can be created or updated; existing workloads continue running (kubelet operates independently), but cannot be rescheduled on failure
- For HA, run 3 or 5 etcd members (tolerates 1 or 2 failures respectively)
- Backup etcd daily: `etcdctl snapshot save`
- Encrypt etcd at rest using `EncryptionConfiguration`

---

**Q3: What is the difference between liveness, readiness, and startup probes?**

| Probe | Question | On Failure | Use Case |
|-------|----------|-----------|---------|
| Readiness | Is pod ready for traffic? | Removed from Service endpoints | App initializing, DB migrations, circuit breaker open |
| Liveness | Is pod still alive? | Pod killed + restarted | Deadlock, hung goroutine, unrecoverable state |
| Startup | Has app finished starting? | Pod killed (if failureThreshold exceeded) | Slow-starting apps, prevents premature liveness kills |

**Critical:** Always configure `startupProbe` for apps with variable startup time. Without it, liveness probe kills the pod before it finishes initializing.

---

**Q4: A pod is stuck in Pending. Walk through your diagnosis.**

```
kubectl describe pod <name> -n <ns>
```

Events section reveals the root cause:

| Event Message | Root Cause | Fix |
|---------------|-----------|-----|
| Insufficient CPU/memory | Requests exceed node capacity | Reduce requests, add nodes |
| No nodes match nodeSelector | Label mismatch | Check node labels |
| Taint effect NoSchedule | Missing toleration | Add toleration |
| Unbound PersistentVolumeClaim | StorageClass issue, no provisioner | Check StorageClass, PVC events |
| Too many pods | Node at pod limit (110 default) | Scale cluster |

---

**Q5: What is CrashLoopBackOff? How do you systematically debug it?**

Container repeatedly starts and crashes. Kubernetes adds exponential backoff delay.

Debug steps:
1. `kubectl logs <pod> --previous` — get last crash logs
2. `kubectl describe pod` — check `Last State` exit code
3. Common exit codes:
   - `1` — application error (check logs)
   - `137` — OOMKilled (increase memory limit)
   - `139` — segfault
   - `143` — graceful shutdown timed out
4. `kubectl exec` when running briefly — check if config/secrets mounted
5. Override entrypoint to debug: `command: ["sleep", "infinity"]`

---

## Networking

**Q6: How does pod-to-pod networking work across nodes?**

Kubernetes networking contract: every pod has a unique routable IP, no NAT between pods.

CNI plugin implements this:
- **Flannel**: VXLAN overlay — encapsulates packets in UDP, sends to destination node's VTEP, decapsulates
- **Calico**: BGP — advertises pod CIDRs as routes between nodes; no encapsulation = lower overhead; also enforces NetworkPolicy via iptables
- **Cilium**: eBPF-based — replaces iptables entirely, kernel-level enforcement, observability via Hubble

---

**Q7: Explain ClusterIP, NodePort, LoadBalancer, and Ingress differences.**

- **ClusterIP**: Virtual IP inside cluster only. kube-proxy writes iptables/IPVS rules to DNAT to pod IPs
- **NodePort**: Opens same port on every node (30000-32767). External traffic → any NodeIP:port → ClusterIP → pod
- **LoadBalancer**: Cloud-provisioned external LB (ELB, GCP LB). Routes → NodePort internally
- **Ingress**: L7 HTTP routing. Single external IP/LB, routes by Host header and URL path to different Services. Requires an Ingress Controller (NGINX, Traefik, AWS ALB Ingress)

---

**Q8: How do NetworkPolicies work? What is default behavior?**

By default: all pod-to-pod communication is allowed (no isolation).

Once any NetworkPolicy selects a pod, that pod is isolated — only explicitly allowed traffic passes.

```yaml
# Deny all ingress to app pods, only allow from frontend on port 8080
spec:
  podSelector:
    matchLabels:
      role: backend
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: frontend
      ports:
        - port: 8080
```

**Important**: NetworkPolicy is enforced by the CNI plugin. Flannel does NOT enforce it. Use Calico, Cilium, or Weave.

---

## Scheduling & Resources

**Q9: Explain Kubernetes QoS classes and their eviction order.**

| Class | Condition | Evicted First? |
|-------|-----------|---------------|
| BestEffort | No requests or limits set | Yes — first killed under pressure |
| Burstable | Requests set but not equal to limits | Middle |
| Guaranteed | Requests == Limits for every container | Last (never evicted for other pods) |

For production pods: aim for Guaranteed QoS. At minimum, always set resource requests.

---

**Q10: What are taints and tolerations?**

Taints prevent pods from being scheduled on nodes. Tolerations allow pods to schedule on tainted nodes.

```yaml
# Taint a node (dedicated GPU node)
kubectl taint nodes gpu-node-1 gpu=true:NoSchedule

# Pod must tolerate to be scheduled here
tolerations:
  - key: gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
```

Effects:
- `NoSchedule` — don't schedule new pods without toleration
- `PreferNoSchedule` — try to avoid, not enforced
- `NoExecute` — evict existing pods that don't tolerate + don't schedule new ones

Common use: dedicated nodes for monitoring, GPU nodes, spot/preemptible nodes.

---

**Q11: Explain node affinity vs pod affinity vs pod anti-affinity.**

- **nodeAffinity**: Schedule pods on nodes with specific labels (replace nodeSelector with expressions)
- **podAffinity**: Schedule pod on same node/zone as other pods with matching labels (co-location, e.g., cache near app)
- **podAntiAffinity**: Schedule pod away from other pods (spread replicas across nodes/zones for HA)

```yaml
# Spread replicas — never two on same node
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: myapp
        topologyKey: kubernetes.io/hostname
```

---

## Advanced Topics

**Q12: What is a Kubernetes Operator pattern?**

Extends Kubernetes with domain-specific operational knowledge using:
- CRD (Custom Resource Definition) — defines new API types
- Controller — watches CRDs + reconciles actual vs desired state

Example: `PostgresCluster` CRD → Operator handles: provisioning, HA setup, failover, backup scheduling, version upgrades, connection pooling config.

Real operators: Strimzi (Kafka), Zalando Postgres Operator, cert-manager, Prometheus Operator, Argo Rollouts.

---

**Q13: How do you implement zero-downtime deployments in Kubernetes?**

1. Set `maxUnavailable: 0` and `maxSurge: 1` in rolling update strategy
2. Configure proper readiness probes (traffic only sent to ready pods)
3. Add `preStop` lifecycle hook with sleep to drain in-flight requests
4. Set `terminationGracePeriodSeconds` ≥ your max request duration
5. Use PodDisruptionBudget to prevent voluntary disruptions from taking too many pods
6. For canary: use Argo Rollouts or Flagger with weighted traffic splitting

---

**Q14: What is IRSA (IAM Roles for Service Accounts) on EKS?**

Allows pods to assume AWS IAM roles without static credentials.

How it works:
1. EKS cluster has OIDC provider
2. ServiceAccount annotated with IAM role ARN
3. Pod's projected service account token is signed by OIDC issuer
4. AWS SDK/CLI exchanges token for temporary credentials via STS AssumeRoleWithWebIdentity
5. Credentials auto-rotate every hour

No more passing AWS keys as environment variables or using node instance profiles.

---

**Q15: How do you debug a pod that keeps getting OOMKilled?**

1. Confirm OOMKilled: `kubectl describe pod` → check `Last State.Reason: OOMKilled`
2. Check current limits vs usage: `kubectl top pod <name>`
3. Check if it's a memory leak or undersized limits
4. For JVM apps: ensure `-XX:MaxRAMPercentage=75` set, not fixed heap size
5. Temporarily increase limits by 50%, watch if stabilizes
6. For leak: take heap dump, analyze with MAT or async-profiler
7. Set up memory usage alerts in Prometheus before OOM

---

**Q16: What is Horizontal Pod Autoscaler and what are KEDA's advantages?**

HPA scales pod count based on CPU/memory metrics (via Metrics Server). Runs every 15s.

KEDA (Kubernetes Event-Driven Autoscaling) extends HPA:
- Scale to zero (HPA minimum is 1)
- Scale based on external event sources: SQS queue depth, Kafka lag, Prometheus metrics, Redis list length, cron schedules
- 50+ built-in scalers

```yaml
# KEDA ScaledObject — scale on SQS queue depth
spec:
  scaleTargetRef:
    name: worker-deployment
  minReplicaCount: 0        # scale to zero when queue empty
  maxReplicaCount: 50
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.region.amazonaws.com/account/queue
        queueLength: "10"   # target: 10 messages per pod
```

---

**Q17: How does cert-manager work?**

cert-manager is a Kubernetes operator for TLS certificate management.

Flow:
1. Create `Certificate` or `Ingress` with `cert-manager.io/cluster-issuer` annotation
2. cert-manager creates `CertificateRequest`
3. For Let's Encrypt: starts ACME challenge (HTTP-01 or DNS-01)
4. HTTP-01: creates temporary Ingress to serve challenge file
5. DNS-01: updates DNS TXT record via provider (Route53, Cloudflare)
6. Let's Encrypt validates, issues cert
7. cert-manager stores cert in Kubernetes Secret
8. Automatically renews 30 days before expiry

---

**Q18: How do you secure secrets in Kubernetes? (Beyond base64)**

Built-in Kubernetes secrets are only base64 encoded — not encrypted by default.

Proper approaches:
1. **etcd encryption at rest**: `EncryptionConfiguration` with AES-GCM or KMS provider
2. **External Secrets Operator**: Syncs from AWS Secrets Manager, Vault, GCP Secret Manager into K8s Secrets
3. **HashiCorp Vault Agent Injector**: Sidecar injects secrets as files at runtime; never stored in K8s
4. **Sealed Secrets** (Bitnami): Encrypt secrets with cluster public key, safe to store in Git
5. **CSI Secrets Store driver**: Mount secrets as volumes from external stores

Best practice: use External Secrets Operator + AWS Secrets Manager for cloud deployments.
