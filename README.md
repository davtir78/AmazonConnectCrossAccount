# Amazon Connect Cross-Account Analytics with Terraform

**Why Lake Formation?** Alternative approaches were considered including direct IAM role assumption in the producer account, but this is not feasible for Amazon Connect Analytics Data Lake. The data lake infrastructure (S3 buckets, Glue databases, and tables) is owned by an AWS service account that customers cannot access or assume roles against. Lake Formation is the only supported mechanism for cross-account access to Amazon Connect analytics data, making it the mandatory architectural pattern for this use case.

A complete Terraform solution for setting up cross-account access to Amazon Connect Analytics Data Lake, enabling secure data sharing between AWS accounts without data duplication.

## ⚠️ Important: Manual Steps Required

**This project achieves ~80% automation with Terraform, but requires some manual steps due to AWS service limitations:**

### Manual Steps Required:

- **Lake Formation Admin Setup (One-time)**
  - Grant Lake Formation admin permissions to your AWS user/role
  - Required for Terraform to manage Lake Formation permissions
  - Location: AWS Console → Lake Formation → Permissions → Admin

- **RAM Share Acceptance (Prerequisite)**
  - Accept the RAM share invitation from producer account
  - Must be done before running Terraform
  - Location: AWS Console → RAM → Shared with me → Accept invitation

- **Lambda "Grant on Target" Permissions (If Lambda Enabled)**
  - Manual Lake Formation permission grant using "Grant on Target" feature
  - CLI can automate DESCRIBE permissions ✅
  - CLI CANNOT automate SELECT permissions on target tables ❌
  - Console "Grant on Target" is the only way to grant SELECT on cross-account tables
  - Location: AWS Console → Lake Formation → Permissions → Grant → Target table

### Scripts Used Due to Terraform Limitations:

- **`recreate_resource_links.sh`**
  - Required because Terraform AWS provider doesn't support `storage_descriptor` with `target_table`
  - Creates Resource Links with storage descriptor for automatic schema population
  - Automatically called by Terraform during `apply`

- **`grant_lambda_permissions.sh`**
  - Automates DESCRIBE permissions for Lambda role (partial solution)
  - Cannot automate SELECT permissions due to AWS CLI limitations

- **`verify_deployment.sh`**
  - Comprehensive validation script for troubleshooting complex cross-account setup

### Why These Limitations Exist:

- **Terraform Provider Gaps**: AWS provider lacks support for certain Resource Link configurations
- **AWS Service Limitations**: Lake Formation CLI cannot grant SELECT on cross-account target tables
- **Amazon Connect Data Architecture**: Data owned by AWS service account, not customer account

### Automation vs Manual Breakdown:

| Component | Terraform | CLI | Console | Notes |
|-----------|-----------|-----|---------|-------|
| S3 Buckets | ✅ | ✅ | ✅ | Fully automated |
| IAM Roles | ✅ | ✅ | ✅ | Fully automated |
| Glue Database | ✅ | ✅ | ✅ | Fully automated |
| Resource Links | ❌ | ✅ | ✅ | Script required |
| Lake Formation DB Perms | ✅ | ✅ | ✅ | Fully automated |
| Lake Formation Table Perms | ✅ | ✅ | ✅ | Fully automated |
| Lambda DESCRIBE Perms | ❌ | ✅ | ✅ | Script required |
| Lambda SELECT Perms | ❌ | ❌ | ✅ | Manual only |

### Your Options:

1. **Enable Lambda Function** (`enable_lambda_export = true`)
   - Requires 5-minute manual Lake Formation setup after deployment
   - Follow [setup_lambda_permissions.md](setup_lambda_permissions.md) for detailed steps

2. **Disable Lambda Function** (`enable_lambda_export = false`)
   - Achieves 100% automation for core cross-account access
   - No manual steps required after initial Lake Formation admin setup

**Everything infrastructure-related is fully automated via Terraform - only AWS service limitations require manual intervention!**

## 🎯 What This Project Does

This project automates the deployment of infrastructure that allows a **consumer AWS account** to query Amazon Connect analytics data stored in a **producer AWS account**, using:

