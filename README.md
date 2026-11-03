
Kubernetes Inventory Service Lab
This project demonstrates Kubernetes service discovery, readiness probes, load balancing across replicas, and Pod replacement after failure.
The application consists of:

An inventory Deployment with two replicas.
An inventory ClusterIP Service that provides a stable DNS name.
A client Pod that sends HTTP requests to http://inventory using the Service name.
Architecture

Client Pod
Inventory Service
Inventory Pod 1
Inventory Pod 2
Inventory Deployment
http://inventory
The client never uses an individual Pod IP or Pod name. Kubernetes DNS resolves the Service name inventory, and the Service forwards traffic only to ready Pods.
Prerequisites
Install one Kubernetes environment:
Minikube
Kind
Docker Desktop with Kubernetes enabled
Also install kubectl and verify access:
kubectl version --client
kubectl get nodes
Project Structure
The repository should use the following structure:
.
├── inventory-service/
│   ├── app.py
│   ├── Dockerfile
│   └── requirements.txt
├── client/
│   ├── client.py
│   ├── Dockerfile
│   └── requirements.txt
├── k8s/
│   ├── inventory-deployment.yaml
│   ├── inventory-service.yaml
│   └── client-deployment.yaml
└── README.md
The evidence files requested by the assignment can be added later in an optional evidence/ directory. The commands below assume the exact filenames shown above.
Expected Kubernetes Resources
inventory-service/app.py
The Inventory application should provide these HTTP endpoints:
GET / — returns a response identifying the Inventory Pod that handled the request.
GET /health — returns HTTP 200 while the process is alive.
GET /ready — returns HTTP 200 when the Pod is ready and a non-200 response when readiness is intentionally disabled.
The response from / should include the Pod identity. The Deployment passes the Kubernetes Pod name through the POD_NAME environment variable.
inventory-service/Dockerfile and requirements.txt
The Inventory Dockerfile should install the dependencies from requirements.txt, copy app.py, expose port 8080, and start the web server on 0.0.0.0:8080.
k8s/inventory-deployment.yaml
Create a Deployment named inventory with:
replicas: 2
Label app: inventory
A container that listens on port 8080
A readiness probe that checks GET /ready on port 8080
A liveness probe that checks GET /health on port 8080
The application response should identify the serving Pod, for example through the HOSTNAME environment variable.
Example container configuration:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory
spec:
  replicas: 2
  selector:
    matchLabels:
      app: inventory
  template:
    metadata:
      labels:
        app: inventory
    spec:
      containers:
        - name: inventory
          image: inventory-service:latest
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          readinessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 2
            periodSeconds: 3
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
If you use a different image tag, update k8s/inventory-deployment.yaml and the image-build commands consistently. For local clusters, set imagePullPolicy: IfNotPresent or load the image into the cluster.
Inventory Service
Create a Service named inventory that selects the two Deployment Pods:
apiVersion: v1
kind: Service
metadata:
  name: inventory
spec:
  type: ClusterIP
  selector:
    app: inventory
  ports:
    - name: http
      port: 80
      targetPort: http
Inside the cluster, the client can call the application with:
http://inventory
The full DNS name is also available:
http://inventory.default.svc.cluster.local
client/client.py, client/Dockerfile, and client/requirements.txt
The client should send repeated HTTP requests to the value of the INVENTORY_URL environment variable and print each response. Its dependencies and startup command belong in the client Dockerfile and requirements file.
k8s/client-deployment.yaml
The client should run inside the cluster and send repeated requests to the Service name:
apiVersion: v1
kind: Deployment
metadata:
  name: inventory-client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inventory-client
  template:
    metadata:
      labels:
        app: inventory-client
    spec:
      containers:
        - name: client
          image: inventory-client:latest
          env:
            - name: INVENTORY_URL
              value: http://inventory
The client must not contain a hard-coded Pod IP or Pod name. Its output should display the response from the Inventory application, including the serving Pod identity.
Deployment Instructions
1. Start the cluster
Use the command for your selected Kubernetes environment.
# Minikube
minikube start

# Kind
kind create cluster --name inventory-lab
For Docker Desktop, enable Kubernetes through Docker Desktop settings and wait until the cluster reports Running.
Confirm the active context:

kubectl config current-context
kubectl get nodes
2. Build or load images
Build the Inventory and client images according to the source code in this repository. For Minikube, one option is:
eval "$(minikube docker-env)"
docker build -t inventory-service:latest ./inventory-service
docker build -t inventory-client:latest ./client
For Kind, build locally and load the images:
docker build -t inventory-service:latest ./inventory-service
docker build -t inventory-client:latest ./client
kind load docker-image inventory-service:latest --name inventory-lab
kind load docker-image inventory-client:latest --name inventory-lab
If the images are hosted in a registry, push them and update the image references in k8s/inventory-deployment.yaml and k8s/client-deployment.yaml.
3. Apply the manifests
kubectl apply -f k8s/inventory-deployment.yaml
kubectl apply -f k8s/inventory-service.yaml
kubectl apply -f k8s/client-deployment.yaml
These manifests use the default namespace unless a namespace is explicitly added to the YAML files.
Wait for the Deployment:

