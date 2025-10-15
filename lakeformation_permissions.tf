# =============================================================================
# Lake Formation Permissions and Configuration
# =============================================================================
# Essential configuration for Amazon Connect Analytics Data Lake consumer
# All optional LF tag features removed for clean deployment

# -----------------------------------------------------------------------------
# Lake Formation Data Lake Settings
# -----------------------------------------------------------------------------

resource "aws_lakeformation_data_lake_settings" "main" {
  provider = aws.consumer
  admins = [aws_iam_role.connect_analytics_query_role.arn]
  
  trusted_resource_owners = [
    data.aws_caller_identity.current.account_id
  ]
}

# -----------------------------------------------------------------------------
# Lake Formation Permissions - Database
# -----------------------------------------------------------------------------

resource "aws_lakeformation_permissions" "database_access" {
  provider = aws.consumer
  principal = aws_iam_role.connect_analytics_query_role.arn
  
  permissions = [
    "DESCRIBE"
  ]
  
  database {
    name = aws_glue_catalog_database.consumer_database.name
  }
  
  depends_on = [
    aws_lakeformation_data_lake_settings.main,
    aws_glue_catalog_database.consumer_database
  ]
}

# -----------------------------------------------------------------------------
# Enhanced IAM Policy for Lake Formation
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "enhanced_lake_formation" {
  name        = "${var.project_name}_enhanced_lake_formation_policy"
  description = "Enhanced permissions for Amazon Connect analytics with Lake Formation"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:*",
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject",
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_lake_formation" {
  provider   = aws.consumer
  role       = aws_iam_role.connect_analytics_query_role.name
  policy_arn = aws_iam_policy.enhanced_lake_formation.arn
}

# -----------------------------------------------------------------------------
# Lambda Enhanced Permissions
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "lambda_lake_formation_access" {
  count  = var.enable_lambda_export ? 1 : 0
  provider = aws.consumer
  name   = "${var.project_name}_lambda_lake_formation_access"
  role   = aws_iam_role.connect_analytics_lambda_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Data Lake Settings for Lambda Role (if enabled)
# -----------------------------------------------------------------------------

resource "aws_lakeformation_data_lake_settings" "lambda_admin" {
  count   = var.enable_lambda_export ? 1 : 0
  provider = aws.consumer
  
  admins = [aws_iam_role.connect_analytics_lambda_role[0].arn]
  
  depends_on = [aws_lakeformation_data_lake_settings.main]
}
