#!/bin/bash

# Complete Observability System - Traffic Generation Script
# Generates sample traffic to populate metrics, logs, and traces

set -e

API_URL="${API_URL:-http://localhost:5000}"
DURATION="${DURATION:-300}"  # seconds
INTERVAL="${INTERVAL:-2}"    # seconds between requests

echo "=========================================="
echo "Complete Observability System - Traffic Generator"
echo "=========================================="
echo "API URL: $API_URL"
echo "Duration: $DURATION seconds"
echo "Interval: $INTERVAL seconds"
echo "=========================================="

# Function to check if API is available
check_api() {
    echo "Checking API availability..."
    for i in {1..30}; do
        if curl -s "$API_URL/health" > /dev/null 2>&1; then
            echo "✓ API is ready"
            return 0
        fi
        echo "  Waiting for API... ($i/30)"
        sleep 1
    done
    echo "✗ API is not responding, exiting"
    return 1
}

# Function to make GET requests to users endpoint
make_get_requests() {
    echo ""
    echo "Starting GET requests to /api/users..."
    local end=$((SECONDS + DURATION))
    local count=0
    
    while [ $SECONDS -lt $end ]; do
        for user_id in 1 2 3; do
            if [ $SECONDS -lt $end ]; then
                response=$(curl -s -w "\n%{http_code}" "$API_URL/api/users/$user_id")
                http_code=$(echo "$response" | tail -n 1)
                count=$((count + 1))
                echo "[$(date +'%H:%M:%S')] GET /api/users/$user_id - HTTP $http_code ($count requests)"
                sleep "$INTERVAL"
            fi
        done
    done
}

# Function to make POST requests to process endpoint
make_post_requests() {
    echo ""
    echo "Starting POST requests to /api/process..."
    local end=$((SECONDS + DURATION))
    local count=0
    
    while [ $SECONDS -lt $end ]; do
        payload="{\"operation\": \"analyze\", \"data\": \"sample_data_$count\"}"
        response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/api/process" \
            -H "Content-Type: application/json" \
            -d "$payload")
        http_code=$(echo "$response" | tail -n 1)
        count=$((count + 1))
        echo "[$(date +'%H:%M:%S')] POST /api/process - HTTP $http_code ($count requests)"
        sleep $((INTERVAL * 2))
    done
}

# Function to simulate errors
simulate_errors() {
    echo ""
    echo "Starting error simulation..."
    local end=$((SECONDS + DURATION))
    local count=0
    
    while [ $SECONDS -lt $end ]; do
        response=$(curl -s -w "\n%{http_code}" "$API_URL/api/simulate-error")
        http_code=$(echo "$response" | tail -n 1)
        count=$((count + 1))
        echo "[$(date +'%H:%M:%S')] GET /api/simulate-error - HTTP $http_code ($count errors)"
        sleep $((INTERVAL * 8))  # Less frequent errors
    done
}

# Function to fetch metrics
show_metrics() {
    echo ""
    echo "Sample Prometheus Metrics:"
    echo "=========================================="
    
    metrics=$(curl -s "$API_URL/metrics" | grep "^app_")
    echo "$metrics" | head -20
    
    echo ""
    echo "=========================================="
}

# Main execution
main() {
    check_api || exit 1
    
    echo ""
    echo "Running traffic generation for $DURATION seconds..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    # Run requests in parallel
    make_get_requests &
    GET_PID=$!
    
    sleep 3
    
    make_post_requests &
    POST_PID=$!
    
    sleep 3
    
    simulate_errors &
    ERROR_PID=$!
    
    # Wait for all background processes
    wait $GET_PID $POST_PID $ERROR_PID 2>/dev/null || true
    
    echo ""
    echo "=========================================="
    echo "Traffic generation completed!"
    echo "=========================================="
    
    # Show sample metrics
    show_metrics
    
    echo ""
    echo "Next steps:"
    echo "1. Visit Grafana: http://localhost:3000"
    echo "2. Check metrics dashboard: Application Metrics Dashboard"
    echo "3. View logs: Logs Dashboard"
    echo "4. Check traces: http://localhost:16686"
    echo ""
}

# Trap SIGINT to cleanup
trap 'echo ""; echo "Stopping traffic generation..."; kill $GET_PID $POST_PID $ERROR_PID 2>/dev/null; exit 0' INT

# Run main function
main
