#!/bin/bash
# =============================================================================
# Amazon Connect Analytics Data Lake - Table Metadata Export Script
# =============================================================================
# This script exports comprehensive metadata for all Amazon Connect Analytics tables
# from the consumer account using resource links, and saves it to a CSV file.
#
# USAGE:
#   ./export_table_metadata.sh
#
# OUTPUT:
#   - amazon_connect_tables_metadata.csv (comprehensive table metadata)
#   - Console output with progress and summary
#
# REQUIREMENTS:
#   - AWS CLI configured with appropriate permissions
#   - Access to consumer account with resource links
#   - jq (JSON processor) - optional, script will work without it
#
# TABLES COVERED:
#   All 32 Amazon Connect Analytics tables including:
#   - Agent & Queue Statistics (5 tables)
#   - Contact Records (4 tables) 
#   - Contact Lens (1 table)
#   - Bot Analytics (3 tables)
#   - Configuration (3 tables)
#   - Forecasting (4 tables)
#   - Outbound Campaigns (1 table)
#   - Staff Scheduling (11 tables)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# CONFIGURATION - Update these values as needed
# =============================================================================

# Consumer account database (where resource links are created)
CONSUMER_DATABASE="connect_analytics_consumer"

# AWS region
REGION="ap-southeast-2"

# Output file
OUTPUT_FILE="amazon_connect_tables_metadata.csv"

# =============================================================================
# AMAZON CONNECT ANALYTICS TABLES - Update this list as needed
# =============================================================================
# This list includes all 32 standard Amazon Connect Analytics tables
# You can add/remove tables by modifying this array

TABLES=(
    # Agent & Queue Statistics
    "agent_queue_statistic_record"
    "agent_statistic_record"
    "agent_metrics"
    "contact_statistic_record"
    "queue_metrics"
    
    # Contact Records
    "contacts_record"
    "contacts"
    "contact_flow_events"
    "contact_evaluation_record"
    
    # Contact Lens
    "contact_lens_conversational_analytics"
    
    # Bot Analytics
    "bot_conversations"
    "bot_intents"
    "bot_slots"
    
    # Configuration
    "agent_hierarchy_groups"
    "routing_profiles"
    "users"
    
    # Forecasting
    "forecast_groups"
    "long_term_forecasts"
    "short_term_forecasts"
    "intraday_forecasts"
    
    # Outbound Campaigns
    "outbound_campaign_events"
    
    # Staff Scheduling
    "staff_scheduling_profile"
    "shift_activities"
    "shift_profiles"
    "staffing_groups"
    "staffing_group_forecast_groups"
    "staffing_group_supervisors"
    "staff_shifts"
    "staff_shift_activities"
    "staff_timeoff_balance_changes"
    "staff_timeoffs"
    "staff_timeoff_intervals"
)

# =============================================================================
# SCRIPT FUNCTIONS - Do not modify below this line
# =============================================================================

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓ SUCCESS:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
}

print_error() {
    echo -e "${RED}✗ ERROR:${NC} $1"
}

print_progress() {
    echo -e "${YELLOW}→${NC} $1"
}

# Check if jq is available
check_dependencies() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    if command -v jq &> /dev/null; then
        JQ_AVAILABLE=true
        print_info "jq is available - using for JSON parsing"
    else
        JQ_AVAILABLE=false
        print_warning "jq not found - using built-in JSON parsing"
    fi
}

# Validate AWS credentials and access
validate_aws_access() {
    print_info "Validating AWS credentials and access..."
    
    # Check if we can authenticate
    if ! aws sts get-caller-identity --region "$REGION" &> /dev/null; then
        print_error "AWS authentication failed. Please check your credentials."
        exit 1
    fi
    
    # Check if database exists
    if ! aws glue get-database --name "$CONSUMER_DATABASE" --region "$REGION" &> /dev/null; then
        print_error "Database '$CONSUMER_DATABASE' not found in region '$REGION'"
        print_error "Please ensure the consumer account is properly set up with resource links."
        exit 1
    fi
    
    print_success "AWS access validated successfully"
}

# Initialize CSV file with headers
initialize_csv() {
    print_info "Initializing CSV file: $OUTPUT_FILE"
    
    # Create CSV header
    cat > "$OUTPUT_FILE" << 'EOF'
Table Name,Column Name,Data Type,Description,Is Partition Key,Table Location,Table Type,Last Updated,Table Description
EOF
    
    print_success "CSV file initialized with headers"
}

