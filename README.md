# Module 6 – Kubernetes Service Discovery, Readiness & Pod Replacement

A small Flask **Inventory Service** runs as 2 replicas behind a Kubernetes **Service**. A **client** Pod calls the Inventory Service every 2 seconds **using only the Service name** (`http://inventory-service:8080`) and logs which Pod answered. This shows how Kubernetes handles service discovery, readiness, and Pod replacement.

## Repository layout

```
inventory-service/   Flask app (/, /health/readiness, /health/liveness, /toggle-ready) + Dockerfile
client/              Python client that calls the Service every 2s + Dockerfile
k8s/
  inventory-deployment.yaml   Deployment, 2 replicas, readiness + liveness probes
  inventory-service.yaml      ClusterIP Service "inventory-service" on port 8080
  client-deployment.yaml      Client Deployment, INVENTORY_URL=http://inventory-service:8080
scripts/run-demo.sh  Runs all three tests and saves output to evidence/
evidence/            Terminal output captured by run-demo.sh
screenshots/         Screenshots of the system working
```

## Architecture

```mermaid
flowchart LR
    C["inventory-client Pod<br/>GET http://inventory-service:8080<br/>every 2s"]
    S(["Service: inventory-service<br/>ClusterIP :8080<br/>selector app=inventory"])
    subgraph D["Deployment: inventory (replicas: 2)"]
        P1["inventory Pod #1<br/>Flask :8080<br/>readinessProbe /health/readiness"]
        P2["inventory Pod #2<br/>Flask :8080<br/>readinessProbe /health/readiness"]
    end
    C -- "DNS: inventory-service" --> S
    S -- "only Ready Pods" --> P1
    S -- "only Ready Pods" --> P2
```

- The client never uses Pod IPs, only the DNS name `inventory-service`.
- The Service sends traffic only to Pods whose readiness probe passes (its *endpoints*).
- The Deployment keeps 2 replicas running and replaces any Pod that is deleted.

## How to deploy

Tested with **Docker Desktop Kubernetes** (minikube also works; see the note below).

1. Turn on Kubernetes: Docker Desktop → Settings → Kubernetes → **Enable Kubernetes** → Apply & restart.
2. Build the images:
   ```bash
   kubectl config use-context docker-desktop
   docker build -t inventory-service:latest ./inventory-service
   docker build -t inventory-client:latest ./client
   ```
3. Deploy:
   ```bash
   kubectl apply -f k8s/
   kubectl rollout status deployment/inventory
   kubectl get pods,svc,endpoints
   ```
4. Watch the client:
   ```bash
   kubectl logs -f deployment/inventory-client
   ```
5. Run all three tests and save the evidence:
   ```bash
   ./scripts/run-demo.sh
   ```

**minikube instead:** run `minikube start`, build the images as above, then `minikube image load inventory-service:latest` and `minikube image load inventory-client:latest` before `kubectl apply`. The manifests use `imagePullPolicy: Never`, so the images must be built locally.

**Cleanup:** `kubectl delete -f k8s/`

### Making a Pod fail readiness by hand

```bash
POD=$(kubectl get pods -l app=inventory -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- python -c "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/toggle-ready', method='POST')).read().decode())"
```
Run the same command again to make it ready again.

## Results

<!-- EVIDENCE -->
_Evidence is added after running `./scripts/run-demo.sh`._

## Reflection: why a stable Service name is useful

Pods are temporary: they get new names and IP addresses whenever they are restarted, rescheduled, or replaced, as the Pod deletion test showed. If the client called Pod IPs directly, it would break every time a Pod changed. The Service gives a single, stable DNS name and ClusterIP that stay the same while the Pods behind it come and go. Kubernetes keeps the Service's endpoints up to date automatically, adding Pods when they become Ready and removing them when they fail readiness or are deleted. As a result, the client needs no code or configuration changes and keeps working through failures and recoveries.
