# Project 3: Production Kubernetes Cluster Setup

## Overview
Deploy a production-grade Kubernetes cluster on AWS EKS with full HA, auto-scaling, GitOps via ArgoCD, Ingress, cert-manager, cluster autoscaler, and RBAC hardening.

**Skills**: EKS, Terraform, ArgoCD, Helm, NGINX Ingress, cert-manager, ExternalDNS, Cluster Autoscaler, HPA, PDB

---

## Architecture
```
                    ┌──────────────────────────────────────┐
                    │           AWS EKS Cluster             │
   Internet         │                                      │
   Users ──► ALB ──►│  Nginx Ingress Controller            │
                    │       ↓                              │
                    │  ┌─────────────┐  ┌──────────────┐  │
                    │  │  Namespace: │  │  Namespace:  │  │
                    │  │  production │  │  monitoring  │  │
                    │  └─────────────┘  └──────────────┘  │
                    │                                      │
                    │  ArgoCD (gitops)  cert-manager       │
                    │  ExternalDNS      Cluster Autoscaler │
                    └──────────────────────────────────────┘
                              ↕  (IRSA - IAM)
                    ┌──────────────────────────────────────┐
                    │   AWS: Route53 | ACM | ECR | S3      │
                    └──────────────────────────────────────┘
```

---

## Project Structure
```
03-Kubernetes-Production/
├── terraform/
│   ├── main.tf            # EKS cluster + node groups
│   ├── vpc.tf             # VPC + subnets
│   ├── iam.tf             # IRSA roles
│   ├── variables.tf
│   └── outputs.tf
├── bootstrap/
│   ├── 01-namespaces.yaml
│   ├── 02-argocd-install.sh
│   ├── 03-argocd-apps.yaml
│   └── 04-root-app.yaml
├── k8s/
│   ├── cert-manager/
│   │   └── cluster-issuer.yaml
│   ├── ingress/
│   │   └── ingress-nginx-values.yaml
│   ├── external-dns/
│   │   └── values.yaml
│   └── monitoring/
│       └── kube-prometheus-stack-values.yaml
└── apps/
    └── sample-app/
        ├── deployment.yaml
        ├── service.yaml
        ├── ingress.yaml
        ├── hpa.yaml
        └── pdb.yaml
```

---

## Step 1: EKS with Terraform

**terraform/main.tf** (key sections)
```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.cluster_name}-${var.environment}"
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Control plane logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Enable IRSA
  enable_irsa = true

  # Managed node groups
  eks_managed_node_groups = {
    general = {
      instance_types = ["m6i.xlarge"]
      min_size       = 2
      max_size       = 10
      desired_size   = 3
      
      labels = {
        role = "general"
      }
      
      taints = []
    }
    
    spot = {
      instance_types = ["m6i.xlarge", "m5.xlarge", "m5a.xlarge"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 20
      desired_size   = 0
      
      labels = {
        role = "spot"
      }
      
      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  tags = local.common_tags
}
```

---

## Step 2: Core Add-ons via Helm

**bootstrap/02-argocd-install.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.extraArgs[0]="--insecure" \
  --set redis-ha.enabled=true \
  --set controller.replicas=2 \
  --set server.autoscaling.enabled=true \
  --wait

echo "Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set prometheus.enabled=true \
  --wait

echo "Installing ingress-nginx..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f k8s/ingress/ingress-nginx-values.yaml \
  --wait

echo "Bootstrap complete. ArgoCD ready."
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

---

## Step 3: GitOps with ArgoCD (App of Apps)

**bootstrap/04-root-app.yaml**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/gitops-config
    targetRevision: main
    path: apps/
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## Step 4: Production App Manifests

**apps/sample-app/deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sample-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    metadata:
      labels:
        app: sample-app
        version: v1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      serviceAccountName: sample-app
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
        seccompProfile:
          type: RuntimeDefault
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: sample-app
      terminationGracePeriodSeconds: 60
      containers:
        - name: app
          image: ghcr.io/myorg/sample-app:1.0.0
          ports:
            - containerPort: 8080
            - containerPort: 9090
              name: metrics
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 10"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
```

**apps/sample-app/pdb.yaml**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: sample-app-pdb
  namespace: production
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: sample-app
```

**apps/sample-app/hpa.yaml**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sample-app-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sample-app
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
```

---

## Learning Outcomes
- [ ] Provision EKS with Terraform (node groups, IRSA, logging)
- [ ] Bootstrap GitOps with ArgoCD App of Apps pattern
- [ ] Configure multi-AZ spread for HA
- [ ] Implement zero-downtime rolling updates
- [ ] Set up PDB to protect deployments during node drains
- [ ] Configure HPA with proper scale-down stabilization
- [ ] Harden pods (non-root, read-only FS, drop capabilities)

---

## Interview Talking Points
> "I deployed a production EKS cluster using Terraform with separate on-demand and spot node groups. All deployments are managed via GitOps using ArgoCD's App of Apps pattern — the cluster's desired state lives entirely in Git, and ArgoCD continuously reconciles drift. I implemented proper pod anti-affinity across zones for HA, PodDisruptionBudgets to prevent simultaneous disruption during node drains, and HPA with conservative scale-down windows to prevent flapping. Zero-downtime deployments are ensured by setting maxUnavailable: 0 and using preStop lifecycle hooks to drain in-flight requests."
