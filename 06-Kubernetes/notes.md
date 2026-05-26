# Kubernetes — Deep Dive Notes

## 1. Architecture

```
Control Plane                        Worker Nodes
┌─────────────────────────┐         ┌──────────────────┐
│  kube-apiserver          │         │ kubelet           │
│  etcd                    │◄───────►│ kube-proxy        │
│  kube-scheduler          │         │ container runtime │
│  controller-manager      │         │ (containerd/CRI-O)│
│  cloud-controller-manager│         └──────────────────┘
└─────────────────────────┘
```

### Components Deep Dive

**kube-apiserver:** All communication goes through here. Validates, persists to etcd, publishes watch events.

**etcd:** Distributed key-value store. Single source of truth for all cluster state. Raft consensus. Backup critical! `etcdctl snapshot save backup.db`

**kube-scheduler:** Watches for unscheduled pods, finds best node using predicates (can pod run here?) → priorities (which node is best?).

**controller-manager:** Runs reconciliation loops: Deployment controller, ReplicaSet controller, Node controller, Service controller, etc.

**kubelet:** Agent on each node. Watches PodSpecs from API server, ensures containers are running and healthy. Reports node/pod status.

**kube-proxy:** Maintains network rules (iptables or IPVS) for Service VIPs.

---

## 2. Core Workloads

### Pod
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
  labels:
    app: myapp
    version: v1
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
    fsGroup: 1001
  initContainers:
    - name: init-db
      image: busybox
      command: ['sh', '-c', 'until nc -z db 5432; do sleep 2; done']
  containers:
    - name: app
      image: myapp:1.2.3
      ports:
        - containerPort: 8080
      env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        - name: CONFIG_VALUE
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: value
      resources:
        requests:
          cpu: 100m      # guaranteed CPU
          memory: 128Mi  # guaranteed memory
        limits:
          cpu: 500m      # max CPU
          memory: 512Mi  # max memory (OOM killed if exceeded)
      readinessProbe:
        httpGet:
          path: /ready
          port: 8080
        initialDelaySeconds: 10
        periodSeconds: 5
        failureThreshold: 3
      livenessProbe:
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 30
        periodSeconds: 10
        failureThreshold: 3
      startupProbe:
        httpGet:
          path: /health
          port: 8080
        failureThreshold: 30
        periodSeconds: 10    # 30*10=300s to start
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: [ALL]
      volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: config
          mountPath: /etc/config
          readOnly: true
  volumes:
    - name: tmp
      emptyDir: {}
    - name: config
      configMap:
        name: app-config
```

### Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    metadata:
      labels:
        app: myapp
        version: "1.2.3"
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      # Spread pods across nodes
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: myapp
      # Anti-affinity — don't schedule on same node
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values: [myapp]
              topologyKey: kubernetes.io/hostname
      terminationGracePeriodSeconds: 60
      containers:
        - name: app
          image: myapp:1.2.3
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 10"]  # drain connections
```

### StatefulSet
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres   # headless service name
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    spec:
      containers:
        - name: postgres
          image: postgres:16
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:      # PVC per pod
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: fast-ssd
        resources:
          requests:
            storage: 50Gi
```

---

## 3. Services & Networking

```yaml
# ClusterIP (default — internal only)
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
  ports:
    - port: 80          # service port
      targetPort: 8080  # container port
      protocol: TCP

# Headless — direct pod DNS (for StatefulSets, service discovery)
spec:
  clusterIP: None    # no virtual IP
  # Creates: postgres-0.postgres.default.svc.cluster.local

# NodePort
spec:
  type: NodePort
  ports:
    - port: 80
      nodePort: 30080   # 30000-32767 range
```

### Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts: [api.example.com]
      secretName: api-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /v1
            pathType: Prefix
            backend:
              service:
                name: api-v1
                port:
                  number: 80
          - path: /v2
            pathType: Prefix
            backend:
              service:
                name: api-v2
                port:
                  number: 80
```

---

## 4. Storage

### PersistentVolume & PVC
```yaml
# StorageClass (dynamic provisioning)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer   # better for multi-AZ
allowVolumeExpansion: true

# PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  storageClassName: fast-ssd
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 20Gi
```

---

## 5. ConfigMaps & Secrets

