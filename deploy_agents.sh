#!/bin/bash

# Enable strict error handling
set -euo pipefail
IFS=$'\n\t'

# Environment Variables
export INITIAL_CLIENT_COUNT=4
export INITIAL_PARTNER_COUNT=10
export AGENT_PAIRS=3  # Combining complementary agents

# Configuration
readonly LOG_FILE="./deploy_agents.log"
readonly REQUIRED_MEMORY=2560  # MB per agent
readonly REQUIRED_CPU=1        # CPU cores per agent
readonly MAX_RETRIES=3

# Logging function
log() {
    local level=$1
    shift
    local message=$*
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Ensure log message gets printed even if log file write fails
    echo "[$timestamp] [$level] $message"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

# Resource check function
check_resources() {
    local pair_name=$1
    local required_mem=$((REQUIRED_MEMORY * 2))  # Double for pair
    local required_cpu=$((REQUIRED_CPU * 2))     # Double for pair
    
    log "INFO" "Checking resources for pair: $pair_name"
    
    # Get available resources (example command - adjust based on your environment)
    local available_mem
    available_mem=$(free -m | awk '/^Mem:/{print $4}')
    local available_cpu
    available_cpu=$(nproc --all)
    
    if [ "$available_mem" -lt "$required_mem" ] || [ "$available_cpu" -lt "$required_cpu" ]; then
        log "ERROR" "Insufficient resources for $pair_name. Required: ${required_mem}MB RAM, ${required_cpu} CPU. Available: ${available_mem}MB RAM, ${available_cpu} CPU"
        return 1
    fi
    return 0
}

# Deployment function for a single agent
deploy_single_agent() {
    local agent_name=$1
    local retry_count=0
    
    while [ "$retry_count" -lt "$MAX_RETRIES" ]; do
        if gcloud ai models deploy "$agent_name" --region=us-west1; then
            log "INFO" "Successfully deployed $agent_name"
            return 0
        fi
        retry_count=$((retry_count + 1))
        log "WARN" "Retry $retry_count/$MAX_RETRIES for $agent_name"
        sleep 5
    done
    
    log "ERROR" "Failed to deploy $agent_name after $MAX_RETRIES attempts"
    return 1
}

# Status check function
check_deployment_status() {
    local agent_name=$1
    if gcloud ai models describe "$agent_name" --region=us-west1 | grep -q "state: DEPLOYED"; then
        log "INFO" "$agent_name is successfully deployed and running"
        return 0
    fi
    log "ERROR" "$agent_name deployment verification failed"
    return 1
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up resources..."
    # Add cleanup logic here
}

# Main deployment function
deploy_agents() {
    log "INFO" "🤖 Deploying Essential Agent Pairs 🤖"
    
    declare -A AGENT_PAIRS=(
        ["research_intelligence"]="dr_lucy,dr_claude"
        ["security_governance"]="dr_grant,dr_burby"
        ["relationship_communication"]="dr_sabina,dr_match"
    )
    
    # Trap cleanup on script exit
    trap cleanup EXIT
    
    for pair_name in "${!AGENT_PAIRS[@]}"; do
        log "INFO" "Processing pair: $pair_name"
        
        # Check resources before deployment
        if ! check_resources "$pair_name"; then
            log "ERROR" "Resource check failed for $pair_name. Skipping deployment."
            continue
        fi
        
        # Get individual agents from the pair
        IFS=',' read -r agent1 agent2 <<< "${AGENT_PAIRS[$pair_name]}"
        
        # Deploy both agents
        log "INFO" "Deploying agent pair: $agent1 and $agent2"
        
        if ! deploy_single_agent "$agent1"; then
            log "ERROR" "Failed to deploy $agent1. Skipping pair."
            continue
        fi
        
        if ! deploy_single_agent "$agent2"; then
            log "ERROR" "Failed to deploy $agent2. Rolling back $agent1."
            gcloud ai models delete "$agent1" --region=us-west1 --quiet
            continue
        fi
        
        # Verify deployment status
        if check_deployment_status "$agent1" && check_deployment_status "$agent2"; then
            log "INFO" "✅ Successfully deployed and verified pair: $pair_name"
        else
            log "ERROR" "❌ Deployment verification failed for pair: $pair_name"
            # Initiate rollback
            gcloud ai models delete "$agent1" --region=us-west1 --quiet
            gcloud ai models delete "$agent2" --region=us-west1 --quiet
        fi
    done
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_agents
fi