- **AWS Glue Resource Links** - Virtual tables pointing to shared data
- **AWS Lake Formation** - Fine-grained access control
- **AWS RAM (Resource Access Manager)** - Cross-account resource sharing
- **Amazon Athena** - SQL queries on the shared data
- **AWS Lambda** (optional) - Automated data exports

**Key Benefit:** Query Amazon Connect data across accounts without copying or moving data, maintaining a single source of truth.

## 📋 Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [File Structure](#file-structure)
- [Configuration](#configuration)
- [The Resource Link Challenge](#the-resource-link-challenge)
- [Deployment](#deployment)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Cost Considerations](#cost-considerations)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    PRODUCER ACCOUNT                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Amazon Connect Instance                                  │  │
│  │  └─> Exports data to S3                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  AWS Glue Data Catalog                                    │  │
│  │  Database: connect_datalake                               │  │
│  │  Tables: users, contacts, agent_metrics, etc. (32 tables) │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           │ AWS RAM Share                        │
│                           │ (Lake Formation)                     │
└───────────────────────────┼──────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CONSUMER ACCOUNT                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  AWS Glue Resource Links (Terraform + Script)             │  │
│  │  Database: connect_analytics_consumer                     │  │
│  │  Links: users_link, contacts_link, etc. (32 links)        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Amazon Athena                                            │  │
│  │  Workgroup: connect_analytics_workgroup                   │  │
│  │  Queries: SELECT * FROM users_link WHERE ...              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  AWS Lambda (Optional)                                    │  │
│  │  Function: Automated data exports                         │  │
│  │  Schedule: Daily at 2 AM UTC                              │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## ✅ Prerequisites

### Producer Account Requirements

1. **Amazon Connect Instance** with Data Streaming enabled
2. **AWS Glue Database** containing Connect analytics tables
3. **AWS RAM Share** created and shared with consumer account
4. **Lake Formation** permissions configured for the shared database

### Consumer Account Requirements

1. **AWS CLI** installed and configured
2. **Terraform** >= 1.0.0 installed
3. **Bash** shell (Git Bash on Windows, native on Linux/Mac)
4. **AWS Credentials** with appropriate permissions:
   - `glue:*` - Glue catalog operations
   - `lakeformation:*` - Lake Formation permissions
   - `iam:*` - IAM role creation
   - `s3:*` - S3 bucket operations
   - `athena:*` - Athena workgroup management
   - `lambda:*` - Lambda function deployment (if enabled)

### RAM Share Acceptance

**CRITICAL:** Before running Terraform, the consumer account must accept the RAM share invitation from the producer account:

```bash
# List pending RAM share invitations
aws ram get-resource-share-invitations \
  --query 'resourceShareInvitations[?status==`PENDING`]'

# Accept the invitation
aws ram accept-resource-share-invitation \
  --resource-share-invitation-arn <invitation-arn>
```

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd amazon-connect-cross-account
```

### 2. Configure Your Environment

```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your account details
nano terraform.tfvars
```

Update these critical values:
- `producer_account_id` - Your producer AWS account ID
- `consumer_account_id` - Your consumer AWS account ID
- `producer_database_name` - Name of the Glue database in producer account (usually `connect_datalake`)
- `producer_region` and `consumer_region` - AWS regions

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Deploy Infrastructure

```bash
# Review the plan
terraform plan

# Deploy everything
terraform apply
```

**That's it!** Terraform will:
1. Create all infrastructure (databases, IAM roles, S3 buckets, Athena workgroup)
2. Automatically run the bash script to create resource links with schemas
3. Configure Lake Formation permissions
4. Deploy Lambda function (if enabled)

### 5. Set Up Lambda Permissions (Required for Lambda Function)

**IMPORTANT:** The Lambda function requires a one-time manual setup to grant Lake Formation permissions. This takes approximately 5 minutes.

```bash
# Follow the step-by-step guide
cat setup_lambda_permissions.md

# Or use the AWS CLI method (see setup_lambda_permissions.md for details)
```

See **[setup_lambda_permissions.md](setup_lambda_permissions.md)** for complete instructions.

### 6. Test Your Deployment

```bash
# Test Lambda function (after setting up permissions)
aws lambda invoke \
  --function-name connect-analytics-users-export \
  --payload '{}' \
  response.json

# Or query directly with Athena
aws athena start-query-execution \
  --query-string "SELECT COUNT(*) FROM connect_analytics_consumer.users_link" \
  --query-execution-context Database=connect_analytics_consumer \
  --result-configuration OutputLocation=s3://connect-analytics-athena-results-<account-id>/ \
  --work-group connect_analytics_workgroup
```

## 📁 File Structure

```
.
├── README.md                           # This file
├── LICENSE                             # MIT License
├── .gitignore                          # Git ignore rules (protects credentials)
│
├── terraform.tfvars.example            # Configuration template (no credentials)
├── terraform.tfvars                    # Your actual config (gitignored, contains account IDs)
│
├── main.tf                             # Main Terraform configuration
├── variables.tf                        # Variable definitions
├── outputs.tf                          # Output definitions
│
├── resource_links.tf                   # Resource link automation
├── lakeformation_permissions.tf        # Lake Formation permissions
├── lambda.tf                           # Lambda function (optional)
│
├── recreate_resource_links.sh          # Bash script for resource links
│
└── verify_deployment.sh                # Deployment verification script
```

### Key Files Explained

#### Configuration Files

- **`terraform.tfvars.example`** - Template configuration file with placeholder values. Copy this to `terraform.tfvars` and update with your account IDs.
- **`terraform.tfvars`** - Your actual configuration (gitignored). Contains real account IDs and settings.
- **`.gitignore`** - Protects sensitive files from being committed to Git.

#### Terraform Infrastructure Files

- **`main.tf`** - Core infrastructure:
  - AWS provider configuration for both accounts
  - Glue database creation
  - S3 buckets for Athena results and Lambda code
  - Athena workgroup configuration
  - IAM roles and policies

- **`variables.tf`** - Defines all configurable parameters:
  - Account IDs and regions
  - Database names
  - Table lists
  - Feature flags (enable/disable Lambda, Lake Formation, etc.)

- **`resource_links.tf`** - **Critical file** that handles the resource link challenge:
  - Uses `null_resource` with `local-exec` provisioner
  - Automatically runs `recreate_resource_links.sh` during `terraform apply`
  - Triggers on table list changes

- **`lakeformation_permissions.tf`** - Lake Formation access control:
  - LF-Tag creation and assignment
  - Database and table permissions
  - Consumer account access grants

- **`lambda.tf`** - Optional Lambda function for automated exports:
  - Python function for data export
  - EventBridge schedule (daily at 2 AM UTC)
  - IAM permissions for Athena and S3 access

#### Scripts

- **`recreate_resource_links.sh`** - **Critical script** that solves the Terraform limitation:
  - Creates all 32 resource links via AWS CLI
  - Includes `storage_descriptor` to trigger schema auto-population
  - Automatically run by Terraform during apply
  - Can also be run manually if needed

- **`verify_deployment.sh`** - Validates the deployment:
  - Checks resource link creation
  - Verifies schema population
  - Tests Athena connectivity


## ⚙️ Configuration

### Essential Configuration (terraform.tfvars)

```hcl
# Account IDs (REQUIRED)
producer_account_id = "111111111111"  # Replace with your producer account
consumer_account_id = "222222222222"  # Replace with your consumer account

# Regions (REQUIRED)
producer_region = "us-east-1"
consumer_region = "us-east-1"

# Database Names (REQUIRED)
producer_database_name = "connect_datalake"  # Usually this name
consumer_database_name = "connect_analytics_consumer"

# Tables to Share (REQUIRED)
connect_tables = [
  "users",
  "contacts",
  "agent_metrics",
  "queue_metrics"
  # Add more tables as needed
]
```

### All Available Tables

The project supports all 32 Amazon Connect analytics tables:

**Agent & Queue Statistics:**
- agent_queue_statistic_record
- agent_statistic_record
- agent_metrics
- contact_statistic_record
- queue_metrics

**Contact Records:**
- contacts_record
- contacts
- contact_flow_events
- contact_evaluation_record

**Contact Lens:**
- contact_lens_conversational_analytics

**Bot Analytics:**
- bot_conversations
- bot_intents
- bot_slots

**Configuration:**
- agent_hierarchy_groups
- routing_profiles
- users

**Forecasting:**
- forecast_groups
- long_term_forecasts
- short_term_forecasts
- intraday_forecasts

**Outbound Campaigns:**
- outbound_campaign_events

**Staff Scheduling:**
- staff_scheduling_profile
- shift_activities
- shift_profiles
- staffing_groups
- staffing_group_forecast_groups
- staffing_group_supervisors
- staff_shifts
- staff_shift_activities
- staff_timeoff_balance_changes
- staff_timeoffs
- staff_timeoff_intervals

### Optional Features

```hcl
# Lambda Function for Automated Exports
enable_lambda_export = true
lambda_schedule_expression = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC

# Lake Formation
enable_lake_formation = true
lf_tag_key = "department"
lf_tag_values = ["Connect"]

# Resource Links
enable_resource_links = true  # Must be true for cross-account access
```

## 🔧 The Resource Link Challenge

### The Problem

AWS Glue Resource Links are virtual tables that point to tables in another account. However, the Terraform AWS provider has a limitation:

**When creating a resource link with `target_table`, Terraform cannot include `storage_descriptor`.**

Without `storage_descriptor`:
- ❌ Resource link is created but has no schema information
- ❌ `StorageDescriptor: null` in the table metadata
- ❌ `IsRegisteredWithLakeFormation: false`
- ❌ Athena queries fail: "Table StorageDescriptor is null"

### The Solution

We use a **hybrid approach**:

1. **Terraform** creates all infrastructure (databases, IAM, S3, Athena, Lambda)
2. **Bash script** creates resource links via AWS CLI with `storage_descriptor`
3. **AWS Glue** automatically populates full schemas via RAM/Lake Formation share
4. **Terraform automation** runs the script automatically during `terraform apply`

### How It Works

```hcl
# resource_links.tf
resource "null_resource" "resource_links_creator" {
  provisioner "local-exec" {
    command     = "bash ${path.module}/recreate_resource_links.sh"
    interpreter = ["bash", "-c"]
  }
}
```

When you run `terraform apply`:
1. Terraform creates the consumer database
2. The `null_resource` triggers
3. The bash script runs automatically
4. All 32 resource links are created with schemas
5. Athena queries work immediately!

### Why This Approach?

✅ **Fully Automated** - Single `terraform apply` command
✅ **No Manual Steps** - Script runs automatically
✅ **Schemas Auto-Populate** - AWS Glue fetches schemas via RAM share
✅ **Production Ready** - Tested and reliable
✅ **CI/CD Compatible** - Works in automated pipelines


## 🚀 Deployment

### Standard Deployment

```bash
# 1. Initialize Terraform
terraform init

# 2. Review the plan
terraform plan

# 3. Deploy everything
terraform apply

# The script runs automatically - no manual steps needed!
```

### Deployment Output

```
Apply complete! Resources: 26 added, 0 changed, 0 destroyed.

Outputs:

consumer_account_setup = {
  "account_id" = "222222222222"
  "athena_workgroup" = "connect_analytics_workgroup"
  "glue_database" = "connect_analytics_consumer"
  ...
}

resource_links_info = {
  "count" = 32
  "tables" = [
    "users",
    "contacts",
    ...
  ]
}
```

### Verify Deployment

```bash
# Check resource links were created
aws glue get-tables \
  --database-name connect_analytics_consumer \
  --query "TableList[?contains(Name, '_link')].Name"

# Should return 32 table names ending in "_link"
```

### Manual Script Execution (if needed)

If you need to recreate resource links manually:

```bash
bash recreate_resource_links.sh
```

## 📊 Amazon Connect Analytics Tables Reference

### Table Metadata Export

This project includes a comprehensive metadata export script that documents all Amazon Connect Analytics tables available through the resource links.

### Available Tables by Category:

**Agent & Queue Statistics (5 tables):**
- `agent_queue_statistic_record` - Agent queue performance metrics
- `agent_statistic_record` - Individual agent statistics
- `agent_metrics` - Agent performance metrics
- `contact_statistic_record` - Contact-level statistics
- `queue_metrics` - Queue performance metrics

**Contact Records (4 tables):**
- `contacts_record` - Contact interaction records
- `contacts` - Contact details and metadata
- `contact_flow_events` - Contact flow execution events
- `contact_evaluation_record` - Contact evaluation data

**Contact Lens (1 table):**
- `contact_lens_conversational_analytics` - Conversation analytics and insights

**Bot Analytics (3 tables):**
- `bot_conversations` - Bot interaction data
- `bot_intents` - Bot intent recognition data
- `bot_slots` - Bot slot filling data

**Configuration (3 tables):**
- `agent_hierarchy_groups` - Agent hierarchy structure
- `routing_profiles` - Routing profile configurations
- `users` - User account information

**Forecasting (4 tables):**
- `forecast_groups` - Forecast group definitions
- `long_term_forecasts` - Long-term forecasting data
- `short_term_forecasts` - Short-term forecasting data
- `intraday_forecasts` - Intraday forecasting data

**Outbound Campaigns (1 table):**
- `outbound_campaign_events` - Outbound campaign event data

**Staff Scheduling (11 tables):**
- `staff_scheduling_profile` - Staff scheduling configurations
- `shift_activities` - Shift activity definitions
- `shift_profiles` - Shift profile configurations
- `staffing_groups` - Staffing group definitions
- `staffing_group_forecast_groups` - Staffing-forecast mappings
- `staffing_group_supervisors` - Staffing supervisor assignments
- `staff_shifts` - Staff shift assignments
- `staff_shift_activities` - Staff shift activities
- `staff_timeoff_balance_changes` - Time-off balance changes
- `staff_timeoffs` - Time-off requests
- `staff_timeoff_intervals` - Time-off time intervals

### Export Complete Table Metadata

To export comprehensive metadata for all tables (including column names, data types, descriptions, and partition information):

```bash
# Run the metadata export script
./export_table_metadata.sh

# This will create:
# - amazon_connect_tables_metadata.csv (complete metadata)
# - Console output with progress and summary
```

**Script Features:**
- Exports metadata for all 32 Amazon Connect Analytics tables
- Includes table and column descriptions where available
- Identifies partition keys and data types
- Works with resource links in the consumer account
- Provides progress indicators and error handling
- Generates CSV output suitable for documentation

**Output File:** `amazon_connect_tables_metadata.csv`

**CSV Columns:**
- Table Name - Source table name
- Column Name - Column identifier
- Data Type - Column data type (string, int, timestamp, etc.)
- Description - Column description (if available)
- Is Partition Key - Whether column is used for partitioning
- Table Location - S3 path for table data
- Table Type - Table type (EXTERNAL, MANAGED, etc.)
- Last Updated - Last modification timestamp
- Table Description - Table-level description

**Requirements:**
- AWS CLI configured with consumer account access
- Resource links must be created (via Terraform deployment)
- Optional: `jq` for better JSON parsing (script works without it)

### Installing jq on Windows

**Option 1: Using Chocolatey (Recommended)**
```bash
# Install Chocolatey (if not already installed)
# Run PowerShell as Administrator and run:
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install jq
choco install jq

# Verify installation
jq --version
```

**Option 2: Using Scoop**
```bash
# Install Scoop (if not already installed)
# Run PowerShell and run:
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex

# Install jq
scoop install jq

# Verify installation
jq --version
```

**Option 3: Manual Download**
1. Go to https://stedolan.github.io/jq/download/
2. Download the latest `jq-win64.exe`
3. Rename it to `jq.exe`
4. Move it to a directory in your PATH (e.g., `C:\Windows\System32\`)
5. Open a new Command Prompt or PowerShell and verify:
   ```bash
   jq --version
   ```

**Option 4: Using Git Bash**
If you're using Git Bash (which comes with Git for Windows), jq is often included:
```bash
# In Git Bash
jq --version
```

**Why Install jq?**
- **Better JSON Parsing**: More reliable extraction of column information
- **Cleaner Output**: Proper handling of special characters and formatting
- **Error Handling**: Better error messages for malformed JSON
- **Performance**: Faster processing of large JSON responses

**Note**: The script works perfectly without jq, but installing it provides more robust and accurate metadata extraction.

**Customization:**
- Edit the `TABLES` array in `export_table_metadata.sh` to add/remove tables
- Modify `CONSUMER_DATABASE` and `REGION` variables if needed
- Change output filename by updating `OUTPUT_FILE` variable

## 📊 Usage

### Query Data with Athena

```sql
-- Count users
SELECT COUNT(*) as total_users 
FROM connect_analytics_consumer.users_link;

-- Recent contacts
SELECT * 
FROM connect_analytics_consumer.contacts_link 
WHERE contact_date > CURRENT_DATE - INTERVAL '7' DAY
LIMIT 100;

-- Agent performance
SELECT 
  agent_id,
  COUNT(*) as total_contacts,
  AVG(handle_time) as avg_handle_time
FROM connect_analytics_consumer.agent_metrics_link
WHERE date >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY agent_id
ORDER BY total_contacts DESC;
```

### Query via AWS CLI

```bash
# Start a query
QUERY_ID=$(aws athena start-query-execution \
  --query-string "SELECT COUNT(*) FROM connect_analytics_consumer.users_link" \
  --query-execution-context Database=connect_analytics_consumer \
  --result-configuration OutputLocation=s3://connect-analytics-athena-results-<account-id>/ \
  --work-group connect_analytics_workgroup \
  --query QueryExecutionId \
  --output text)

# Check query status
aws athena get-query-execution \
  --query-execution-id $QUERY_ID \
  --query "QueryExecution.Status.State"

# Get results
aws athena get-query-results \
  --query-execution-id $QUERY_ID
```

### Lambda Function (if enabled)

**IMPORTANT:** The Lambda function requires additional Lake Formation permissions that cannot be automated via Terraform. After deployment, you must manually grant permissions via the AWS Console:

1. Go to AWS Lake Formation Console
2. Navigate to "Permissions" → "Data lake permissions"
3. Click "Grant"
4. Select the Lambda execution role: `connect-analytics-lambda-execution-role`
5. Grant permissions on database `connect_analytics_consumer` and all tables
6. Grant `DESCRIBE` and `SELECT` permissions

Alternatively, disable the Lambda function by setting `enable_lambda_export = false` in terraform.tfvars.

```bash
# View Lambda logs
aws logs tail /aws/lambda/connect-analytics-users-export --follow

# Manually trigger Lambda (after granting permissions)
aws lambda invoke \
  --function-name connect-analytics-users-export \
  --payload '{}' \
  response.json
```

## 🔍 Troubleshooting

### Resource Links Have No Schema

**Symptom:** Athena queries fail with "Table StorageDescriptor is null"

**Solution:**
```bash
# Recreate resource links
bash recreate_resource_links.sh

# Verify schema populated
aws glue get-table \
  --database-name connect_analytics_consumer \
  --name users_link \
  --query "Table.[StorageDescriptor.Columns[0].Name,IsRegisteredWithLakeFormation]"
```

### RAM Share Not Accepted

**Symptom:** "Access Denied" errors when querying

**Solution:**
```bash
# Check RAM share status
aws ram get-resource-share-invitations

# Accept pending invitation
aws ram accept-resource-share-invitation \
  --resource-share-invitation-arn <arn>
```

### Wrong Producer Database Name

**Symptom:** Resource links created but queries fail

**Solution:**
1. Check the actual database name in producer account
2. Update `producer_database_name` in `terraform.tfvars`
3. Update `PRODUCER_DATABASE` in `recreate_resource_links.sh`
4. Run `bash recreate_resource_links.sh`

### Terraform Apply Fails

**Symptom:** Errors during `terraform apply`

**Common Causes:**
- AWS credentials not configured
- Insufficient IAM permissions
- RAM share not accepted
- S3 bucket name conflicts

**Solution:**
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check IAM permissions
aws iam get-user

# Review Terraform logs
terraform apply 2>&1 | tee terraform.log
```



## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📚 Additional Resources

- [AWS Glue Resource Links Documentation](https://docs.aws.amazon.com/glue/latest/dg/resource-links.html)
- [AWS Lake Formation Documentation](https://docs.aws.amazon.com/lake-formation/latest/dg/what-is-lake-formation.html)
- [Amazon Connect Analytics Data Lake](https://docs.aws.amazon.com/connect/latest/adminguide/amazon-connect-analytics-data-lake.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)


---
