#!/bin/bash

# Complete Observability System - System Information Script
# Shows status of all components

echo "=========================================="
echo "Complete Observability System - Status"
echo "=========================================="
echo ""

# Check if docker-compose is running
echo "🐳 Docker Compose Status:"
echo "=========================================="

docker-compose ps 2>/dev/null || echo "❌ Docker compose not initialized"

echo ""
echo "📊 Service Health Checks:"
echo "=========================================="

# Check each service
check_service() {
    local name=$1
    local url=$2
    local expected_code=$3
    
    if command -v curl &> /dev/null; then
        status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
        if [ "$status" == "$expected_code" ]; then
            echo "✓ $name: OK (HTTP $status)"
        else
            echo "✗ $name: FAILED (HTTP $status)"
        fi
    else
        echo "? $name: Cannot check (curl not available)"
    fi
}

check_service "Application API" "http://localhost:5000/health" "200"
check_service "Prometheus" "http://localhost:9090/-/healthy" "200"
check_service "Grafana" "http://localhost:3000/api/health" "200"
check_service "Loki" "http://localhost:3100/ready" "200"
check_service "Jaeger" "http://localhost:14268/" "200"

echo ""
echo "📈 Resource Usage:"
echo "=========================================="

if command -v docker &> /dev/null; then
    echo "Container CPU and Memory Usage:"
    echo ""
    docker stats --no-stream 2>/dev/null | grep -E "observability|CONTAINER" || echo "No running containers"
else
    echo "Docker not available"
fi

echo ""
echo "🔗 Access URLs:"
echo "=========================================="
echo "Grafana:         http://localhost:3000 (admin/admin)"
echo "Prometheus:      http://localhost:9090"
echo "Jaeger UI:       http://localhost:16686"
echo "Application API: http://localhost:5000"
echo "Loki API:        http://localhost:3100"
echo ""

echo "📚 Documentation:"
echo "=========================================="
echo "README:          ./README.md"
echo "Traffic Script:  ./scripts/generate-traffic.sh"
echo "Configuration:   ./config/"
echo "Dashboards:      ./dashboards/"
echo ""

echo "✅ Setup Complete! Start generating traffic with:"
echo "   bash scripts/generate-traffic.sh"
echo ""
