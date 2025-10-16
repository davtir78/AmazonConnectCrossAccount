# =============================================================================
# Lake Formation Permissions and Configuration - Updated Based on Working Analysis
# =============================================================================
# This configuration replicates the working manual setup with least-privilege approach
# Key insights: No RAM shares needed, direct resource links with proper permissions

# -----------------------------------------------------------------------------
# Lake Formation Data Lake Settings - Consumer Account
# -----------------------------------------------------------------------------

# Since aws-cli user is already LF admin, we'll use that to grant permissions
# The existing admin setup will be used to create resource links

# -----------------------------------------------------------------------------
# Enhanced IAM Policy for Lake Formation Access
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "lake_formation_query_policy" {
  provider = aws.consumer
  name     = "${var.project_name}_lf_query_policy"
  description = "Lake Formation permissions for Amazon Connect analytics queries"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess",
          "lakeformation:GetResourceLFTags",
          "lakeformation:ListPermissions",
          "lakeformation:GrantPermissions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable", 
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions"
        ]
        Resource = [
          "arn:aws:glue:${var.consumer_region}:${local.consumer_account_id}:catalog",
          "arn:aws:glue:${var.consumer_region}:${local.consumer_account_id}:database/${var.consumer_database_name}",
          "arn:aws:glue:${var.consumer_region}:${local.consumer_account_id}:table/${var.consumer_database_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution", 
          "athena:GetQueryResults",
          "athena:GetWorkGroup",
          "athena:ListWorkGroups"
        ]
        Resource = [
          "arn:aws:athena:${var.consumer_region}:${local.consumer_account_id}:workgroup/${var.athena_workgroup_name}",
          "arn:aws:athena:${var.consumer_region}:${local.consumer_account_id}:workgroup/primary"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.athena_results_bucket}",
          "arn:aws:s3:::${local.athena_results_bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lake_formation_query_attachment" {
  provider   = aws.consumer
  role       = aws_iam_role.connect_analytics_query_role.name
  policy_arn = aws_iam_policy.lake_formation_query_policy.arn
}

# -----------------------------------------------------------------------------
# Resource Link Specific Permissions (Applied after resource links are created)
# -----------------------------------------------------------------------------

# Grant permissions on resource links to the query role
# Note: These will be applied manually after resource links are created
# due to dependency issues in Terraform
# resource "aws_lakeformation_permissions" "resource_link_access" {
#   for_each = var.enable_resource_links ? toset(var.connect_tables) : toset([])
#   provider = aws.consumer
#   
#   permissions = ["DESCRIBE", "SELECT"]
#   
#   principal = aws_iam_role.connect_analytics_query_role.arn
#   
#   table {
#     catalog_id    = local.consumer_account_id
#     database_name = var.consumer_database_name
#     name          = "${each.key}_link"
#   }
#   
#   depends_on = [
#     aws_glue_catalog_database.consumer_database,
#     aws_glue_catalog_table.resource_links
#   ]
# }

# -----------------------------------------------------------------------------
# Lambda Role Lake Formation Permissions (if enabled)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "lambda_lake_formation_policy" {
  count   = var.enable_lambda_export ? 1 : 0
  provider = aws.consumer
  name     = "${var.project_name}_lambda_lf_policy"
  role     = aws_iam_role.lambda_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess",
          "lakeformation:GetResourceLFTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# Note: Lake Formation admin permissions will be handled manually via AWS CLI

# -----------------------------------------------------------------------------
# Lake Formation Database Permissions for Lambda Role
# -----------------------------------------------------------------------------

resource "aws_lakeformation_permissions" "lambda_database_access" {
  count    = var.enable_lambda_export ? 1 : 0
  provider = aws.consumer
  
  permissions = ["DESCRIBE"]
  
  principal = aws_iam_role.lambda_role[0].arn
  
  database {
    catalog_id = local.consumer_account_id
    name       = var.consumer_database_name
  }
  
  depends_on = [
    aws_glue_catalog_database.consumer_database,
    aws_iam_role.lambda_role
  ]
}

# Grant SELECT permissions on all resource links to Lambda role
# NOTE: These permissions must be granted manually via AWS CLI after resource links are created
# The script-created resource links are not tracked in Terraform state, so we can't create
# Lake Formation permissions for them automatically.
#
# Run this command after deployment to grant Lambda permissions:
# 
# LAMBDA_ROLE_ARN=$(terraform output -raw lambda_info | grep -oP '"function_arn"\s*=\s*"\K[^"]+' | sed 's/:function:.*/:role\/connect-analytics-lambda-execution-role/')
# 
# for table in users contacts agent_metrics queue_metrics; do
#   aws lakeformation grant-permissions \
#     --principal DataLakePrincipalIdentifier=$LAMBDA_ROLE_ARN \
#     --permissions "DESCRIBE" "SELECT" \
#     --resource '{"Table":{"DatabaseName":"connect_analytics_consumer","Name":"'${table}'_link"}}'
# done
