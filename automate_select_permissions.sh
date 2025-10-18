#!/bin/bash

# =============================================================================
# Automated Cross-Account SELECT Permissions Script
# =============================================================================
# This script automates the granting of SELECT permissions on target tables
# in the producer account for cross-account Amazon Connect analytics access.
#
# USAGE:
#   ./automate_select_permissions.sh [--test] [--dry-run]
#
# OPTIONS:
#   --test     : Test mode - only validate current permissions
#   --dry-run  : Show commands that would be executed without running them
#
# PREREQUISITES:
#   1. AWS CLI configured with credentials for BOTH accounts
#   2. Lake Formation admin permissions in producer account
#   3. Resource links already created in consumer account
#   4. Lambda execution role exists in consumer account

set -euo pipefail

# Configuration
PRODUCER_ACCOUNT_ID="502851453563"
CONSUMER_ACCOUNT_ID="657416661258"
REGION="ap-southeast-2"
PRODUCER_DATABASE="connect_datalake"
CONSUMER_DATABASE="connect_analytics_consumer"
LAMBDA_ROLE_NAME="connect-analytics-lambda-execution-role"

# Script modes
TEST_MODE=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--test] [--dry-run]"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Execute AWS command with optional dry-run
execute_aws() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $cmd"
        return 0
    else
        log_info "Executing: $description"
        if eval "$cmd"; then
            log_success "Command completed successfully"
            return 0
        else
            log_error "Command failed"
            return 1
        fi
    fi
}

# Check if resource link exists
check_resource_link() {
    local table_name="$1"
    local link_name="${table_name}_link"
    
    log_info "Checking resource link: $link_name"
    
    if aws glue get-table \
        --database-name "$CONSUMER_DATABASE" \
        --name "$link_name" \
        --query "Table.Name" \
        --output text 2>/dev/null | grep -q "$link_name"; then
        log_success "Resource link exists: $link_name"
        return 0
    else
        log_warning "Resource link not found: $link_name"
        return 1
    fi
}

# Validate current permissions
validate_permissions() {
    log_info "=== Validating Current Permissions ==="
    
    local lambda_role_arn="arn:aws:iam::${CONSUMER_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    echo "Current AWS Identity:"
    aws sts get-caller-identity --query "Account" --output text
    echo ""
    
    echo "Resource Links in Consumer Account:"
    aws glue get-tables \
        --database-name "$CONSUMER_DATABASE" \
        --query "TableList[?contains(Name, '_link')].Name" \
        --output table
    echo ""
    
    if [[ "$TEST_MODE" == "true" ]]; then
        echo "=== Current Lake Formation Permissions ==="
        
        # Check permissions on a sample resource link
        local sample_link="users_link"
        if aws glue get-table \
            --database-name "$CONSUMER_DATABASE" \
            --name "$sample_link" \
            --query "Table.Name" \
            --output text 2>/dev/null | grep -q "$sample_link"; then
            
            echo "Permissions on $sample_link:"
            aws lakeformation list-permissions \
                --principal "DataLakePrincipalIdentifier=$lambda_role_arn" \
                --resource '{"Table":{"DatabaseName":"'$CONSUMER_DATABASE'","Name":"'$sample_link'"}}' \
                --query "PrincipalResourcePermissions[].Permission" \
                --output table 2>/dev/null || echo "No permissions found"
        fi
    fi
}

# Grant SELECT permissions on producer target tables
grant_producer_select_permissions() {
    log_info "=== Granting SELECT Permissions on Producer Target Tables ==="
    
    local lambda_role_arn="arn:aws:iam::${CONSUMER_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    # Key tables that need SELECT permissions
    local tables=(
        "users"
        "contacts"
        "agent_metrics"
        "queue_metrics"
        "agent_hierarchy_groups"
        "routing_profiles"
        "contacts_record"
        "contact_flow_events"
        "contact_statistic_record"
        "agent_statistic_record"
    )
    
    for table in "${tables[@]}"; do
        log_info "Processing table: $table"
        
        # Check if resource link exists
        if check_resource_link "$table"; then
            # Grant SELECT on target table in producer account
            local cmd="aws lakeformation grant-permissions \
                --region '$REGION' \
                --catalog-id '$PRODUCER_ACCOUNT_ID' \
                --principal 'DataLakePrincipalIdentifier=$lambda_role_arn' \
                --permissions 'SELECT' \
                --resource '{\"Table\":{\"CatalogId\":\"$PRODUCER_ACCOUNT_ID\",\"DatabaseName\":\"$PRODUCER_DATABASE\",\"Name\":\"$table\"}}'"
            
            execute_aws "$cmd" "Grant SELECT on $table (producer account)"
            
            # Small delay to avoid rate limiting
            sleep 1
        else
            log_warning "Skipping $table - resource link not found"
        fi
    done
}

