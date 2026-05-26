# Kubernetes Cheatsheet — Production Commands & Patterns

## kubectl Context & Config
```bash
kubectl config get-contexts                    # list all clusters
kubectl config use-context CONTEXT_NAME        # switch cluster
kubectl config current-context                 # show active cluster
kubectl config set-context --current --namespace=NAMESPACE  # set default ns
kubens NAMESPACE                               # (kubens plugin) switch namespace
kubectx CONTEXT                               # (kubectx plugin) switch context
```

## Getting Resources
```bash
# List with extra info
kubectl get pods -o wide                       # show node, IP
kubectl get pods -A                            # all namespaces
kubectl get pods -n NAMESPACE -l app=myapp     # label selector
kubectl get all -n NAMESPACE                   # all resource types

# Watch mode
kubectl get pods -w                            # live updates

# Output formats
kubectl get pod POD_NAME -o yaml               # raw YAML
kubectl get pod POD_NAME -o json               # raw JSON
kubectl get pods -o jsonpath='{.items[*].metadata.name}'  # extract fields
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase

# Sort & filter
kubectl get events --sort-by='.lastTimestamp' -n NAMESPACE
kubectl get pods --field-selector=status.phase=Running
kubectl get pods --field-selector=spec.nodeName=NODE_NAME
```

## Describe & Debug
```bash
kubectl describe pod POD_NAME -n NAMESPACE     # full details + events
kubectl describe node NODE_NAME                # node capacity, conditions
kubectl describe svc SERVICE_NAME              # endpoints, selectors

# Logs
kubectl logs POD_NAME                          # container stdout
kubectl logs POD_NAME -c CONTAINER_NAME        # specific container
kubectl logs POD_NAME --previous               # last crashed container
kubectl logs -f POD_NAME                       # follow / stream
kubectl logs -l app=myapp --tail=100           # label selector, last 100 lines

# Shell access
kubectl exec -it POD_NAME -- bash              # interactive shell
kubectl exec -it POD_NAME -c CONTAINER -- sh   # specific container
kubectl exec POD_NAME -- ls /app               # single command

# Port forwarding (local access without exposing)
kubectl port-forward pod/POD_NAME 8080:8080
kubectl port-forward svc/SERVICE_NAME 8080:80
kubectl port-forward deploy/DEPLOY_NAME 8080:8080

# Quick debug pod
kubectl run debug --image=busybox:latest --rm -it --restart=Never -- sh
kubectl run netdebug --image=nicolaka/netshoot --rm -it --restart=Never -- bash
```

## Apply & Manage
```bash
kubectl apply -f manifest.yaml                 # declarative apply
kubectl apply -f ./directory/                  # apply all in dir
kubectl apply -k ./kustomize-dir/              # kustomize
kubectl delete -f manifest.yaml               # delete by manifest

kubectl create deployment NAME --image=IMAGE   # imperative create
kubectl expose deployment NAME --port=80       # create service

# Dry run (test without applying)
kubectl apply -f manifest.yaml --dry-run=client
kubectl apply -f manifest.yaml --dry-run=server  # validates against API
```

## Deployments
```bash
kubectl rollout status deploy/NAME             # watch rollout progress
kubectl rollout history deploy/NAME            # list revisions
kubectl rollout undo deploy/NAME               # rollback 1 version
kubectl rollout undo deploy/NAME --to-revision=3  # rollback to specific
kubectl rollout pause deploy/NAME              # pause rollout
kubectl rollout resume deploy/NAME             # resume rollout

kubectl scale deploy NAME --replicas=5         # scale
kubectl set image deploy/NAME container=image:tag  # update image
kubectl autoscale deploy NAME --min=2 --max=10 --cpu-percent=70  # HPA

# Annotate rollout (shows in history)
kubectl annotate deploy NAME kubernetes.io/change-cause="Deploy v1.2.3 — added payment feature"
```

## Namespaces & RBAC
```bash
kubectl get namespaces
kubectl create namespace myapp-prod

# RBAC
kubectl get roles,rolebindings -n NAMESPACE
kubectl get clusterroles,clusterrolebindings
kubectl auth can-i list pods --namespace default                    # current user
kubectl auth can-i list pods --as=USER --namespace default         # as user
kubectl auth can-i list pods --as=system:serviceaccount:ns:sa      # as SA
kubectl auth can-i --list --namespace NAMESPACE                    # all perms
```

