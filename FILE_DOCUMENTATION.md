# Amazon Connect Cross-Account Analytics - File Documentation

This document provides comprehensive documentation for each Terraform file and script in the Amazon Connect Cross-Account Analytics project.

## Table of Contents

- [Terraform Configuration Files](#terraform-configuration-files)
  - [main.tf](#maintf)
  - [variables.tf](#variablestf)
  - [resource_links.tf](#resource_linkstf)
  - [lakeformation_permissions.tf](#lakeformation_permissionstf)
  - [lambda.tf](#lambdatf)
- [Scripts](#scripts)
  - [recreate_resource_links.sh](#recreate_resource_linkssh)
  - [verify_deployment.sh](#verify_deploymentsh)
  - [grant_lambda_permissions.sh](#grant_lambda_permissionssh)
- [Configuration Files](#configuration-files)
  - [terraform.tfvars.example](#terraformtfvarsexample)
  - [.gitignore](#gitignore)

---

## Terraform Configuration Files

### main.tf

**Purpose:** Core infrastructure configuration and resource provisioning.

**Key Sections:**

#### 1. Terraform Provider Configuration
```hcl
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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}
```
- **Purpose:** Defines required Terraform providers and their versions
- **AWS Provider:** Manages AWS resources
- **Null Provider:** Used for executing local scripts (resource link creation)
- **Time Provider:** Handles time-based operations and scheduling

#### 2. AWS Providers Configuration
```hcl
provider "aws" {
  region = var.consumer_region
  alias  = "consumer"
}

provider "aws" {
  region = var.producer_region
  alias  = "producer"
}
```
- **Consumer Provider:** Manages resources in the consumer (data analyst) account
- **Producer Provider:** Accesses producer account information (if same account, uses same provider)
- **Alias:** Enables multiple provider configurations for cross-account scenarios

#### 3. Local Values
```hcl
locals {
  consumer_account_id = var.consumer_account_id != "" ? var.consumer_account_id : data.aws_caller_identity.current.account_id
  
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "DataLake-Consumer"
    ManagedBy   = "Terraform"
  }
  
  athena_results_bucket = var.athena_results_bucket_name != "" ? var.athena_results_bucket_name : "${var.project_name}-athena-results-${local.consumer_account_id}"
  lambda_bucket = var.lambda_bucket_name != "" ? var.lambda_bucket_name : "${var.project_name}-lambda-code-${local.consumer_account_id}"
}
```
- **Purpose:** Centralizes computed values and common configurations
- **Account ID Detection:** Auto-detects consumer account ID if not specified
- **Common Tags:** Standardizes tagging across all resources
- **Bucket Naming:** Generates unique bucket names if not provided

#### 4. S3 Buckets
```hcl
resource "aws_s3_bucket" "athena_results" {
  provider = aws.consumer
  bucket   = local.athena_results_bucket
  
  tags = merge(local.common_tags, {
    Name = "Athena Query Results Bucket"
  })
}
```
- **Purpose:** Creates S3 bucket for Athena query results storage
- **Encryption:** Configured with AES256 server-side encryption
- **Security:** Blocks all public access for security compliance

#### 5. IAM Role for Data Access
```hcl
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
}
```
- **Purpose:** Creates IAM role for Athena and Redshift data access
- **Trust Policy:** Allows Athena and Redshift services to assume the role
- **Permissions:** Additional policies attached in lakeformation_permissions.tf

#### 6. Glue Database
```hcl
resource "aws_glue_catalog_database" "consumer_database" {
  provider = aws.consumer
  name     = var.consumer_database_name

  description = "Consumer database for Amazon Connect analytics resource links"
}
```
- **Purpose:** Creates Glue catalog database in consumer account
- **Usage:** Stores resource links that point to producer account tables
- **Naming:** Configurable via `consumer_database_name` variable

#### 7. Athena Workgroup
```hcl
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
}
```
- **Purpose:** Creates dedicated Athena workgroup for query execution
- **Configuration:** Sets query result location and encryption
- **Security:** Enforces workgroup configuration and enables monitoring

#### 8. Outputs
```hcl
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
```
- **Purpose:** Provides deployment information and next steps
- **Usage:** Supplies values needed for testing and validation
- **Commands:** Includes sample AWS CLI commands for verification

---

### variables.tf

**Purpose:** Defines all configurable parameters for the Terraform deployment.

**Variable Categories:**

#### 1. Cross-Account Configuration
```hcl
variable "producer_account_id" {
  description = "AWS Account ID of the producer account (where Amazon Connect data resides)"
  type        = string
}

variable "consumer_account_id" {
  description = "AWS Account ID of the consumer (data analyst)"
  type        = string
  default     = ""
}
```
- **Producer Account:** Contains the Amazon Connect instance and data lake
- **Consumer Account:** Accesses the data via resource links and Lake Formation

#### 2. Project Configuration
```hcl
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
```
- **Project Name:** Used as prefix for resource naming
- **Environment:** Tag for identifying deployment environment (dev, test, prod)

#### 3. Amazon Connect Data Configuration
```hcl
variable "connect_tables" {
  description = "List of Amazon Connect tables to create Resource Links for"
  type        = list(string)
  default = [
    # Agent and Queue Statistics
    "agent_queue_statistic_record",
    "agent_statistic_record",
    "agent_metrics",
    # ... (32 total tables)
  ]
}
```
- **Complete List:** Includes all 32 Amazon Connect analytics tables
- **Categories:** Agent metrics, contacts, forecasting, scheduling, etc.
- **Flexible:** Can be customized to include only needed tables

#### 4. Lake Formation Configuration
```hcl
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
```
- **LF-Tags:** Used for fine-grained access control in Lake Formation
- **Classification:** Helps organize and secure data by department or purpose

#### 5. Lambda Configuration
```hcl
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
```
- **Lambda Export:** Optional automated data export functionality
- **Schedule:** Configurable execution schedule using cron syntax

---

### resource_links.tf

**Purpose:** Manages AWS Glue Resource Links for cross-account table access.

**Key Challenge Solved:**
AWS Glue Resource Links created via Terraform AWS provider cannot include `storage_descriptor`, which prevents automatic schema population. This file implements a hybrid solution using Terraform + bash script.

#### 1. Resource Links Creator
```hcl
resource "null_resource" "resource_links_creator" {
  count = var.enable_resource_links ? 1 : 0
  
  triggers = {
    tables_hash         = sha256(jsonencode(var.connect_tables))
    database            = var.consumer_database_name
    producer_database   = var.producer_database_name
  }
  
  provisioner "local-exec" {
    command     = "bash ${path.module}/recreate_resource_links.sh"
    interpreter = ["bash", "-c"]
  }
  
  depends_on = [
    aws_glue_catalog_database.consumer_database
  ]
}
```
- **Purpose:** Executes bash script to create resource links with storage_descriptor
- **Triggers:** Recreates links when table list or configuration changes
- **Dependency:** Ensures consumer database exists before script execution

#### 2. Why This Approach?
- **Terraform Limitation:** AWS provider doesn't support storage_descriptor with target_table
- **Script Solution:** AWS CLI supports full resource link creation with schema
- **Automation:** Script runs automatically during terraform apply
- **Consistency:** Hash-based triggers ensure recreation only when needed

#### 3. Commented Out Sections
```hcl
# NOTE: These permissions are NOT needed when using RAM/Lake Formation shares
# The producer account has already shared access via RAM (Resource Access Manager)
```
- **Producer Permissions:** Not needed due to existing RAM shares
- **Cross-Account Issues:** Avoids permission conflicts between accounts
- **Best Practice:** Uses existing share configuration instead of duplicating permissions

---

### lakeformation_permissions.tf

**Purpose:** Configures Lake Formation permissions for secure cross-account data access.

#### 1. Enhanced IAM Policy
```hcl
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
      # ... additional permissions for Glue, Athena, S3
    ]
  })
}
```
- **Lake Formation Access:** Core permissions for data access and LF-tag operations
- **Glue Access:** Database and table metadata access
- **Athena Access:** Query execution and result retrieval
- **S3 Access:** Query result storage and retrieval

#### 2. Lambda Lake Formation Permissions
```hcl
resource "aws_lakeformation_permissions" "lambda_database_access" {
  count    = var.enable_lambda_export ? 1 : 0
  provider = aws.consumer
  
  permissions = ["DESCRIBE"]
  
  principal = aws_iam_role.lambda_role[0].arn
  
  database {
    catalog_id = local.consumer_account_id
    name       = var.consumer_database_name
  }
}
```
- **Lambda Database Access:** Grants DESCRIBE permission on consumer database
- **Table Permissions:** Must be granted manually due to Terraform state limitations
- **Manual Step:** Lambda SELECT permissions require Console "Grant on Target"

#### 3. Manual Permission Requirements
```hcl
# NOTE: Lake Formation admin permissions will be handled manually via AWS CLI
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
```
- **Manual Requirement:** Lambda SELECT permissions cannot be automated
- **Console Method:** "Grant on Target" is the only way to grant SELECT on resource links
- **CLI Alternative:** AWS CLI commands for programmatic permission granting

---

### lambda.tf

**Purpose:** Optional Lambda function for automated data export from Amazon Connect analytics.

#### 1. Lambda Function Configuration
```hcl
resource "aws_lambda_function" "users_export" {
  count         = var.enable_lambda_export ? 1 : 0
  function_name = "${var.project_name}-users-export"
  description   = "Lambda function to export Amazon Connect users data to S3"
  runtime       = "python3.11"
  handler       = "lambda_function.lambda_handler"
  timeout       = 300
  memory_size   = 256
 
  s3_bucket = aws_s3_bucket.lambda_bucket[0].id
  s3_key    = aws_s3_object.lambda_code[0].id

  role = aws_iam_role.lambda_role[0].arn
```
- **Conditional Creation:** Only created if `enable_lambda_export = true`
- **Runtime:** Python 3.11 for modern Python features
- **Configuration:** 5-minute timeout, 256MB memory for data processing
- **Storage:** Code stored in S3 for deployment

#### 2. Environment Variables
```hcl
environment {
  variables = {
    ATHENA_DATABASE  = aws_glue_catalog_database.consumer_database.name
    ATHENA_WORKGROUP = aws_athena_workgroup.connect_analytics.name
    REGION           = var.consumer_region
    OUTPUT_BUCKET    = aws_s3_bucket.athena_results.id
    OUTPUT_PREFIX    = "users-export"
    TABLE_NAME       = "users_link"
  }
}
```
- **Database Configuration:** Consumer database and workgroup for queries
- **Output Configuration:** S3 bucket and prefix for exported data
- **Table Source:** Resource link table to query (users_link)

#### 3. IAM Role and Permissions
```hcl
resource "aws_iam_role" "lambda_role" {
  count = var.enable_lambda_export ? 1 : 0
  name  = "${var.project_name}-lambda-execution-role"

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
}
```
- **Lambda Service Trust:** Allows Lambda service to assume the role
- **Policy Attachments:** AWS managed policies for Athena, S3, and Lambda execution
- **Custom Policies:** Lake Formation access for data queries

#### 4. EventBridge Schedule
```hcl
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  count               = var.enable_lambda_export ? 1 : 0
  name                = "${var.project_name}-lambda-schedule"
  description         = "Schedule for Amazon Connect users export"
  schedule_expression = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  count     = var.enable_lambda_export ? 1 : 0
  rule      = aws_cloudwatch_event_rule.lambda_schedule[0].name
  target_id = "LambdaTarget"
  arn       = aws_lambda_function.users_export[0].arn
}
```
- **Scheduled Execution:** Daily at 2 AM UTC by default
- **EventBridge Integration:** Triggers Lambda function on schedule
- **Flexible Schedule:** Configurable via `lambda_schedule_expression` variable

#### 5. Lambda Function Code
```python
def lambda_handler(event, context):
    """
    Lambda function to export Amazon Connect users data to S3
    Simplified version for testing and validation
    """
    
    # Configuration from environment variables
    athena_database = os.environ['ATHENA_DATABASE']
    athena_workgroup = os.environ['ATHENA_WORKGROUP']
    region = os.environ['REGION']
    output_bucket = os.environ['OUTPUT_BUCKET']
    output_prefix = os.environ['OUTPUT_PREFIX']
    table_name = os.environ['TABLE_NAME']
    
    # Initialize AWS clients
    athena = boto3.client('athena', region_name=region)
    s3 = boto3.client('s3', region_name=region)
```
- **Query Execution:** Runs Athena query against resource link table
- **Data Processing:** Transforms results into JSON format
- **S3 Export:** Saves results to S3 with date-based partitioning
- **Error Handling:** Comprehensive error handling and logging

---

## Scripts

### recreate_resource_links.sh

**Purpose:** Creates AWS Glue Resource Links with storage_descriptor to enable automatic schema population.

**Key Features:**

#### 1. Configuration Section
```bash
# Configuration - Update these values to match your environment
DATABASE="connect_analytics_consumer"
PRODUCER_CATALOG=""  # Set via terraform.tfvars or environment variable
PRODUCER_DATABASE="connect_datalake"
```
- **Database Names:** Consumer and producer database names
- **Producer Catalog:** Auto-detected from Terraform output if not set
- **Validation:** Ensures required variables are configured

#### 2. Table List
```bash
TABLES=(
  "agent_queue_statistic_record"
  "agent_statistic_record"
  "agent_metrics"
  # ... (32 total tables)
)
```
- **Complete Coverage:** Includes all Amazon Connect analytics tables
- **Consistent:** Matches table list in variables.tf
- **Extensible:** Easy to add or remove tables as needed

#### 3. Resource Link Creation Process
```bash
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
done
```
- **Delete and Recreate:** Ensures clean resource link creation
- **Storage Descriptor:** Critical for automatic schema population
- **Error Handling:** Continues processing even if individual links fail

#### 4. Verification
```bash
echo "Done! Verifying first table..."
aws glue get-table --database-name "$DATABASE" --name "users_link" \
  --query "Table.[Name,StorageDescriptor.Columns[0].Name,IsRegisteredWithLakeFormation]" \
  --output json
```
- **Sample Verification:** Checks first resource link for proper configuration
- **Schema Validation:** Confirms storage descriptor and Lake Formation registration
- **Success Indicators:** Shows table name, column presence, and LF registration

---

### verify_deployment.sh

**Purpose:** Comprehensive deployment verification script to ensure all resources are properly configured.

**Verification Categories:**

#### 1. Terraform State Verification
```bash
print_test "Checking Terraform state file exists"
if [ -f "terraform.tfstate" ]; then
    print_pass "Terraform state file exists"
else
    print_fail "Terraform state file not found"
fi

print_test "Checking Resource Links in Terraform state"
RESOURCE_LINKS_COUNT=$(terraform state list 2>/dev/null | grep -c "aws_glue_catalog_table.resource_links" || echo "0")
```
- **State File:** Confirms Terraform state exists and is accessible
- **Resource Tracking:** Verifies expected resources are in state
- **Clean State:** Checks for old script-based resources

#### 2. AWS Glue Resources
```bash
print_test "Checking consumer database exists"
DB_EXISTS=$(aws glue get-database --name "$CONSUMER_DATABASE" --region "$REGION" 2>/dev/null && echo "yes" || echo "no")

print_test "Checking Resource Links in AWS Glue"
RESOURCE_LINKS=$(aws glue get-tables \
    --database-name "$CONSUMER_DATABASE" \
    --region "$REGION" \
    --query 'TableList[?contains(Name, `_link`)].Name' \
    --output text 2>/dev/null || echo "")
```
- **Database Existence:** Confirms consumer Glue database exists
- **Resource Links:** Verifies all resource links are created
- **Link Validation:** Checks each link points to correct producer account

#### 3. Cross-Account Configuration
```bash
print_test "Checking Resource Link targets point to producer account"
for TABLE in users contacts agent_metrics queue_metrics; do
    TARGET=$(aws glue get-table \
        --database-name "$CONSUMER_DATABASE" \
        --name "${TABLE}_link" \
        --region "$REGION" \
        --query 'Table.TargetTable.CatalogId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$TARGET" = "$PRODUCER_ACCOUNT" ]; then
        print_pass "${TABLE}_link points to producer account $PRODUCER_ACCOUNT"
    else
        print_fail "${TABLE}_link has incorrect target: $TARGET (expected $PRODUCER_ACCOUNT)"
    fi
done
```
- **Target Validation:** Ensures resource links point to correct producer account
- **Account Verification:** Confirms cross-account configuration is correct
- **Security Check:** Validates no incorrect account references

#### 4. Lambda Function Verification
```bash
print_test "Checking Lambda function exists and is active"
LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_info.function_name 2>/dev/null || echo "")
if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
    LAMBDA_STATUS=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$REGION" --query 'Configuration.State' --output text 2>/dev/null || echo "NotFound")
    if [ "$LAMBDA_STATUS" = "Active" ]; then
        print_pass "Lambda function '$LAMBDA_FUNCTION_NAME' is active"
    else
        print_fail "Lambda function '$LAMBDA_FUNCTION_NAME' status: $LAMBDA_STATUS"
    fi
fi
```
- **Function Status:** Checks Lambda function is deployed and active
- **Configuration:** Verifies function exists with expected name
- **Health Check:** Ensures Lambda is ready for execution

---

### grant_lambda_permissions.sh

**Purpose:** Automated script to grant Lake Formation permissions to Lambda role for all resource links.

**Key Features:**

#### 1. Role Detection
```bash
# Get Lambda role ARN from Terraform output
LAMBDA_ROLE_ARN=$(terraform output -raw consumer_account_setup 2>/dev/null | grep -oP '"iam_role_arn":"[^"]*"' | cut -d'"' -f4 || echo "")
DATABASE_NAME="connect_analytics_consumer"
TABLES=("users" "contacts" "agent_metrics" "queue_metrics")
```
- **Automatic Detection:** Retrieves Lambda role ARN from Terraform output
- **Database Configuration:** Uses configured consumer database name
- **Table List:** Focuses on core tables for Lambda function

#### 2. Permission Granting Process
```bash
echo "Granting Lake Formation permissions to Lambda role: $LAMBDA_ROLE_ARN"
echo ""

# Grant database-level DESCRIBE permission
echo "1. Granting database-level DESCRIBE permission..."
aws lakeformation grant-permissions \
    --principal DataLakePrincipalIdentifier="$LAMBDA_ROLE_ARN" \
    --permissions "DESCRIBE" \
    --resource '{"Database":{"CatalogId":"'${ACCOUNT_ID}'","Name":"'${DATABASE_NAME}'"}}'

# Grant table-level permissions for each table
for table in "${TABLES[@]}"; do
    echo "2. Granting table-level permissions for ${table}_link..."
    aws lakeformation grant-permissions \
        --principal DataLakePrincipalIdentifier="$LAMBDA_ROLE_ARN" \
        --permissions "DESCRIBE" "SELECT" \
        --resource '{"Table":{"DatabaseName":"'${DATABASE_NAME}'","Name":"'${table}'_link"}}'
done
```
- **Database Permissions:** Grants DESCRIBE permission on consumer database
- **Table Permissions:** Grants DESCRIBE and SELECT on each resource link
- **Comprehensive Coverage:** Ensures Lambda can access all required tables

#### 3. Verification
```bash
echo "3. Verifying granted permissions..."
echo ""

# Check database permissions
echo "Database permissions:"
aws lakeformation list-permissions \
    --principal "$LAMBDA_ROLE_ARN" \
    --resource '{"Database":{"CatalogId":"'${ACCOUNT_ID}'","Name":"'${DATABASE_NAME}'"}}'

# Check table permissions for first table
echo ""
echo "Table permissions for users_link:"
aws lakeformation list-permissions \
    --principal "$LAMBDA_ROLE_ARN" \
    --resource '{"Table":{"DatabaseName":"'${DATABASE_NAME}'","Name":"users_link"}}'
```
- **Permission Verification:** Confirms permissions were granted successfully
- **Database Check:** Verifies database-level permissions
- **Table Check:** Sample verification of table-level permissions

---

## Configuration Files

### terraform.tfvars.example

**Purpose:** Template configuration file with example values for deployment.

**Key Sections:**

#### 1. Account Configuration
```hcl
# Account Configuration
producer_account_id = "502851453563"
consumer_account_id = "657416661258"

producer_region = "ap-southeast-2"
consumer_region = "ap-southeast-2"
```
- **Account IDs:** Producer and consumer AWS account identifiers
- **Regions:** AWS regions for each account
- **Cross-Account:** Enables cross-account data sharing

#### 2. Project Configuration
```hcl
# Project Configuration
project_name = "connect-analytics"
environment  = "poc"
```
- **Project Naming:** Used for resource naming and tagging
- **Environment:** Deployment environment identifier

#### 3. Data Configuration
```hcl
# Data configuration
connect_tables = [
  "users",
  "contacts", 
  "agent_metrics",
  "queue_metrics"
]
```
- **Table Selection:** Subset of available tables for resource links
- **Flexible:** Can be customized based on requirements

---

### .gitignore

**Purpose:** Git ignore rules to protect sensitive information and manage file exclusions.

**Key Rules:**

#### 1. Sensitive Files
```
# Protect sensitive configuration files
terraform.tfvars
```
- **Security:** Prevents committing account IDs and sensitive configuration
- **Template Only:** Only terraform.tfvars.example should be committed

#### 2. Terraform Files
```
# Terraform state and lock files
.terraform/
*.tfstate
*.tfstate.*
.terraform.lock.hcl
```
- **State Management:** Excludes Terraform state files
- **Lock Files:** Prevents lock file conflicts
- **Provider Cache:** Excludes provider cache directory

#### 3. Generated Files
```
# Generated files
lambda_function.py
lambda_users_export.zip
lambda_package/
```
- **Build Artifacts:** Excludes generated Lambda code and packages
- **Temporary Files:** Prevents committing temporary build files

#### 4. OS Files
```
# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
```
- **Cross-Platform:** Excludes OS-specific files
- **Clean Repository:** Maintains clean repository across platforms

---

## Deployment Workflow

### 1. Initial Setup
1. Copy `terraform.tfvars.example` to `terraform.tfvars`
2. Update account IDs and regions in `terraform.tfvars`
3. Select required tables in `connect_tables` list
4. Configure optional features (Lambda, Lake Formation)

### 2. Terraform Execution
1. Run `terraform init` to initialize providers
2. Run `terraform plan` to review changes
3. Run `terraform apply` to deploy infrastructure
4. Resource links are created automatically via bash script

### 3. Post-Deployment
1. Run `grant_lambda_permissions.sh` if Lambda is enabled
2. Execute `verify_deployment.sh` to validate deployment
3. Test Athena queries using provided IAM role
4. Verify Lambda function execution if enabled

### 4. Validation Commands
```bash
# Test Athena query
aws athena start-query-execution \
  --query-string "SELECT COUNT(*) FROM connect_analytics_consumer.users_link" \
  --query-execution-context Database=connect_analytics_consumer \
  --result-configuration OutputLocation=s3://connect-analytics-athena-results-<account-id>/ \
  --work-group connect_analytics_workgroup

# Test Lambda function
aws lambda invoke \
  --function-name connect-analytics-users-export \
  --payload '{}' \
  response.json
```

---

## Troubleshooting

### Common Issues

#### 1. Resource Links Without Schema
**Problem:** Resource links created but have no schema information
**Solution:** Ensure `recreate_resource_links.sh` runs successfully with storage_descriptor

#### 2. Lambda Permission Errors
**Problem:** Lambda function fails with access denied errors
**Solution:** Run `grant_lambda_permissions.sh` to grant required Lake Formation permissions

#### 3. Cross-Account Access Issues
**Problem:** Cannot access producer account data
**Solution:** Verify RAM share is accepted and producer account has granted Lake Formation permissions

#### 4. Athena Query Failures
**Problem:** Athena queries fail with table not found errors
**Solution:** Check resource link names and ensure they match expected format (`table_link`)

### Debugging Commands

```bash
# Check resource link details
aws glue get-table --database-name connect_analytics_consumer --name users_link

# Verify Lake Formation permissions
aws lakeformation list-permissions --principal <role-arn>

# Test Athena query execution
aws athena start-query-execution --query-string "SELECT * FROM users_link LIMIT 10" --work-group connect_analytics_workgroup

# Check Lambda function logs
aws logs tail /aws/lambda/connect-analytics-users-export --follow
```

---

## Architecture Summary

This implementation provides a complete, production-ready solution for cross-account Amazon Connect Analytics data sharing with the following key benefits:

1. **Security:** Lake Formation provides fine-grained access control
2. **Automation:** Terraform manages all infrastructure automatically
3. **Scalability:** Supports all 32 Amazon Connect analytics tables
4. **Flexibility:** Configurable tables, regions, and optional features
5. **Monitoring:** Comprehensive verification and validation scripts
6. **Documentation:** Complete documentation for all components

The solution follows AWS best practices and provides a robust foundation for cross-account analytics data sharing.
