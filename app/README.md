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
# Get values from Terraform
cd infra-terraform
terraform output postgresql_fqdn
terraform output postgresql_admin_password

# Create secret (replace values)
DATABASE_URL="postgresql://admin:PASSWORD@FQDN:5432/learning_journal?sslmode=require"
kubectl create secret generic learningsteps-secrets \
  --from-literal=database-url="${DATABASE_URL}" \
  -n learningsteps
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

### CI (Build, Scan & Push)
1. **Trivy Code Scan** - Scan source for vulnerabilities
2. **Docker Build** - Build image with tag `${{ github.run_number }}`
3. **Trivy Image Scan** - **CRITICAL GATE** (fails on CRITICAL vulns)
4. **Push to ACR** - Only if scan passes

### CD (Deploy to AKS)
1. Configure kubectl with service account token
2. Update deployment with new image tag (using `sed`)
3. Apply deployment and service manifests
4. Verify rollout status

**Triggers**: Runs on push to `main`/`master` or manual dispatch

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
# Check pod status
kubectl describe pod -l app=learningsteps-api -n learningsteps

# View logs
kubectl logs -l app=learningsteps-api -n learningsteps

# Common issues:
# - Missing database secret: kubectl get secret learningsteps-secrets -n learningsteps
# - Image pull error: Check ACR credentials in GitHub secrets
```

### Deployment Not Updating

```bash
# Check current image
kubectl get deployment learningsteps-api -n learningsteps -o jsonpath='{.spec.template.spec.containers[0].image}'

# Force restart
kubectl rollout restart deployment/learningsteps-api -n learningsteps
```

### Pipeline Failing

- **Trivy Image Scan**: Critical vulnerability found → Update base image or dependencies
- **Image Pull**: Check ACR credentials in GitHub secrets
- **Kubectl Access**: Verify `K8S_SERVER` and `K8S_TOKEN` are correct

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

## Support

- **Terraform Issues**: Check `infra-terraform/` outputs
- **Pipeline Failures**: View GitHub Actions logs
- **Runtime Issues**: Check pod logs with kubectl
