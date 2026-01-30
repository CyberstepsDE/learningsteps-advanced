# LearningSteps API - Deployment Guide

FastAPI learning journal application with automated CI/CD to Azure Kubernetes Service.

## Features

- **FastAPI** with PostgreSQL, Prometheus metrics (`/metrics`), health checks (`/health`)
- **Auto-Schema**: Database tables created automatically on startup
- **Security**: Trivy code/image scanning, namespace-scoped RBAC, non-root containers
- **CI/CD**: Push to main → build → scan → deploy to AKS

## Required GitHub Secrets

Configure these 5 secrets in **Settings → Secrets and variables → Actions**:

| Secret | Purpose | Command to Get Value |
|--------|---------|---------------------|
| `ACR_LOGIN_SERVER` | Docker registry URL | `az acr show --name acrwesteu --query loginServer -o tsv` |
| `ACR_USERNAME` | Registry token username | Use: `token` |
| `ACR_PASSWORD` | Registry token password | See Step 3 - ACR token |
| `K8S_SERVER` | Kubernetes API | `kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'` |
| `K8S_TOKEN` | Service account token | See Step 2 below |

## Setup Instructions

### Step 1: Create Namespace & Service Account

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/github-deployer-sa.yaml
kubectl apply -f k8s/github-deployer-secret.yaml
```

### Step 2: Extract Service Account Token

```bash
sleep 2  # Wait for token generation
kubectl get secret github-deployer-token -n learningsteps -o jsonpath='{.data.token}' | base64 -d
```

Copy the output → Use for `K8S_TOKEN` GitHub secret.

### Step 3: Get ACR Token

```bash
# Get ACR login server
az acr show --name acrwesteu --query loginServer -o tsv

# Create token (valid for 1 year)
az acr token create \
  --name github-actions-token \
  --registry acrwesteu \
  --scope-map _repositories_admin \
  --expiration-in-days 365

# Get token password (save this - shown only once)
az acr token credential generate \
  --name github-actions-token \
  --registry acrwesteu
```

**GitHub Secrets**:
- `ACR_LOGIN_SERVER`: Output from first command
- `ACR_USERNAME`: `token` (literal string "token")
- `ACR_PASSWORD`: Password from token credential generate

### Step 4: Create Database Secret

```bash
# Get password from Terraform
cd infra-terraform
terraform output postgresql_admin_password

# Create secret (replace PASSWORD with actual password)
DATABASE_URL="postgresql://psqladmin:PASSWORD@psql-dev-aks-west-eu.postgres.database.azure.com:5432/learning_journal?sslmode=require"
kubectl create secret generic learningsteps-secrets \
  --from-literal=database-url="${DATABASE_URL}" \
  -n learningsteps

# Verify secret was created
kubectl get secret learningsteps-secrets -n learningsteps
```

### Step 5: Add GitHub Secrets

1. Go to GitHub repo → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add all 5 secrets from the table above
4. Ensure names are exact (case-sensitive)

## Deployment

**Automatic**: Push to `main` branch
```bash
git push origin main
```

**Manual**: GitHub → Actions → Application CI/CD Pipeline → Run workflow

## Pipeline Stages

The CI/CD pipeline consists of 5 sequential jobs:

### Step 1: Code Security Scan
- **Job**: `code-scan`
- **Purpose**: Scan application source code for vulnerabilities before building
- **Tool**: Trivy filesystem scanner
- **Severity**: CRITICAL and HIGH (informational only, doesn't block)
- **Scans**: Python dependencies, configuration files, secrets

### Step 2: Build, Scan & Push Image
- **Job**: `build-scan-push`
- **Purpose**: Build Docker image, scan for vulnerabilities, push to ACR
- **Steps**:
  1. Build image with tag `${{ github.run_number }}`
  2. Run Trivy image scan (**CRITICAL GATE** - pipeline fails if CRITICAL vulnerabilities found)
  3. Push to ACR only if scan passes
- **Note**: All operations happen in-memory, no artifact uploads needed

### Step 3: Configure Kubernetes Access
- **Job**: `setup-kubernetes`
- **Purpose**: Configure kubectl with service account authentication
- **Condition**: Only runs on `main`/`master` branch
- **Authentication**: Uses `K8S_SERVER` and `K8S_TOKEN` secrets
- **Verification**: Tests cluster connectivity

### Step 4: Deploy to AKS
- **Job**: `deploy-to-kubernetes`
- **Purpose**: Deploy application to Kubernetes cluster
- **Environment**: `production` (requires manual approval if configured)
- **Steps**:
  1. Download image tag artifact from build job
  2. Use `sed` to replace image tag in deployment.yaml
  3. Apply updated deployment manifest
  4. Apply service manifest (LoadBalancer)

### Step 5: Verify Deployment
- **Job**: `verify-deployment`
- **Purpose**: Ensure deployment completed successfully
- **Checks**:
  - Wait for rollout to complete
  - Verify pods are running
  - Check service is available

**Triggers**:
- Push to `main`/`master` branch (auto-deploy)
- Pull requests (build and scan only, no deploy)
- Manual dispatch via GitHub Actions UI

## Monitoring

```bash
# Check resources
kubectl get all -n learningsteps