# Extract table metadata using AWS CLI
extract_table_metadata() {
    local table_name="$1"
    local resource_link_name="${table_name}_link"
    
    print_progress "Processing table: $table_name (resource link: $resource_link_name)"
    
    # Get table metadata via resource link
    local table_json
    table_json=$(aws glue get-table \
        --database-name "$CONSUMER_DATABASE" \
        --name "$resource_link_name" \
        --region "$REGION" \
        --output json 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$table_json" ]; then
        print_warning "Could not retrieve metadata for table: $table_name"
        return 1
    fi
    
    # Extract table-level information
    local table_location table_type last_updated table_description
    if [ "$JQ_AVAILABLE" = true ]; then
        table_location=$(echo "$table_json" | jq -r '.Table.StorageDescriptor.Location // "Unknown"')
        table_type=$(echo "$table_json" | jq -r '.Table.TableType // "Unknown"')
        last_updated=$(echo "$table_json" | jq -r '.Table.UpdateTime // "Unknown"')
        table_description=$(echo "$table_json" | jq -r '.Table.Description // ""')
    else
        # Fallback parsing without jq
        table_location=$(echo "$table_json" | grep -o '"Location":[^,]*' | cut -d'"' -f4 || echo "Unknown")
        table_type=$(echo "$table_json" | grep -o '"TableType":[^,]*' | cut -d'"' -f4 || echo "Unknown")
        last_updated=$(echo "$table_json" | grep -o '"UpdateTime":[^,]*' | cut -d'"' -f4 || echo "Unknown")
        table_description=$(echo "$table_json" | grep -o '"Description":"[^"]*"' | cut -d'"' -f4 || echo "")
    fi
    
    # Extract partition keys
    local partition_keys=""
    if [ "$JQ_AVAILABLE" = true ]; then
        partition_keys=$(echo "$table_json" | jq -r '.Table.PartitionKeys[].Name // empty' | tr '\n' ',' | sed 's/,$//')
    else
        partition_keys=$(echo "$table_json" | grep -A 10 '"PartitionKeys"' | grep '"Name"' | cut -d'"' -f4 | tr '\n' ',' | sed 's/,$//')
    fi
    
    # Process columns - use temporary file to avoid subshell issues
    local temp_file="/tmp/columns_$$.csv"
    
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$table_json" | jq -r '.Table.StorageDescriptor.Columns[] | [.Name, .Type, .Comment] | @csv' > "$temp_file"
    else
        # Fallback parsing without jq - extract columns using sed/awk
        echo "$table_json" | sed -n '/"Columns":/,/]/p' | sed '1d;$d' | while IFS= read -r column_line; do
            # Skip empty lines and brackets
            if [[ "$column_line" =~ ^[[:space:]}]*$ ]] || [[ "$column_line" =~ ^[[:space:]]*[\[]*$ ]]; then
                continue
            fi
            
            # Extract column name
            column_name=$(echo "$column_line" | grep -o '"Name"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            if [ -z "$column_name" ]; then
                continue
            fi
            
            # Extract column type
            column_type=$(echo "$column_line" | grep -o '"Type"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            if [ -z "$column_type" ]; then
                column_type="Unknown"
            fi
            
            # Extract column comment
            column_comment=$(echo "$column_line" | grep -o '"Comment"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
            if [ -z "$column_comment" ]; then
                column_comment=""
            fi
            
            # Output CSV line
            echo "\"$column_name\",\"$column_type\",\"$column_comment\""
        done > "$temp_file"
    fi
    
    # Process columns from temporary file
    while IFS= read -r column_line; do
        # Skip empty lines
        [ -z "$column_line" ] && continue
        
        # Parse column info
        column_name=$(echo "$column_line" | cut -d',' -f1 | tr -d '"')
        column_type=$(echo "$column_line" | cut -d',' -f2 | tr -d '"')
        column_comment=$(echo "$column_line" | cut -d',' -f3 | tr -d '"')
        
        # Check if this is a partition key
        is_partition_key="NO"
        if [[ "$partition_keys" == *"$column_name"* ]]; then
            is_partition_key="YES"
        fi
        
        # Write to CSV
        echo "\"$table_name\",\"$column_name\",\"$column_type\",\"$column_comment\",\"$is_partition_key\",\"$table_location\",\"$table_type\",\"$last_updated\",\"$table_description\"" >> "$OUTPUT_FILE"
    done < "$temp_file"
    
    # Clean up temporary file
    rm -f "$temp_file"
    
    print_success "Processed table: $table_name"
    return 0
}

# Generate summary report
generate_summary() {
    local total_tables=${#TABLES[@]}
    local processed_tables line_count
    
    if [ -f "$OUTPUT_FILE" ]; then
        # Count lines minus header
        line_count=$(wc -l < "$OUTPUT_FILE")
        processed_tables=$((line_count - 1))
    else
        processed_tables=0
    fi
    
    print_header "Export Summary"
    echo -e "Total tables requested: ${GREEN}$total_tables${NC}"
    echo -e "Tables processed: ${GREEN}$processed_tables${NC}"
    echo -e "Output file: ${GREEN}$OUTPUT_FILE${NC}"
    echo -e "File size: ${GREEN}$(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1 || echo "Unknown")${NC}"
    
    if [ "$processed_tables" -eq "$total_tables" ]; then
        print_success "All tables processed successfully!"
    else
        print_warning "Some tables may not have been processed. Check the output above for warnings."
    fi
    
    # Show first few lines of the CSV
    echo -e "\n${BLUE}Sample output (first 5 lines):${NC}"
    head -5 "$OUTPUT_FILE" 2>/dev/null || print_warning "Could not display sample output"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    print_header "Amazon Connect Analytics Table Metadata Export"
    print_info "Starting metadata export for ${#TABLES[@]} tables..."
    print_info "Target database: $CONSUMER_DATABASE"
    print_info "Target region: $REGION"
    print_info "Output file: $OUTPUT_FILE"
    
    # Check dependencies
    check_dependencies
    
    # Validate AWS access
    validate_aws_access
    
    # Initialize CSV file
    initialize_csv
    
    # Process each table
    local success_count=0
    local total_count=${#TABLES[@]}
    
    for table in "${TABLES[@]}"; do
        if extract_table_metadata "$table"; then
            ((success_count++))
        fi
    done
    
    # Generate summary
    generate_summary
    
    # Final status
    if [ "$success_count" -eq "$total_count" ]; then
        echo -e "\n${GREEN}🎉 Export completed successfully!${NC}"
        echo -e "${GREEN}📄 Metadata saved to: $OUTPUT_FILE${NC}"
        echo -e "${BLUE}💡 You can now reference this file in your README.md${NC}"
        exit 0
    else
        echo -e "\n${YELLOW}⚠ Export completed with some issues.${NC}"
        echo -e "${YELLOW}📊 Success rate: $success_count/$total_count tables processed${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
