# =============================================================================
# Amazon Connect Analytics Data Lake Consumer - Cross-Account Setup
# =============================================================================
# This Terraform configuration sets up a cross-account Amazon Connect Analytics
# Data Lake Consumer using Lake Formation, Resource Links, and Athena.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# =============================================================================
# AWS PROVIDERS CONFIGURATION
# =============================================================================

# Configure AWS provider for consumer account
provider "aws" {
  region = var.consumer_region
  alias  = "consumer"
}

# Configure AWS provider for producer account (if same account, uses same provider)
provider "aws" {
  region = var.producer_region
  alias  = "producer"
}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  # Get current account ID for consumer
  consumer_account_id = var.consumer_account_id != "" ? var.consumer_account_id : data.aws_caller_identity.current.account_id
  
  # Common tags for all resources
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "DataLake-Consumer"
    ManagedBy   = "Terraform"
  }
  
  # Generate bucket names if not provided
  athena_results_bucket = var.athena_results_bucket_name != "" ? var.athena_results_bucket_name : "${var.project_name}-athena-results-${local.consumer_account_id}"
  lambda_bucket = var.lambda_bucket_name != "" ? var.lambda_bucket_name : "${var.project_name}-lambda-code-${local.consumer_account_id}"
}

# =============================================================================
# RANDOM RESOURCES
# =============================================================================

resource "random_string" "poc_suffix" {
  length  = 8
  special = false
  upper   = false
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_caller_identity" "current" {
  provider = aws.consumer
}

data "aws_region" "current" {
  provider = aws.consumer
}

# =============================================================================
# S3 BUCKETS
# =============================================================================

# S3 bucket for Athena query results
resource "aws_s3_bucket" "athena_results" {
  provider = aws.consumer
  bucket   = local.athena_results_bucket
  
  tags = merge(local.common_tags, {
    Name = "Athena Query Results Bucket"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  provider = aws.consumer
  bucket   = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  provider = aws.consumer
  bucket   = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# IAM ROLE AND POLICIES
# =============================================================================

resource "aws_iam_role" "connect_analytics_query_role" {
  provider = aws.consumer
  name     = var.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["athena.amazonaws.com", "redshift.amazonaws.com"]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Amazon Connect Analytics Query Role"
  })
}

# Specific policy for Athena access
resource "aws_iam_policy" "athena_access_policy" {
  provider = aws.consumer
  name     = "${var.project_name}_athena_access_policy"
  description = "Policy for Athena query access to Amazon Connect data"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetWorkGroup",
          "athena:ListWorkGroups",
          "athena:ListQueryExecutions"
        ]
        Resource = [
          "arn:aws:athena:${var.consumer_region}:${local.consumer_account_id}:workgroup/${var.athena_workgroup_name}",
          "arn:aws:athena:${var.consumer_region}:${local.consumer_account_id}:workgroup/primary"
        ]
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
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.athena_results_bucket}",
          "arn:aws:s3:::${local.athena_results_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "lakeformation:TagCondition" = jsonencode([
              {
                TagKey    = var.lf_tag_key
                TagValues = var.lf_tag_values
              }
            ])
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "athena_access_attachment" {
  provider   = aws.consumer
  role       = aws_iam_role.connect_analytics_query_role.name
  policy_arn = aws_iam_policy.athena_access_policy.arn
}

# Lambda IAM Role (for users export function)
resource "aws_iam_role" "connect_analytics_lambda_role" {
  count    = var.enable_lambda_export ? 1 : 0
  provider = aws.consumer
  name     = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Amazon Connect Analytics Lambda Role"
  })
}

# =============================================================================
# GLUE DATABASE
# =============================================================================

resource "aws_glue_catalog_database" "consumer_database" {
  provider = aws.consumer
  name     = var.consumer_database_name

  description = "Consumer database for Amazon Connect analytics resource links"

  tags = merge(local.common_tags, {
    Name = "Amazon Connect Consumer Database"
  })
}

