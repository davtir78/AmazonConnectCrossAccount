# =============================================================================
# Lambda Lake Formation Permissions - Terraform Implementation
# =============================================================================
# This file demonstrates how Lambda permissions could be automated in Terraform
# if the resource links were also managed by Terraform.
#
# NOTE: This approach only works if aws_glue_resource_link resources are
# created and managed by Terraform. Currently, this is not possible due to
# provider limitations, so the grant_lambda_permissions.sh script is used instead.
# =============================================================================

# Data source for the Lambda execution role
data "aws_iam_role" "lambda_execution_role" {
  provider = aws.consumer
  name     = "connect-analytics-lambda-execution-role"
}

# Grant DESCRIBE permission on the database
# This creates the first permission shown in the AWS Console screenshot
resource "aws_lakeformation_permissions" "lambda_database_access" {
  provider   = aws.consumer
  principal   = data.aws_iam_role.lambda_execution_role.arn
  permissions = ["DESCRIBE"]

  database {
    name = aws_glue_catalog.consumer.database_name
  }
}

# Grant DESCRIBE and SELECT permissions on all resource links
# This single resource creates BOTH the 'DESCRIBE' on the resource link 
# and the 'SELECT' on the cross-account target table automatically
resource "aws_lakeformation_permissions" "lambda_table_access" {
  provider   = aws.consumer
  for_each   = aws_glue_resource_link.connect_links
  principal   = data.aws_iam_role.lambda_execution_role.arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = aws_glue_catalog.consumer.database_name
    name          = each.value.name
  }

  # Ensure this runs after the database permission is granted
  depends_on = [aws_lakeformation_permissions.lambda_database_access]
}

# =============================================================================
# Alternative Implementation Using Dynamic Resource Links
# =============================================================================
# If resource links could be created in Terraform, this would be the ideal approach:

# Variable for all Connect table names
variable "connect_tables" {
  description = "List of Amazon Connect Analytics table names"
  type        = list(string)
  default = [
    "users",
    "contacts", 
    "agent_metrics",
    "queue_metrics",
    "agent_queue_statistic_record",
    "agent_statistic_record",
    "contact_statistic_record",
    "contacts_record",
    "contact_flow_events",
    "contact_evaluation_record",
    "contact_lens_conversational_analytics",
    "bot_conversations",
    "bot_intents",
    "bot_slots",
    "agent_hierarchy_groups",
    "routing_profiles",
    "forecast_groups",
    "long_term_forecasts",
    "short_term_forecasts",
    "intraday_forecasts",
    "outbound_campaign_events",
    "staff_scheduling_profile",
    "shift_activities",
    "shift_profiles",
    "staffing_groups",
    "staffing_group_forecast_groups",
    "staffing_group_supervisors",
    "staff_shifts",
    "staff_shift_activities",
    "staff_timeoff_balance_changes",
    "staff_timeoffs",
    "staff_timeoff_intervals"
  ]
}

# This would create resource links if the provider supported cross-account operations
# resource "aws_glue_resource_link" "connect_links" {
#   provider = aws.consumer
#   for_each = toset(var.connect_tables)
#   
#   name = "${each.value}_link"
#   target_arn = "arn:aws:glue:${var.producer_region}:${var.producer_account_id}:table/connect_analytics_producer/${each.value}"
#   catalog_id = data.aws_caller_identity.consumer.account_id
# }

# Then the permissions would reference the created resource links
# resource "aws_lakeformation_permissions" "lambda_all_table_access" {
#   provider   = aws.consumer
#   for_each   = aws_glue_resource_link.connect_links
#   principal   = data.aws_iam_role.lambda_execution_role.arn
#   permissions = ["SELECT", "DESCRIBE"]
# 
#   table {
#     database_name = aws_glue_catalog.consumer.database_name
#     name          = each.value.name
#   }
# 
#   depends_on = [aws_lakeformation_permissions.lambda_database_access]
# }

# =============================================================================
# Current Limitations and Workarounds
# =============================================================================
# 
# Why this Terraform approach doesn't work currently:
# 
# 1. aws_glue_resource_link provider doesn't support cross-account creation
# 2. Lake Formation permissions resource requires the resource links to exist in state
# 3. Cross-account dependencies create circular dependency issues
# 4. Provider limitations prevent proper resource management
# 
# Current solution:
# - Use recreate_resource_links.sh to create resource links manually
# - Use grant_lambda_permissions.sh to grant permissions via AWS CLI
# - Terraform manages the base infrastructure (S3, Glue databases, IAM roles, Lambda)
# - Scripts handle the cross-account operations that can't be automated in Terraform
# 
# Future improvements:
# - When AWS improves the Terraform provider, migrate the scripts to Terraform
# - Consider using AWS CDK which might handle these dependencies better
# - Develop custom Terraform providers for Lake Formation operations
