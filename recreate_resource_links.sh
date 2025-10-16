#!/bin/bash

# Script to recreate all resource links with storage_descriptor
# This triggers AWS Glue to auto-populate schemas via RAM/Lake Formation share

# Configuration - Update these values to match your environment
DATABASE="connect_analytics_consumer"
PRODUCER_CATALOG=""  # Set via terraform.tfvars or environment variable
PRODUCER_DATABASE="connect_datalake"

# Get producer account ID from terraform output if not set
if [ -z "$PRODUCER_CATALOG" ]; then
  PRODUCER_CATALOG=$(terraform output -raw producer_account_info 2>/dev/null | grep -oP '"account_id"\s*=\s*"\K[^"]+' || echo "")
fi

# Validate required variables
if [ -z "$PRODUCER_CATALOG" ]; then
  echo "ERROR: PRODUCER_CATALOG not set. Please set it in this script or via environment variable."
  echo "Example: export PRODUCER_CATALOG=111111111111"
  exit 1
fi

# List of all tables
TABLES=(
  "agent_queue_statistic_record"
  "agent_statistic_record"
  "agent_metrics"
  "contact_statistic_record"
  "queue_metrics"
  "contacts_record"
  "contacts"
  "contact_flow_events"
  "contact_evaluation_record"
  "contact_lens_conversational_analytics"
  "bot_conversations"
  "bot_intents"
  "bot_slots"
  "agent_hierarchy_groups"
  "routing_profiles"
  "users"
  "forecast_groups"
  "long_term_forecasts"
  "short_term_forecasts"
  "intraday_forecasts"
  "outbound_campaign_events"
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

echo "Recreating ${#TABLES[@]} resource links with storage_descriptor..."
echo ""

for table in "${TABLES[@]}"; do
  link_name="${table}_link"
  
  echo "Processing: $link_name"
  
  # Delete existing resource link
  echo "  - Deleting existing link..."
  aws glue delete-table --database-name "$DATABASE" --name "$link_name" 2>/dev/null || true
  
  # Create new resource link with storage_descriptor
  echo "  - Creating new link with storage_descriptor..."
  aws glue create-table --database-name "$DATABASE" --table-input "{
    \"Name\": \"$link_name\",
    \"TargetTable\": {
      \"CatalogId\": \"$PRODUCER_CATALOG\",
      \"DatabaseName\": \"$PRODUCER_DATABASE\",
      \"Name\": \"$table\"
    },
    \"TableType\": \"EXTERNAL_TABLE\",
    \"StorageDescriptor\": {
      \"Location\": \"\"
    }
  }"
  
  if [ $? -eq 0 ]; then
    echo "  ✓ Successfully created $link_name"
  else
    echo "  ✗ Failed to create $link_name"
  fi
  
  echo ""
done

echo "Done! Verifying first table..."
aws glue get-table --database-name "$DATABASE" --name "users_link" \
  --query "Table.[Name,StorageDescriptor.Columns[0].Name,IsRegisteredWithLakeFormation]" \
  --output json

echo ""
echo "All resource links recreated. AWS Glue will auto-populate schemas via RAM share."
