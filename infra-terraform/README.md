# Chapter 1: Infrastructure as Code (IaaC)

> **Cybersteps Module 3 - Advanced Kubernetes Learning Series**

This chapter covers deploying Azure Kubernetes Service (AKS) using Terraform, with a CI/CD pipeline for security scanning and validation.

---

## Important Note for Students

> **Lab Environment Limitation**: In this training environment, students do not have access to Azure IAM (Identity and Access Management) to create Service Principals. Therefore, **Terraform will be deployed manually** using local Azure CLI authentication (`az login`).
>
> **In a real-world production scenario**, you would:
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
- **System Identity**: System-assigned managed identity for the cluster
- **PostgreSQL Flexible Server**: Azure Database for PostgreSQL with firewall rules

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- An Azure subscription

---

## Quick Start (Local Deployment)

### 1. Authenticate with Azure

```bash
az login
az account set --subscription <subscription-id>
```

### 2. Initialize and Deploy

```bash
cd infra-terraform

# Initialize Terraform (skip remote backend for local dev)
terraform init -backend=false

# Review changes
terraform plan -var="postgresql_admin_password=YourSecurePass123!"

# Apply
terraform apply -var="postgresql_admin_password=YourSecurePass123!"
```

### 3. Connect to Your Cluster

```bash
az aks get-credentials --resource-group rg-dev-aks --name aks-west-eu
kubectl get nodes
```

---

## Project Structure

```
infra-terraform/
├── main.tf           # Resource definitions (RG, AKS, PostgreSQL)
├── variables.tf      # Input variable declarations
├── outputs.tf        # Output values
├── provider.tf       # Azure provider configuration (~> 3.0)
├── backend.tf        # Remote state backend (Azure Storage)
└── terraform.tfvars  # Variable values for deployment
```

---

## Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `location` | string | Yes | - | Azure region (e.g., "West Europe") |
| `environment` | string | Yes | - | Environment name (e.g., "dev", "prod") |
| `cluster_name` | string | Yes | - | AKS cluster name |
| `subscription_id` | string | Yes | - | Azure Subscription ID |
| `node_count` | number | No | 1 | Number of nodes |
| `vm_size` | string | No | Standard_D2s_v3 | VM size for nodes |
| `kubernetes_version` | string | No | 1.33 | Kubernetes version |
| `authorized_ip_ranges` | list(string) | No | ["0.0.0.0/0"] | Authorized IP ranges for API server access |
| `postgresql_admin_password` | string | Yes | - | PostgreSQL admin password (sensitive) |
| `postgresql_admin_username` | string | No | psqladmin | PostgreSQL admin username |

---

## Security Features

The AKS cluster includes security hardening based on Trivy/tfsec recommendations:

| Feature | Description | Reference |
|---------|-------------|-----------|
| **RBAC Enabled** | Role-Based Access Control for cluster access management | AVD-AZU-0042 |
| **API Server IP Restriction** | Limits API server access to authorized IP ranges | AVD-AZU-0041 |
| **Network Policy** | Azure CNI with network policy for pod-to-pod traffic control | AVD-AZU-0043 |

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

The GitHub Actions pipeline (`.github/workflows/infra-pipeline.yml`) supports two modes:

### Pipeline Modes

| Mode | Azure Credentials | What Runs |
|------|-------------------|-----------|
| **Scan Only** (default) | Not needed | Security scan + Terraform validate |
| **Full Deploy** | Required | Scan + Validate + Plan + Apply |

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

| Secret | Description |
|--------|-------------|
| `ARM_CLIENT_ID` | Azure Service Principal Client ID |
| `ARM_CLIENT_SECRET` | Azure Service Principal Client Secret |
| `ARM_SUBSCRIPTION_ID` | Azure Subscription ID |
| `ARM_TENANT_ID` | Azure Tenant ID |
| `BACKEND_RESOURCE_GROUP` | Resource group for state storage |
| `BACKEND_STORAGE_ACCOUNT` | Storage account name for state |
| `BACKEND_CONTAINER_NAME` | Blob container name |
| `POSTGRESQL_ADMIN_PASSWORD` | PostgreSQL admin password |

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

| Output | Description |
|--------|-------------|
| `cluster_id` | AKS cluster resource ID |
| `cluster_name` | AKS cluster name |
| `resource_group_name` | Resource group name |
| `postgresql_server_name` | PostgreSQL server name |
| `postgresql_fqdn` | PostgreSQL FQDN |

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

## Resources

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/)
