#!/bin/bash

# Automated Lake Formation permissions for Lambda function
# Grants DESCRIBE permission on all resource links to enable Lambda access

set -e

# Configuration
CONSUMER_ACCOUNT_ID="657416661258"
LAMBDA_ROLE_NAME="connect-analytics-lambda-execution-role"
DATABASE_NAME="connect_analytics_consumer"

# Construct role ARN
LAMBDA_ROLE_ARN="arn:aws:iam::${CONSUMER_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"

echo "=== Granting Lambda Permissions via CLI ==="
echo "Consumer Account: ${CONSUMER_ACCOUNT_ID}"
echo "Lambda Role: ${LAMBDA_ROLE_ARN}"
echo "Database: ${DATABASE_NAME}"
echo ""

# All Amazon Connect tables (matches terraform.tfvars)
CONNECT_TABLES=(
  "users"
  "contacts"
  "agent_metrics"
  "queue_metrics"
  "agent_queue_statistic_record"
  "agent_statistic_record"
  "contact_statistic_record"
  "contacts_record"
  "contact_flow_events"
  "contact_evaluation_record"
  "contact_lens_conversational_analytics"
  "bot_conversations"
  "bot_intents"
  "bot_slots"
  "agent_hierarchy_groups"
  "routing_profiles"
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

SUCCESS_COUNT=0
FAILED_COUNT=0

echo "Granting DESCRIBE permissions on all resource links..."
echo ""

for table in "${CONNECT_TABLES[@]}"; do
  resource_link_name="${table}_link"
  
  echo -n "Granting DESCRIBE on ${resource_link_name}... "
  
  # Grant DESCRIBE permission on the resource link
  if aws lakeformation grant-permissions \
    --principal DataLakePrincipalIdentifier="${LAMBDA_ROLE_ARN}" \
    --permissions "DESCRIBE" \
    --resource "{\"Table\":{\"DatabaseName\":\"${DATABASE_NAME}\",\"Name\":\"${resource_link_name}\"}}" \
    --query "ResponseMetadata.HTTPStatusCode" \
    --output text 2>/dev/null; then
    
    echo "✅ SUCCESS"
    ((SUCCESS_COUNT++))
  else
    echo "❌ FAILED"
    ((FAILED_COUNT++))
  fi
done

echo ""
echo "=== Summary ==="
echo "✅ Successful grants: ${SUCCESS_COUNT}"
echo "❌ Failed grants: ${FAILED_COUNT}"

if [ ${FAILED_COUNT} -eq 0 ]; then
  echo ""
  echo "🎉 All permissions granted successfully!"
  echo ""
  echo "Testing Lambda function..."
  
  # Test Lambda function
  aws lambda invoke \
    --function-name connect-analytics-users-export \
    --payload '{}' \
    test_lambda_response.json 2>/dev/null
  
  if [ -f test_lambda_response.json ]; then
    if grep -q '"statusCode": 200' test_lambda_response.json; then
      echo "✅ Lambda function working correctly!"
      echo "Response: $(cat test_lambda_response.json | python -c "import sys, json; print(json.load(sys.stdin)['body'])")"
    else
      echo "❌ Lambda function failed"
      cat test_lambda_response.json
    fi
    rm -f test_lambda_response.json
  fi
  
  echo ""
  echo "🚀 Lambda permissions are now fully automated!"
  echo "No manual setup required."
else
  echo ""
  echo "⚠️  Some permissions failed. Check AWS Console for details."
  echo "You may need to grant permissions manually for failed tables."
fi
