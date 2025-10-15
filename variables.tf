# =============================================================================
# CROSS-ACCOUNT CONFIGURATION VARIABLES
# =============================================================================

variable "producer_account_id" {
  description = "AWS Account ID of the producer (data owner)"
  type        = string
  default     = "502851453563"
}

variable "consumer_account_id" {
  description = "AWS Account ID of the consumer (data analyst)"
  type        = string
  default     = ""
}

variable "producer_region" {
  description = "AWS region of the producer account"
  type        = string
  default     = "ap-southeast-2"
}

variable "consumer_region" {
  description = "AWS region of the consumer account"
  type        = string
  default     = "ap-southeast-2"
}

# =============================================================================
# PROJECT CONFIGURATION VARIABLES
# =============================================================================

variable "project_name" {
  description = "Name for the project (used for resource naming)"
  type        = string
  default     = "connect-analytics"
}

variable "environment" {
  description = "Environment tag for resources"
  type        = string
  default     = "poc"
}

# =============================================================================
# AMAZON CONNECT DATA CONFIGURATION
# =============================================================================

variable "connect_tables" {
  description = "List of Amazon Connect tables to create Resource Links for"
  type        = list(string)
  default = [
    "users",
    "contacts", 
    "agent_metrics",
    "queue_metrics"
  ]
}

variable "producer_database_name" {
  description = "Name of the producer Glue database containing Amazon Connect data"
  type        = string
  default     = "connect_analytics"
}

variable "consumer_database_name" {
  description = "Name of the consumer Glue database for Resource Links"
  type        = string
  default     = "connect_analytics_consumer"
}

# =============================================================================
# LAKE FORMATION CONFIGURATION
# =============================================================================

variable "lf_tag_key" {
  description = "Lake Formation LF-Tag key for data classification"
  type        = string
  default     = "department"
}

variable "lf_tag_values" {
  description = "LF-Tag values for Lake Formation permissions"
  type        = list(string)
  default     = ["Connect"]
}

variable "enable_resource_links" {
  description = "Enable AWS Glue Resource Links for cross-account table access"
  type        = bool
  default     = true
}

variable "enable_lake_formation" {
  description = "Enable Lake Formation configuration (requires additional permissions)"
  type        = bool
  default     = true
}

# =============================================================================
# LAMBDA CONFIGURATION
# =============================================================================

variable "enable_lambda_export" {
  description = "Enable Lambda function for automated users export"
  type        = bool
  default     = true
}

variable "lambda_schedule_expression" {
  description = "Cron schedule for Lambda function execution"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC
}

# =============================================================================
# S3 CONFIGURATION
# =============================================================================

variable "athena_results_bucket_name" {
  description = "Name of the S3 bucket for Athena query results"
  type        = string
  default     = ""
}

variable "lambda_bucket_name" {
  description = "Name of the S3 bucket for Lambda code"
  type        = string
  default     = ""
}

# =============================================================================
# IAM CONFIGURATION
# =============================================================================

variable "iam_role_name" {
  description = "Name of the IAM role for data access"
  type        = string
  default     = "connect_analytics_query_role"
}

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  type        = string
  default     = "connect_analytics_workgroup"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-2"
}

# =============================================================================
# PRODUCER ACCOUNT S3 AND KMS CONFIGURATION
# =============================================================================

variable "producer_s3_bucket_name" {
  description = "Name of the S3 bucket in producer account containing Amazon Connect data"
  type        = string
  default     = ""
}

variable "producer_s3_prefix" {
  description = "S3 prefix for Amazon Connect data in producer bucket"
  type        = string
  default     = "amazon-connect-analytics"
}

variable "producer_kms_key_id" {
  description = "KMS key ID used for encrypting S3 data in producer account"
  type        = string
  default     = ""
}
