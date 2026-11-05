#!/usr/bin/env bash
# Runs the three lab demonstrations and saves the terminal output to evidence/.
# Usage (from the repo root):  ./scripts/run-demo.sh
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=evidence
mkdir -p "$OUT"

section() { echo; echo "========== $* =========="; }
run()     { echo "\$ $*"; "$@"; echo; }

# Count which pod answered each client request in a recent time window.
client_counts() {
  echo "\$ kubectl logs deployment/inventory-client --since=$1 | grep -o 'pod=[^ ]*' | sort | uniq -c"
  kubectl logs deployment/inventory-client --since="$1" | grep -o 'pod=[^ ]*' | sort | uniq -c
  echo
}

# Flip a pod's readiness by calling its /toggle-ready endpoint from inside the pod.
toggle() {
  echo "\$ kubectl exec $1 -- POST http://localhost:8080/toggle-ready"
  kubectl exec "$1" -c inventory -- python -c \
    "import urllib.request as u; print(u.urlopen(u.Request('http://localhost:8080/toggle-ready', method='POST')).read().decode())"
  echo
}

############################################################
# 0. Deploy
############################################################
{
  section "0. Cluster and deployment  ($(date))"
  run kubectl config current-context
  run kubectl get nodes
  run kubectl apply -f k8s/
  run kubectl rollout status deployment/inventory --timeout=120s
  run kubectl rollout status deployment/inventory-client --timeout=120s
} 2>&1 | tee "$OUT/00-deploy.txt"

############################################################
# 1. Both replicas running and receiving traffic via the Service
############################################################
{
  section "1. Deployment, Service and load balancing  ($(date))"
  run kubectl get deployment inventory
  run kubectl get pods -l app=inventory -o wide
  run kubectl get service inventory-service
  run kubectl get endpoints inventory-service
  section "Client is configured with the Service name (not pod IPs)"
  run kubectl get deployment inventory-client -o jsonpath='{.spec.template.spec.containers[0].env}'
  echo; echo "Collecting 30s of client traffic..."; sleep 30
  section "Client log (last 15 lines)"
  run kubectl logs deployment/inventory-client --tail=15
  section "Requests per pod in the last 30s (both replicas should appear)"
  client_counts 30s
} 2>&1 | tee "$OUT/01-service-and-replicas.txt"

POD_A=$(kubectl get pods -l app=inventory -o jsonpath='{.items[0].metadata.name}')
POD_B=$(kubectl get pods -l app=inventory -o jsonpath='{.items[1].metadata.name}')

############################################################
# 2a. Readiness failure
############################################################
{
  section "2a. Readiness failure: making $POD_A unready  ($(date))"
  toggle "$POD_A"
  echo "Waiting for the readiness probe to mark $POD_A as NotReady..."
  run kubectl wait --for=condition=Ready=false "pod/$POD_A" --timeout=60s
  section "Pod is still Running (READY 0/1, no restarts)"
  run kubectl get pods -l app=inventory -o wide
  section "Only the ready pod is left in the Service endpoints"
  run kubectl get endpoints inventory-service
  section "Readiness probe events for $POD_A"
  echo "\$ kubectl describe pod $POD_A | (Events)"
  kubectl describe pod "$POD_A" | sed -n '/^Events:/,$p' | tail -6
  echo
  echo "Collecting 30s of client traffic while $POD_A is unready..."; sleep 30
  section "Client log while $POD_A is unready (only $POD_B should answer)"
  run kubectl logs deployment/inventory-client --since=30s --tail=15
  section "Requests per pod in the last 30s"
  client_counts 30s
} 2>&1 | tee "$OUT/02-readiness-failure.txt"

############################################################
# 2b. Readiness recovery
############################################################
{
  section "2b. Readiness recovery: restoring $POD_A  ($(date))"
  toggle "$POD_A"
  run kubectl wait --for=condition=Ready "pod/$POD_A" --timeout=60s
  run kubectl get pods -l app=inventory -o wide
  run kubectl get endpoints inventory-service
  echo "Collecting 30s of client traffic after recovery..."; sleep 30
  section "Client log after recovery"
  run kubectl logs deployment/inventory-client --since=30s --tail=15
  section "Requests per pod in the last 30s (both replicas again)"
  client_counts 30s
} 2>&1 | tee "$OUT/03-readiness-recovery.txt"

############################################################
# 3. Pod failure and replacement
############################################################
{
  section "3. Pod failure and recovery: deleting $POD_A  ($(date))"
  SVC_BEFORE=$(kubectl get service inventory-service -o jsonpath='{.metadata.name} {.spec.clusterIP}')
  BEFORE=$(kubectl get pods -l app=inventory -o jsonpath='{.items[*].metadata.name}')
  section "Before deletion"
  run kubectl get pods -l app=inventory -o wide
  run kubectl get service inventory-service
  run kubectl delete pod "$POD_A" --wait=false
  sleep 3
  section "Immediately after deletion (old pod terminating, new pod being created)"
  run kubectl get pods -l app=inventory -o wide
  run kubectl rollout status deployment/inventory --timeout=120s
  sleep 5
  section "After recovery"
  run kubectl get pods -l app=inventory -o wide
  run kubectl get service inventory-service
  run kubectl get endpoints inventory-service
  AFTER=$(kubectl get pods -l app=inventory --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')
  SVC_AFTER=$(kubectl get service inventory-service -o jsonpath='{.metadata.name} {.spec.clusterIP}')
  NEW_POD=""
  for p in $AFTER; do case " $BEFORE " in *" $p "*) ;; *) NEW_POD=$p ;; esac; done
  section "Summary"
  echo "Deleted pod:          $POD_A"
  echo "Replacement pod:      ${NEW_POD:-<not found>}"
  echo "Service before:       $SVC_BEFORE"
  echo "Service after:        $SVC_AFTER"
  echo
  echo "Collecting 30s of client traffic after replacement..."; sleep 30
  section "Client log after replacement (new pod should appear)"
  run kubectl logs deployment/inventory-client --since=30s --tail=15
  section "Requests per pod in the last 30s"
  client_counts 30s
} 2>&1 | tee "$OUT/04-pod-replacement.txt"

echo
echo "Done. Evidence saved in $OUT/"