# Grant DESCRIBE permissions on consumer resource links
grant_consumer_describe_permissions() {
    log_info "=== Granting DESCRIBE Permissions on Consumer Resource Links ==="
    
    local lambda_role_arn="arn:aws:iam::${CONSUMER_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    # Key resource links that need DESCRIBE permissions
    local tables=(
        "users"
        "contacts"
        "agent_metrics"
        "queue_metrics"
        "agent_hierarchy_groups"
        "routing_profiles"
        "contacts_record"
        "contact_flow_events"
        "contact_statistic_record"
        "agent_statistic_record"
    )
    
    for table in "${tables[@]}"; do
        local link_name="${table}_link"
        
        if check_resource_link "$table"; then
            # Grant DESCRIBE on resource link in consumer account
            local cmd="aws lakeformation grant-permissions \
                --region '$REGION' \
                --catalog-id '$CONSUMER_ACCOUNT_ID' \
                --principal 'DataLakePrincipalIdentifier=$lambda_role_arn' \
                --permissions 'DESCRIBE' \
                --resource '{\"Table\":{\"CatalogId\":\"$CONSUMER_ACCOUNT_ID\",\"DatabaseName\":\"$CONSUMER_DATABASE\",\"Name\":\"$link_name\"}}'"
            
            execute_aws "$cmd" "Grant DESCRIBE on $link_name (consumer account)"
            
            # Small delay to avoid rate limiting
            sleep 1
        fi
    done
}

# Test cross-account access
test_cross_account_access() {
    log_info "=== Testing Cross-Account Access ==="
    
    # Test query using resource link
    local test_query="SELECT COUNT(*) FROM ${CONSUMER_DATABASE}.users_link LIMIT 5"
    
    log_info "Testing query: $test_query"
    
    if aws athena start-query-execution \
        --work-group "connect_analytics_workgroup" \
        --query-string "$test_query" \
        --query "QueryExecutionId" \
        --output text 2>/dev/null; then
        
        log_success "Cross-account query initiated successfully"
        
        # Wait a moment and check results
        sleep 2
        local query_id=$(aws athena list-query-executions \
            --work-group "connect_analytics_workgroup" \
            --query "QueryExecutionIds[0]" \
            --output text 2>/dev/null)
        
        if [[ -n "$query_id" && "$query_id" != "None" ]]; then
            log_info "Query ID: $query_id"
            log_info "Check results with: aws athena get-query-results --query-execution-id $query_id"
        fi
    else
        log_error "Cross-account query failed"
    fi
}

# Main execution
main() {
    echo "=============================================================================="
    echo "Automated Cross-Account SELECT Permissions Script"
    echo "=============================================================================="
    echo "Date: $(date)"
    echo "Producer Account: $PRODUCER_ACCOUNT_ID"
    echo "Consumer Account: $CONSUMER_ACCOUNT_ID"
    echo "Region: $REGION"
    echo "Test Mode: $TEST_MODE"
    echo "Dry Run: $DRY_RUN"
    echo "=============================================================================="
    echo ""
    
    # Validate current state
    validate_permissions
    echo ""
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log_info "Test mode complete - no changes made"
        exit 0
    fi
    
    # Grant permissions
    if [[ "$DRY_RUN" == "false" ]]; then
        log_warning "This will modify Lake Formation permissions"
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi
    
    # Execute permission grants
    grant_producer_select_permissions
    echo ""
    
    grant_consumer_describe_permissions
    echo ""
    
    # Test access if not dry run
    if [[ "$DRY_RUN" == "false" ]]; then
        test_cross_account_access
        echo ""
        
        log_success "Automated permission setup complete!"
        log_info "Verify permissions with: aws lakeformation list-permissions --principal 'DataLakePrincipalIdentifier=arn:aws:iam::${CONSUMER_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}'"
    else
        log_info "Dry run complete - no changes made"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found"
        exit 1
    fi
    
    # Check current account
    local current_account=$(aws sts get-caller-identity --query "Account" --output text)
    if [[ "$current_account" != "$CONSUMER_ACCOUNT_ID" ]]; then
        log_warning "Current account ($current_account) is not the consumer account ($CONSUMER_ACCOUNT_ID)"
        log_warning "Some operations may fail due to cross-account restrictions"
    fi
    
    # Check if Lambda role exists
    if ! aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        log_error "Lambda role not found: $LAMBDA_ROLE_NAME"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Run prerequisites check
check_prerequisites
echo ""

# Execute main function
main "$@"