```yaml
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_ENV: production
  LOG_LEVEL: info
  config.yaml: |
    server:
      port: 8080
    database:
      pool_size: 10

# Secret (base64 encoded — use External Secrets Operator or Vault in production)
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:           # plain text, auto-encoded
  password: supersecret
  connection-string: "postgresql://user:supersecret@db:5432/app"
```

---

## 6. RBAC

```yaml
# ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123:role/app-role  # IRSA

# Role (namespace-scoped)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "patch"]  # no delete

# RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-sa-role
  namespace: production
subjects:
  - kind: ServiceAccount
    name: app-sa
    namespace: production
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

---

## 7. Autoscaling

### HPA (Horizontal Pod Autoscaler)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: AverageValue
          averageValue: 400Mi
    - type: External            # custom metric (e.g., queue depth)
      external:
        metric:
          name: sqs_queue_depth
        target:
          type: AverageValue
          averageValue: "100"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 4
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300   # slow scale-down
```

### VPA (Vertical Pod Autoscaler)
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: myapp-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  updatePolicy:
    updateMode: "Off"   # Recommend only, don't auto-update
```

---

## 8. Helm

```bash
# Install chart
helm install myapp ./mychart -n production -f values.prod.yaml \
  --set image.tag=1.2.3 \
  --wait --timeout 5m

# Upgrade with atomic rollback on failure
helm upgrade --install myapp ./mychart \
  --atomic --cleanup-on-fail \
  -f values.prod.yaml

# Rollback
helm rollback myapp 1

# Debug
helm template myapp ./mychart -f values.yaml | kubectl apply --dry-run=client -f -
helm install myapp ./mychart --debug --dry-run
```

### Helm Chart Structure
```
mychart/
├── Chart.yaml          # metadata
├── values.yaml         # default values
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── _helpers.tpl    # named templates
│   └── NOTES.txt
└── charts/             # dependencies
```

---

## 9. Resource Management & QoS

### QoS Classes
| Class | Condition | Eviction Priority |
|-------|-----------|------------------|
| Guaranteed | requests == limits for all containers | Last evicted |
| Burstable | Some resources have requests != limits | Middle |
| BestEffort | No requests or limits set | First evicted |

```yaml
# Guaranteed QoS
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 200m       # same as request
    memory: 256Mi   # same as request
```

### LimitRange & ResourceQuota
```yaml
# LimitRange — defaults for pods in namespace
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 256Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: 2
        memory: 2Gi

# ResourceQuota — total namespace limits
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    pods: "100"
    services: "20"
    persistentvolumeclaims: "20"
```

---

## 10. Useful kubectl Commands

```bash
# Quick diagnosis
kubectl get pods -n ns -o wide
kubectl describe pod <name> -n ns
kubectl logs pod -n ns -c container --previous --tail=100
kubectl exec -it pod -n ns -- bash

# Resource usage
kubectl top pods -n ns --sort-by=memory
kubectl top nodes

# Events (chronological)
kubectl get events -n ns --sort-by=.lastTimestamp

# Patch/edit
kubectl patch deployment myapp -n ns -p '{"spec":{"replicas":5}}'
kubectl set image deployment/myapp app=myapp:1.2.4

# Port forward for debugging
kubectl port-forward pod/myapp-xxx 8080:8080 -n ns
kubectl port-forward svc/myapp 8080:80 -n ns

# Copy files
kubectl cp pod:/tmp/heap.hprof ./heap.hprof

# Debug with ephemeral container
kubectl debug -it pod/myapp --image=nicolaka/netshoot --target=app

# Rollout management
kubectl rollout status deployment/myapp
kubectl rollout history deployment/myapp
kubectl rollout undo deployment/myapp
kubectl rollout pause/resume deployment/myapp

# Drain a node
kubectl cordon node01
kubectl drain node01 --ignore-daemonsets --delete-emptydir-data
kubectl uncordon node01
```

## 📚 Resources

- https://kubernetes.io/docs/ — Official docs
- https://k8s.af/ — Kubernetes failure stories
- https://learnk8s.io/ — In-depth articles
- https://www.cncf.io/certification/cka/ — CKA exam
- https://killercoda.com/killer-shell-cka — CKA practice
- https://github.com/kelseyhightower/kubernetes-the-hard-way