# View logs
kubectl logs -l app=learningsteps-api -n learningsteps -f

# Get external IP
kubectl get svc learningsteps-api -n learningsteps

# Check rollout
kubectl rollout status deployment/learningsteps-api -n learningsteps
```

## Architecture

**Kubernetes**:
- **Namespace**: `learningsteps` (isolated)
- **Deployment**: 2 replicas, rolling updates, health checks
- **Service**: LoadBalancer (port 80 → 8000)
- **RBAC**: Namespace-scoped Role (no cluster-admin)

**Security**:
- Non-root container (UID 1000)
- Capabilities dropped
- Image scanning blocks CRITICAL CVEs
- Code and image vulnerability scanning with Trivy

**Database**:
- Azure PostgreSQL Flexible Server
- Schema auto-created on app startup
- Tables: `entries` (id, data JSONB, timestamps)

## Local Development

```bash
cd app
pip install -r requirements.txt
export DATABASE_URL="postgresql://user:pass@localhost:5432/learning_journal"
uvicorn main:app --reload
```

**Endpoints**:
- http://localhost:8000 - API root
- http://localhost:8000/health - Health check
- http://localhost:8000/metrics - Prometheus metrics
- http://localhost:8000/docs - Swagger UI

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status and events
kubectl describe pod -l app=learningsteps-api -n learningsteps

# View application logs
kubectl logs -l app=learningsteps-api -n learningsteps --tail=100

# Check if all pods are ready
kubectl get pods -n learningsteps -o wide
```

**Common Issues**:

1. **Missing Database Secret**
   - Symptom: Pod crashes with database connection error
   - Check: `kubectl get secret learningsteps-secrets -n learningsteps`
   - Fix: Create secret using Step 4 instructions above

2. **Image Pull Error**
   - Symptom: `ErrImagePull` or `ImagePullBackOff`
   - Check ACR credentials in GitHub secrets (`ACR_LOGIN_SERVER`, `ACR_USERNAME`, `ACR_PASSWORD`)
   - Verify ACR token hasn't expired: `az acr token show --name github-actions-token --registry acrwesteu`

3. **Database Connection Failed**
   - Symptom: `asyncpg.exceptions.InvalidPasswordError` or connection timeout
   - Verify PostgreSQL server is running and accessible from AKS
   - Check firewall rules allow AKS IP range
   - Verify DATABASE_URL format is correct

4. **Module Not Found**
   - Symptom: `ModuleNotFoundError: No module named 'uvicorn'`
   - Rebuild image with updated Dockerfile (should be fixed with single-stage build)

### Deployment Not Updating

```bash
# Check current image tag
kubectl get deployment learningsteps-api -n learningsteps -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check rollout status
kubectl rollout status deployment/learningsteps-api -n learningsteps

# View rollout history
kubectl rollout history deployment/learningsteps-api -n learningsteps

# Force restart (pulls latest image if tag changed)
kubectl rollout restart deployment/learningsteps-api -n learningsteps

# Rollback to previous version if needed
kubectl rollout undo deployment/learningsteps-api -n learningsteps
```

### Pipeline Failing

**Step 1: Code Scan Fails**
- Trivy found vulnerabilities in dependencies
- Review scan output and update requirements.txt versions
- Pipeline continues even with HIGH severity (only blocks on CRITICAL in image scan)

**Step 2: Build/Scan/Push Fails**

1. **Build Fails**
   - Check Dockerfile syntax
   - Verify all COPY paths exist
   - Check requirements.txt is valid