kubectl rollout status deployment/inventory
kubectl get pods -l app=inventory -o wide
kubectl get service inventory
kubectl get endpoints inventory
The expected initial state is two Running and Ready Inventory Pods, with two endpoints listed for the Service.
Test 1: Service Discovery and Replica Traffic
Run the client and save its output:
kubectl rollout status deployment/inventory-client
kubectl logs -f deployment/inventory-client
The client should call http://inventory, not an individual Pod address. Run enough requests to make the serving Pod identity visible:
kubectl exec deployment/inventory-client -- sh -c 'for i in $(seq 1 20); do wget -qO- http://inventory; echo; done'
Verify the replica identities:
kubectl get pods -l app=inventory -o wide
kubectl get endpoints inventory -o wide
Expected result: responses should show requests being handled by both Inventory Pod names over multiple requests. Because Service routing is not guaranteed to alternate perfectly on every request, run several requests and record the distinct Pod identities observed.
Evidence to add
Add the following to the repository under evidence/ and reference them here:
<!-- Add a screenshot or terminal output showing two Running/Ready Pods. -->
<!-- Add client output showing responses from both Pod identities. -->
<!-- Add Service and endpoint output showing the stable Service name. -->
Test 2: Readiness Failure and Recovery
Identify the two Inventory Pods:
kubectl get pods -l app=inventory
Choose one Pod and make it fail readiness. The recommended approach is to use an application-controlled readiness switch, if implemented by the Inventory application. For example:
kubectl exec POD_TO_TEST -- sh -c 'touch /tmp/not-ready'
The application should return a non-success status from /ready while /tmp/not-ready exists. If your application uses a different readiness mechanism, document that mechanism and use it instead.
Observe the state:

kubectl get pods -l app=inventory -w
kubectl describe pod POD_TO_TEST
kubectl get endpoints inventory -o wide
The selected Pod should remain Running but become 0/1 Ready. Its endpoint should be removed from the Service, while the other ready Pod remains available.
Send requests during the failure:

kubectl exec deployment/inventory-client -- sh -c 'for i in $(seq 1 10); do wget -qO- http://inventory; echo; done'
Expected result: normal Service traffic is handled by the remaining ready Pod. The unready Pod may still be reachable directly for diagnostic purposes, but it should not receive normal traffic through the inventory Service.
Restore readiness using the application-specific recovery command. For the example mechanism above:

kubectl exec POD_TO_TEST -- sh -c 'rm -f /tmp/not-ready'
kubectl wait --for=condition=Ready pod/POD_TO_TEST --timeout=60s
kubectl get endpoints inventory -o wide
Run the client again and verify that the restored Pod can receive traffic:
kubectl exec deployment/inventory-client -- sh -c 'for i in $(seq 1 20); do wget -qO- http://inventory; echo; done'
Evidence to add
<!-- Add output showing the selected Pod is Running but NotReady. -->
<!-- Add endpoint output showing that the unready Pod was removed. -->
<!-- Add client output showing the remaining ready Pod serving requests. -->
<!-- Add output showing readiness restored and the endpoint returned. -->
Test 3: Pod Deletion and Replacement
List the current Inventory Pods and save their names:
kubectl get pods -l app=inventory
Delete one Inventory Pod:
POD_TO_DELETE=$(kubectl get pods -l app=inventory -o jsonpath='{.items[0].metadata.name}')
echo "Deleting $POD_TO_DELETE"
kubectl delete pod "$POD_TO_DELETE"
Watch Kubernetes create the replacement:
kubectl get pods -l app=inventory -w
kubectl rollout status deployment/inventory
kubectl get pods -l app=inventory -o wide
kubectl get service inventory
kubectl get endpoints inventory -o wide
Expected result:
The deleted Pod terminates.
The Deployment creates a replacement Pod.
The replacement has a different generated Pod name and identity.
The inventory Service name and ClusterIP remain unchanged.
Once the replacement passes readiness, it becomes a Service endpoint.
Confirm that the client continues to work through the same Service name:
kubectl rollout status deployment/inventory-client
kubectl exec deployment/inventory-client -- sh -c 'for i in $(seq 1 20); do wget -qO- http://inventory; echo; done'
Evidence to add
<!-- Add output before deletion showing the original Pod name. -->
<!-- Add output showing the deleted Pod and replacement Pod with a different name. -->
<!-- Add Service output proving that the Service name remained inventory. -->
<!-- Add client output after replacement proving continued communication. -->
Useful Diagnostic Commands
kubectl get all
kubectl get pods -l app=inventory -o wide
kubectl describe deployment inventory
kubectl describe service inventory
kubectl describe pod POD_NAME
kubectl logs POD_NAME -c inventory
kubectl get endpoints inventory -o yaml
kubectl get events --sort-by=.lastTimestamp
To clean up the lab:
kubectl delete -f k8s/client-deployment.yaml
kubectl delete -f k8s/inventory-service.yaml
kubectl delete -f k8s/inventory-deployment.yaml
Results and Evidence
Place screenshots, logs, and terminal transcripts in the evidence/ directory. Each evidence item should include a short caption explaining which requirement it proves.
Suggested evidence files:

evidence/
├── screenshots/
│   ├── initial-two-ready-pods.png
│   ├── service-endpoints.png
│   ├── readiness-failure.png
│   ├── readiness-recovery.png
│   └── pod-replacement.png
└── logs/
    ├── replica-traffic.txt
    ├── readiness-test.txt
    └── pod-replacement.txt
Replace this section with links or embedded images after performing the lab. Do not claim a result until the corresponding screenshot or terminal output has been added.
Reflection
A stable Kubernetes Service name is useful because clients can communicate with one consistent DNS name even when the Pods behind it are recreated. Pods are temporary and their IP addresses and names can change after failures, rescheduling, or rolling updates, while the Service provides a stable virtual endpoint. The Service also continuously updates its endpoints based on readiness, so traffic is sent only to Pods that are currently able to serve requests. This lets the client continue working without knowing about Pod replacement or maintaining Pod-specific addresses.
Submission
Submit only the URL of the GitHub repository. Ensure that the repository contains the application source code, Kubernetes manifests, this README, and the completed evidence files before submitting.