## Resource Usage & Capacity
```bash
kubectl top nodes                              # node CPU/memory
kubectl top pods -n NAMESPACE                 # pod CPU/memory
kubectl top pods --sort-by=cpu -A             # sort by CPU

# Node capacity and allocations
kubectl describe node NODE | grep -A8 "Allocated resources"
```

## Secrets & ConfigMaps
```bash
kubectl create secret generic NAME --from-literal=key=value
kubectl create secret generic NAME --from-file=./secret-file
kubectl create secret docker-registry NAME \
  --docker-server=REGISTRY \
  --docker-username=USER \
  --docker-password=PASS

# View (base64 decode)
kubectl get secret NAME -o jsonpath='{.data.key}' | base64 -d

kubectl create configmap NAME --from-literal=key=value
kubectl create configmap NAME --from-file=./config-file
```

## Network Troubleshooting
```bash
# DNS resolution
kubectl exec -it POD -- nslookup kubernetes.default.svc.cluster.local
kubectl exec -it POD -- nslookup SERVICE_NAME.NAMESPACE.svc.cluster.local

# Check if service has endpoints
kubectl get endpoints SERVICE_NAME -n NAMESPACE

# Test connectivity pod to service
kubectl exec -it POD -- curl http://SERVICE_NAME.NAMESPACE.svc.cluster.local/health

# Check network policies
kubectl get networkpolicies -n NAMESPACE
```

## Node Management
```bash
kubectl cordon NODE_NAME                       # mark unschedulable
kubectl uncordon NODE_NAME                     # mark schedulable
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data  # safe drain
kubectl taint nodes NODE key=value:NoSchedule  # add taint
kubectl taint nodes NODE key=value:NoSchedule- # remove taint (trailing -)
```

## Useful One-Liners
```bash
# Get all image names running in cluster
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'

# Find pods NOT in Running state
kubectl get pods -A --field-selector=status.phase!=Running

# Delete all Evicted pods
kubectl get pods -A | grep Evicted | awk '{print $1" "$2}' | xargs -n2 kubectl delete pod -n

# Get pod restart counts
kubectl get pods -A -o custom-columns='NAMESPACE:.metadata.namespace,POD:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount' --sort-by='.status.containerStatuses[0].restartCount'

# Resource limits/requests summary
kubectl get pods -n NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.containers[*]}  {.name}: req={.resources.requests} lim={.resources.limits}{"\n"}{end}{end}'

# Force delete stuck terminating pod
kubectl delete pod POD_NAME --force --grace-period=0 -n NAMESPACE
```

## Helm Commands
```bash
helm repo add NAME URL                        # add repo
helm repo update                              # refresh repos
helm search repo KEYWORD                      # search charts
helm show values REPO/CHART                  # see all values

helm install RELEASE_NAME REPO/CHART         # install
helm install RELEASE_NAME REPO/CHART \
  --namespace NS --create-namespace \
  -f values-override.yaml \
  --set key=value

helm upgrade RELEASE_NAME REPO/CHART -f values.yaml
helm upgrade --install RELEASE_NAME REPO/CHART  # idempotent

helm list -A                                  # all releases
helm status RELEASE_NAME                      # release info
helm history RELEASE_NAME                     # revision history
helm rollback RELEASE_NAME 2                  # rollback to revision 2
helm uninstall RELEASE_NAME

helm template RELEASE_NAME REPO/CHART -f values.yaml  # render without install
helm diff upgrade RELEASE_NAME REPO/CHART -f values.yaml  # (plugin)
```

## Essential Manifest Snippets

### Pod with security hardening
```yaml
securityContext:           # pod-level
  runAsNonRoot: true
  runAsUser: 1001
  fsGroup: 1001
  seccompProfile:
    type: RuntimeDefault
containers:
  - securityContext:       # container-level
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
```

### HPA with custom metric
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 2
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
```

### PodDisruptionBudget
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 2           # OR: maxUnavailable: 1
  selector:
    matchLabels:
      app: myapp
```

### Topology Spread (multi-AZ HA)
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: myapp
```

## Exit Codes Reference
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | App error (check logs) |
| 137 | OOMKilled (increase memory limit) |
| 139 | Segfault |
| 143 | SIGTERM received (graceful shutdown) |
| 255 | Exit(-1) — check app code |