2. **Trivy Image Scan Fails (CRITICAL GATE)**
   - Critical vulnerability found in image
   - Update base image: Change `FROM python:3.11-slim` to newer version
   - Update system packages: `apt-get upgrade` in Dockerfile
   - Update Python dependencies in requirements.txt
   - Cannot bypass this - vulnerabilities must be fixed

3. **Push to ACR Fails**
   - Verify ACR credentials: `ACR_LOGIN_SERVER`, `ACR_USERNAME=token`, `ACR_PASSWORD`
   - Check ACR exists: `az acr show --name acrwesteu`
   - Verify token has push permissions (scope: `_repositories_admin`)

**Step 3: Kubernetes Access Fails**
- Verify `K8S_SERVER` is correct: Should be `https://...` format
- Verify `K8S_TOKEN` is valid: Token may have been deleted or expired
- Check service account: `kubectl get sa github-deployer -n learningsteps`
- Verify secret exists: `kubectl get secret github-deployer-token -n learningsteps`

**Step 4: Deploy Fails**
- Check namespace exists: `kubectl get namespace learningsteps`
- Verify RBAC permissions: Service account should have Role with deployment permissions
- Check if deployment.yaml syntax is valid

**Step 5: Verification Fails**
- Deployment may be slow to roll out (check pod events)
- Pods may be crash-looping (check logs)
- Health check may be failing (check `/health` endpoint)

## File Structure

```
app/
├── main.py                      # FastAPI app + Prometheus metrics
├── repositories/                # DB layer with auto-init
├── Dockerfile                   # Multi-stage build
└── requirements.txt

k8s/
├── namespace.yaml               # learningsteps namespace
├── github-deployer-sa.yaml      # ServiceAccount + Role + RoleBinding
├── github-deployer-secret.yaml  # Permanent token secret
├── deployment.yaml              # App deployment (2 replicas)
└── service.yaml                 # LoadBalancer service

.github/workflows/
└── app-pipeline.yml             # CI/CD pipeline
```

## Environment Variables

Set in pipeline (`NAMESPACE=learningsteps`):
- Applied to all kubectl commands
- Change in workflow file to use different namespace

## Testing the Deployment

Once deployed, you can test the API:

```bash
# Get the external IP (may take a few minutes to provision)
kubectl get svc learningsteps-api -n learningsteps

# Test health endpoint
EXTERNAL_IP=$(kubectl get svc learningsteps-api -n learningsteps -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP/health

# Test Prometheus metrics
curl http://$EXTERNAL_IP/metrics

# View API documentation
open http://$EXTERNAL_IP/docs  # Swagger UI

# Create a learning journal entry
curl -X POST http://$EXTERNAL_IP/entries \
  -H "Content-Type: application/json" \
  -d '{"data": {"title": "Test Entry", "content": "My first entry"}}'

# List all entries
curl http://$EXTERNAL_IP/entries
```

## Security Best Practices

This project implements several security measures:

1. **Image Scanning**: Trivy scans block deployment if CRITICAL vulnerabilities found
2. **Non-Root Container**: Application runs as UID 1000 (appuser)
3. **Namespace Isolation**: Dedicated namespace with namespace-scoped RBAC
4. **Secret Management**: Database credentials stored in Kubernetes secrets
5. **Network Policies**: Can be added to restrict pod-to-pod communication
6. **TLS**: Should be configured with Ingress controller (not included in basic setup)
7. **ACR Token Auth**: Uses scoped tokens instead of admin credentials
8. **Service Account**: GitHub Actions uses service account with minimal permissions

## Scaling

```bash
# Scale replicas manually
kubectl scale deployment learningsteps-api -n learningsteps --replicas=3

# Enable horizontal pod autoscaling
kubectl autoscale deployment learningsteps-api -n learningsteps \
  --cpu-percent=70 --min=2 --max=10

# Check HPA status
kubectl get hpa -n learningsteps
```

## Cleanup

```bash
# Delete application resources
kubectl delete namespace learningsteps

# Delete ACR images
az acr repository delete --name acrwesteu --repository learningsteps-api --yes

# Delete ACR token
az acr token delete --name github-actions-token --registry acrwesteu --yes

# Destroy Terraform infrastructure
cd infra-terraform
terraform destroy
```

## Support

- **Terraform Issues**: Check `infra-terraform/` outputs and logs
- **Pipeline Failures**: View GitHub Actions logs for detailed error messages
- **Runtime Issues**: Use `kubectl logs` and `kubectl describe` commands
- **Database Issues**: Check PostgreSQL server logs in Azure Portal