# =============================================================================
# LAKE FORMATION CONFIGURATION
# =============================================================================
# Lake Formation resources are now managed in lakeformation_permissions.tf
# This provides better organization and separation of concerns

# =============================================================================
# ATHENA WORKGROUP
# =============================================================================

resource "aws_athena_workgroup" "connect_analytics" {
  provider = aws.consumer
  name     = var.athena_workgroup_name
  force_destroy = true

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"
      
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
    
    enforce_workgroup_configuration = true
    publish_cloudwatch_metrics_enabled = true
  }

  # Tags removed to avoid athena:TagResource permission requirement
  # tags = merge(local.common_tags, {
  #   Name = "Amazon Connect Analytics Workgroup"
  # })
  
  lifecycle {
    ignore_changes = [tags]
  }
}

# =============================================================================
# LAMBDA RESOURCES (OPTIONAL)
# =============================================================================

# Include Lambda resources if enabled
# Note: Lambda resources are defined in POC_lambda.tf and will be created when enable_lambda_export = true

# =============================================================================
# OUTPUTS
# =============================================================================

output "consumer_account_setup" {
  description = "Consumer account configuration details"
  value = {
    account_id           = local.consumer_account_id
    region               = var.consumer_region
    athena_workgroup     = aws_athena_workgroup.connect_analytics.name
    glue_database        = aws_glue_catalog_database.consumer_database.name
    iam_role_arn         = aws_iam_role.connect_analytics_query_role.arn
    athena_results_bucket = aws_s3_bucket.athena_results.bucket
    lf_tag_key           = var.lf_tag_key
    lf_tag_values        = var.lf_tag_values
  }
}

output "producer_account_info" {
  description = "Producer account information needed for setup"
  value = {
    account_id      = var.producer_account_id
    region          = var.producer_region
    database_name   = var.producer_database_name
    tables_to_share = var.connect_tables
  }
}

output "resource_links_info" {
  description = "Resource Links information and status"
  value = {
    enabled     = var.enable_resource_links
    count       = length(var.connect_tables)
    database    = var.consumer_database_name
    tables      = var.connect_tables
    producer_account = var.producer_account_id
    producer_region  = var.producer_region
    producer_database = var.producer_database_name
  }
}

output "next_steps" {
  description = "Next steps for complete setup"
  value = var.enable_resource_links ? [
    "1. Ensure RAM share is accepted in producer account",
    "2. Resource Links are automatically created by Terraform",
    "3. Test Athena queries using the workgroup",
    "4. Verify data access with the IAM role",
    "5. Test Lambda function if enabled"
  ] : [
    "1. Ensure RAM share is accepted in producer account",
    "2. Enable Resource Links in configuration",
    "3. Run terraform apply again",
    "4. Test Athena queries using the workgroup",
    "5. Verify data access with the IAM role"
  ]
}

output "validation_commands" {
  description = "Commands to validate the setup"
  value = var.enable_resource_links ? {
    assume_role = "aws sts assume-role --role-arn ${aws_iam_role.connect_analytics_query_role.arn} --role-session-name test-session"
    test_query = "SELECT COUNT(*) FROM \"${var.consumer_database_name}\".${var.connect_tables[0]}_link LIMIT 10"
    list_tables = "aws glue get-tables --database-name ${var.consumer_database_name}"
    list_resource_links = "aws glue get-tables --database-name ${var.consumer_database_name} --query 'TableList[?contains(Name, `_link`)]'"
  } : {
    assume_role = "aws sts assume-role --role-arn ${aws_iam_role.connect_analytics_query_role.arn} --role-session-name test-session"
    enable_resource_links = "Set enable_resource_links = true in terraform.tfvars"
    list_tables = "aws glue get-tables --database-name ${var.consumer_database_name}"
  }
}

output "lambda_info" {
  description = "Lambda function information (if enabled)"
  value = var.enable_lambda_export ? {
    enabled       = true
    function_name = "${var.project_name}-users-export"
    schedule      = var.lambda_schedule_expression
    bucket_name   = local.lambda_bucket
  } : {
    enabled = false
  }
}
