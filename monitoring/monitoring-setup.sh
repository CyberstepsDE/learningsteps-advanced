#!/bin/bash
# Quick setup script for Prometheus + Grafana monitoring stack
# Run this from the project root directory

set -e

echo "📊 Setting up Prometheus and Grafana monitoring stack..."

# Add Helm repository
echo "Adding prometheus-community Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
echo "Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install kube-prometheus-stack
echo "Installing kube-prometheus-stack (this may take 2-3 minutes)..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --wait

echo ""
echo "✅ Monitoring stack installed successfully!"
echo ""
echo "📝 Access Instructions:"
echo ""
echo "1. Grafana Dashboard:"
echo "   kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "   Then open: http://localhost:3000"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "2. Prometheus UI:"
echo "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "   Then open: http://localhost:9090"
echo ""
echo "3. Your application will be automatically discovered by Prometheus"
echo "   (using prometheus.io/scrape annotations on the service)"
echo ""
