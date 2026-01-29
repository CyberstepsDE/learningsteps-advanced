# Chapter 1: Infrastructure as Code (IaaC)

> **Cybersteps Module 3 - Advanced Kubernetes Learning Series**

This chapter covers deploying Azure Kubernetes Service (AKS) using Terraform, with a CI/CD pipeline for security scanning and validation.

---

## Table of Contents

- [Important Note for Students](#important-note-for-students)
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [What You Need to Change](#what-you-need-to-change)
- [Quick Start (Local Deployment)](#quick-start-local-deployment)
- [Project Structure](#project-structure)
- **Resources**
  - [Azure Kubernetes Service (AKS)](#azure-kubernetes-service-aks)
  - [Azure Container Registry (ACR)](#azure-container-registry-acr)
  - [PostgreSQL Flexible Server](#postgresql-flexible-server)
- [Security Features](#security-features)
- [CI/CD Pipeline](#cicd-pipeline)
- [Remote State Backend](#remote-state-backend)
- [Creating Azure Service Principal](#creating-azure-service-principal)
- [Outputs](#outputs)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [Resources Links](#resources-links)

---

## Important Note for Students

> **Lab Environment Limitation**: In this training environment, students do not have access to Azure IAM (Identity and Access Management) to create Service Principals. Therefore, **Terraform will be deployed manually** using local Azure CLI authentication (`az login`).
>
> **In a real-world production scenario**, you would:
>
> 1. Create a Service Principal with appropriate permissions
> 2. Configure GitHub Secrets with the credentials
> 3. Set `ENABLE_AZURE_DEPLOY=true` in repository variables
> 4. Let the CI/CD pipeline handle all deployments automatically
>
> The pipeline is fully configured and ready - it just needs the Azure credentials to be enabled.

---

## Overview

This Terraform configuration provisions:

- **Azure Resource Group**: Organizes and manages Azure resources
- **AKS Cluster**: Azure Kubernetes Service with configurable node pool
- **Azure Container Registry (ACR)**: Private container registry attached to AKS
- **PostgreSQL Flexible Server**: Azure Database for PostgreSQL with database and firewall rules

---

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- An Azure subscription

---

## What You Need to Change

Before deploying, update these values in the configuration files:

### terraform.tfvars

```hcl
# Azure Configuration
location        = "West Europe"           # Your preferred Azure region
environment     = "dev"                   # Environment: dev, staging, prod
subscription_id = "YOUR-SUBSCRIPTION-ID"  # Replace with YOUR Azure subscription ID

# AKS Configuration
cluster_name    = "aks-west-eu"           # Your unique cluster name
node_count      = 2                       # Number of worker nodes
vm_size         = "Standard_D2s_v3"       # VM size for nodes

# Container Registry
acr_name        = "acrwesteu"             # Globally unique ACR name (alphanumeric only)

# PostgreSQL Database
postgresql_database_name = "learning_journal"  # Name of the database to create
```

| Variable                   | What to Change                                            |
| -------------------------- | --------------------------------------------------------- |
| `subscription_id`          | **Required** - Replace with YOUR Azure subscription ID    |
| `acr_name`                 | **Required** - Must be globally unique, alphanumeric only |
| `postgresql_database_name` | Name of the PostgreSQL database to create                 |
| `location`                 | Your preferred Azure region                               |
| `cluster_name`             | Your unique cluster name                                  |
| `node_count`               | Adjust based on your workload needs                       |

### backend.tf

| Setting                | Current Value                                 | What to Change                             |
| ---------------------- | --------------------------------------------- | ------------------------------------------ |
| `resource_group_name`  | "rg-terraform-state"                          | Your state storage resource group          |
| `storage_account_name` | "tfstateblob234"                              | **Replace with YOUR storage account name** |
| `container_name`       | "tfstate"                                     | Keep as-is or change                       |
| `key`                  | "application/learningsteps/terraform.tfstate" | Unique path for your state file            |

### Finding Your Subscription ID

```bash
# List all subscriptions
az account list --output table

# Get current subscription ID
az account show --query id --output tsv
```

---

## Quick Start (Local Deployment)

### 1. Authenticate with Azure

```bash
az login
az account set --subscription <subscription-id>
```

### 2. Set the PostgreSQL Password

The `postgresql_admin_password` is a required sensitive variable. Pass it using one of these methods:

**Option A: Environment variable (recommended)**

```bash
export TF_VAR_postgresql_admin_password="YourSecurePass123"
```

**Option B: Command line flag**

```bash
terraform plan -var="postgresql_admin_password=YourSecurePass123"
terraform apply -var="postgresql_admin_password=YourSecurePass123"
```

**Option C: Create a local tfvars file (gitignored)**

```bash
# Create terraform.tfvars.local (already in .gitignore)
echo 'postgresql_admin_password = "YourSecurePass123"' > terraform.tfvars.local

# Then use it
terraform plan -var-file="terraform.tfvars.local"
```

> **Password Requirements**: Use a strong password with uppercase, lowercase, numbers, and special characters. Minimum 8 characters.

### 3. Initialize and Deploy

```bash
cd infra-terraform

# Initialize Terraform
terraform init

# Review changes (if using env var)
terraform plan

# Or with inline password
terraform plan -var="postgresql_admin_password=YourSecurePass123"

# Apply
terraform apply
```

### 4. Connect to Your Cluster

```bash
az aks get-credentials --resource-group rg-dev-aks --name aks-west-eu
kubectl get nodes
```

---

## Project Structure

```
infra-terraform/
├── main.tf           # Resource Group definition
├── aks.tf            # Azure Kubernetes Service cluster
├── acr.tf            # Azure Container Registry + AKS role assignment
├── postgresql.tf     # PostgreSQL Flexible Server + database + firewall rules
├── variables.tf      # Input variable declarations
├── outputs.tf        # Output values
├── provider.tf       # Azure provider configuration (~> 3.0)
├── backend.tf        # Remote state backend (Azure Storage)
└── terraform.tfvars  # Variable values for deployment
```

---

## Azure Kubernetes Service (AKS)

**File:** `aks.tf`

Deploys a managed Kubernetes cluster with:
- System-assigned managed identity
- RBAC enabled for security
- Azure CNI networking with network policy
- API server access restrictions
- Configurable node pool

### AKS Variables

| Variable               | Type         | Required | Default         | Description                                |
| ---------------------- | ------------ | -------- | --------------- | ------------------------------------------ |
| `cluster_name`         | string       | Yes      | -               | AKS cluster name                           |
| `node_count`           | number       | No       | 1               | Number of nodes in default pool            |
| `vm_size`              | string       | No       | Standard_D2s_v3 | VM size for nodes                          |
| `kubernetes_version`   | string       | No       | 1.33            | Kubernetes version                         |
| `authorized_ip_ranges` | list(string) | No       | ["0.0.0.0/0"]   | Authorized IP ranges for API server access |

### AKS Outputs

| Output               | Description             |
| -------------------- | ----------------------- |
| `cluster_id`         | AKS cluster resource ID |
| `cluster_name`       | AKS cluster name        |
| `resource_group_name`| Resource group name     |

### Connect to AKS

```bash
# Get credentials
az aks get-credentials --resource-group rg-dev-aks --name aks-west-eu

# Verify connection
kubectl get nodes
kubectl get pods -A
```

---

## Azure Container Registry (ACR)

**File:** `acr.tf`

Deploys a private container registry with:
- AKS integration via managed identity (no secrets needed)
- Role assignment granting AKS `AcrPull` permission

### How ACR Connects to AKS

The AKS cluster uses **Managed Identity** to authenticate with ACR - no secrets required.

| Method | How it Works | Secrets? |
|--------|--------------|----------|
| **Managed Identity (what we use)** | Azure IAM grants AKS identity permission to pull images | No secrets needed |
| **Image Pull Secret (old way)** | Kubernetes secret with ACR username/password | Requires secret in each namespace |

**What Terraform creates:**
- ACR with admin access disabled (more secure)
- Role assignment granting the AKS kubelet identity `AcrPull` permission

**In Azure Portal, you can see this under:**
ACR → Access control (IAM) → Role assignments → The AKS identity appears with "AcrPull" role

### ACR Variables

| Variable   | Type   | Required | Default | Description                               |
| ---------- | ------ | -------- | ------- | ----------------------------------------- |
| `acr_name` | string | Yes      | -       | ACR name (globally unique, alphanumeric)  |
| `acr_sku`  | string | No       | Basic   | ACR SKU tier (Basic, Standard, Premium)   |

### ACR Outputs

| Output             | Description          |
| ------------------ | -------------------- |
| `acr_login_server` | ACR login server URL |
| `acr_id`           | ACR resource ID      |

### Using ACR with AKS

```bash
# Login to ACR (for pushing images)
az acr login --name acrwesteu

# Tag and push an image
docker tag myapp:latest acrwesteu.azurecr.io/myapp:v1
docker push acrwesteu.azurecr.io/myapp:v1
```

**In Kubernetes manifests** - no `imagePullSecrets` needed:

```yaml
containers:
  - name: myapp
    image: acrwesteu.azurecr.io/myapp:v1
```

---

## PostgreSQL Flexible Server

**File:** `postgresql.tf`

Deploys Azure Database for PostgreSQL with:
- Flexible Server (latest generation, recommended)
- Application database creation
- Firewall rule allowing Azure services

### PostgreSQL Variables

| Variable                   | Type   | Required | Default         | Description                           |
| -------------------------- | ------ | -------- | --------------- | ------------------------------------- |
| `postgresql_admin_password`| string | Yes      | -               | PostgreSQL admin password (sensitive) |
| `postgresql_admin_username`| string | No       | psqladmin       | PostgreSQL admin username             |
| `postgresql_database_name` | string | Yes      | -               | Name of the database to create        |
| `postgresql_sku_name`      | string | No       | B_Standard_B1ms | PostgreSQL SKU (Burstable tier)       |
| `postgresql_storage_mb`    | number | No       | 32768           | Storage size in MB (32 GB)            |
| `postgresql_version`       | string | No       | 16              | PostgreSQL version                    |

### PostgreSQL Outputs

| Output                     | Description            |
| -------------------------- | ---------------------- |
| `postgresql_server_name`   | PostgreSQL server name |
| `postgresql_fqdn`          | PostgreSQL FQDN        |
| `postgresql_database_name` | Database name          |

### Connecting to PostgreSQL

```bash
# Connection string format
psql "host=<postgresql_fqdn> port=5432 dbname=learning_journal user=psqladmin password=<your-password> sslmode=require"

# Example
psql "host=psql-dev-aks-west-eu.postgres.database.azure.com port=5432 dbname=learning_journal user=psqladmin password=YourSecurePass123 sslmode=require"
```

### Network Access

Current configuration allows Azure services to connect:

```hcl
# Firewall rule (0.0.0.0 = Azure services)
start_ip_address = "0.0.0.0"
end_ip_address   = "0.0.0.0"
```

For **production**, consider using:
- VNet integration (private access)
- Private endpoints
- Specific IP allowlists

---

## Core Variables

These variables are shared across all resources:

| Variable          | Type   | Required | Default | Description                        |
| ----------------- | ------ | -------- | ------- | ---------------------------------- |
| `location`        | string | Yes      | -       | Azure region (e.g., "West Europe") |
| `environment`     | string | Yes      | -       | Environment name (dev, prod, etc.) |
| `subscription_id` | string | Yes      | -       | Azure Subscription ID              |

---

## Security Features

The AKS cluster includes security hardening based on Trivy/tfsec recommendations:

| Feature                       | Description                                                  | Reference    |
| ----------------------------- | ------------------------------------------------------------ | ------------ |
| **RBAC Enabled**              | Role-Based Access Control for cluster access management      | AVD-AZU-0042 |
| **API Server IP Restriction** | Limits API server access to authorized IP ranges             | AVD-AZU-0041 |
| **Network Policy**            | Azure CNI with network policy for pod-to-pod traffic control | AVD-AZU-0043 |

### Restricting API Server Access (Production)

For production environments, restrict `authorized_ip_ranges` to specific IPs:

```hcl
# In terraform.tfvars
authorized_ip_ranges = [
  "203.0.113.0/24",    # Office network
  "198.51.100.50/32"   # VPN gateway
]
```

> **Note**: The default `["0.0.0.0/0"]` allows all IPs for lab convenience. Always restrict this in production.

---

## CI/CD Pipeline

The GitHub Actions pipeline (`.github/workflows/infra-pipeline.yml`) supports two modes.

### Triggers

| Trigger          | When                                              |
| ---------------- | ------------------------------------------------- |
| **Push**         | Changes to `infra-terraform/` on main/master      |
| **Pull Request** | PRs targeting main/master with terraform changes  |
| **Manual**       | Run anytime via "Actions" → "Run workflow" button |

### Running Manually

1. Go to **Actions** tab in GitHub
2. Select **Infrastructure Pipeline**
3. Click **Run workflow**
4. Optionally specify a Terraform version (default: 1.14.4)
5. Click **Run workflow**

### Terraform Version

The pipeline uses Terraform **1.14.4** by default. To change:

- **Manual runs**: Specify version in the workflow dispatch input
- **All runs**: Update `TF_VERSION` in the workflow file

### Pipeline Modes

| Mode                    | Azure Credentials | What Runs                          |
| ----------------------- | ----------------- | ---------------------------------- |
| **Scan Only** (default) | Not needed        | Security scan + Terraform validate |
| **Full Deploy**         | Required          | Scan + Validate + Plan + Apply     |

### Pipeline Architecture

```
┌─────────────────┐     ┌─────────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Security Scan  │────▶│ Terraform Validate  │────▶│ Terraform Plan  │────▶│ Terraform Apply │
│  (Trivy + tfsec)│     │ (fmt + validate)    │     │  (conditional)  │     │  (conditional)  │
│                 │     │                     │     │                 │     │                 │
│ No Azure needed │     │   No Azure needed   │     │  Needs secrets  │     │  Needs secrets  │
└─────────────────┘     └─────────────────────┘     └─────────────────┘     └─────────────────┘
        ▼                        ▼                          ▼                       ▼
   ALWAYS RUNS              ALWAYS RUNS              ENABLE_AZURE_DEPLOY=true only
```

### Enabling Azure Deployment

To enable Plan/Apply stages:

1. Go to **Repository Settings** → **Secrets and variables** → **Actions** → **Variables**
2. Add variable: `ENABLE_AZURE_DEPLOY` = `true`
3. Configure required secrets (see below)

### Required GitHub Secrets (for full deployment)

| Secret                      | Description                           |
| --------------------------- | ------------------------------------- |
| `ARM_CLIENT_ID`             | Azure Service Principal Client ID     |
| `ARM_CLIENT_SECRET`         | Azure Service Principal Client Secret |
| `ARM_SUBSCRIPTION_ID`       | Azure Subscription ID                 |
| `ARM_TENANT_ID`             | Azure Tenant ID                       |
| `BACKEND_RESOURCE_GROUP`    | Resource group for state storage      |
| `BACKEND_STORAGE_ACCOUNT`   | Storage account name for state        |
| `BACKEND_CONTAINER_NAME`    | Blob container name                   |
| `POSTGRESQL_ADMIN_PASSWORD` | PostgreSQL admin password             |

### Security Scanners

The pipeline runs two security scanners:

1. **Trivy** - Scans for misconfigurations (CRITICAL/HIGH severity)
2. **tfsec** - Terraform-specific security scanner (soft fail mode)

---

## Remote State Backend

For team collaboration, use Azure Blob Storage for Terraform state.

### Create Backend Storage

```bash
# Create resource group
az group create --name rg-terraform-state --location "West Europe"

# Create storage account (name must be globally unique)
az storage account create \
  --name tfstateYOURUNIQUE \
  --resource-group rg-terraform-state \
  --sku Standard_LRS

# Create blob container
az storage container create \
  --name tfstate \
  --account-name tfstateYOURUNIQUE
```

### Update backend.tf

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstateYOURUNIQUE"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
```

---

## Creating Azure Service Principal

For CI/CD authentication (if you have IAM access):

### Via Azure Portal

1. Go to **Microsoft Entra ID** → **App registrations** → **+ New registration**
2. Create app, note the **Client ID** and **Tenant ID**
3. Go to **Certificates & secrets** → **+ New client secret**
4. Copy the secret value immediately
5. Go to **Subscriptions** → your subscription → **Access control (IAM)**
6. Add **Contributor** role to your app

### Via Azure CLI

```bash
az ad sp create-for-rbac --name "github-terraform" \
  --role contributor \
  --scopes /subscriptions/<subscription-id>
```

---

## Outputs

After deployment, Terraform outputs:

| Output                     | Description                    |
| -------------------------- | ------------------------------ |
| `cluster_id`               | AKS cluster resource ID        |
| `cluster_name`             | AKS cluster name               |
| `resource_group_name`      | Resource group name            |
| `acr_login_server`         | ACR login server URL           |
| `acr_id`                   | ACR resource ID                |
| `postgresql_server_name`   | PostgreSQL server name         |
| `postgresql_fqdn`          | PostgreSQL FQDN                |
| `postgresql_database_name` | PostgreSQL database name       |

---

## Cleanup

```bash
# Destroy all resources
terraform destroy

# Or via Azure CLI
az group delete --name rg-dev-aks --yes --no-wait
```

---

## Troubleshooting

### Authentication Issues

```bash
az login
az account list --output table
az account set --subscription <subscription-id>
```

### Kubernetes Version

List available versions:

```bash
az aks get-versions --location "West Europe" --output table
```

### State Lock Issues

If state is locked:

```bash
terraform force-unlock <lock-id>
```

---

## Resources Links

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Azure Container Registry](https://docs.microsoft.com/en-us/azure/container-registry/)
- [Azure Database for PostgreSQL](https://docs.microsoft.com/en-us/azure/postgresql/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/)
