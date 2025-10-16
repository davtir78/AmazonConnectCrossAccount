# Amazon Connect Cross-Account Analytics with Terraform

A complete Terraform solution for setting up cross-account access to Amazon Connect Analytics Data Lake, enabling secure data sharing between AWS accounts without data duplication.

## ⚠️ Important: Manual Steps Required

**This project requires ONE manual step after Terraform deployment:**

If you enable the Lambda function (`enable_lambda_export = true`), you must manually grant Lake Formation permissions via AWS Console. This is a **5-minute one-time setup** that cannot be automated due to AWS Lake Formation limitations.

**Options:**
1. **Enable Lambda** - Follow [setup_lambda_permissions.md](setup_lambda_permissions.md) after deployment (5 minutes)
2. **Disable Lambda** - Set `enable_lambda_export = false` for fully automated deployment (no manual steps)

**Everything else is fully automated via Terraform!**

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
├── TERRAFORM_LIMITATION.md             # Technical documentation on Terraform limitation
├── CROSS_ACCOUNT_SOLUTION.md           # Architecture and solution guide
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

#### Documentation

- **`TERRAFORM_LIMITATION.md`** - Deep dive into the technical challenge:
  - Why Terraform can't create resource links with schemas
  - Attempted workarounds
  - Final solution explanation
  - Comparison of approaches

- **`CROSS_ACCOUNT_SOLUTION.md`** - Complete architecture guide:
  - Prerequisites and setup
  - Step-by-step deployment
  - Troubleshooting guide
  - Best practices

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

See [TERRAFORM_LIMITATION.md](TERRAFORM_LIMITATION.md) for technical details.

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

## 💰 Cost Considerations

### Estimated Monthly Costs (US East 1)

| Service | Usage | Estimated Cost |
|---------|-------|----------------|
| AWS Glue Data Catalog | 32 tables | Free (first 1M objects) |
| Amazon Athena | 100 GB scanned/month | $0.50 |
| S3 Storage | 10 GB query results | $0.23 |
| Lambda | 30 executions/month | Free (first 1M requests) |
| CloudWatch Logs | 1 GB/month | $0.50 |
| **Total** | | **~$1.23/month** |

### Cost Optimization Tips

1. **Partition Your Data** - Use date partitions to reduce Athena scan costs
2. **Compress Results** - Enable Athena result compression
3. **Limit Query Scope** - Use WHERE clauses to scan less data
4. **Clean Up Old Results** - Set S3 lifecycle policies
5. **Monitor Usage** - Use AWS Cost Explorer

## 🔒 Security

### Credentials Protection

✅ **terraform.tfvars** - Gitignored, contains account IDs
✅ **AWS credentials** - Never committed to Git
✅ **.gitignore** - Comprehensive protection rules
✅ **terraform.tfvars.example** - Template with placeholders only

### IAM Permissions

The solution creates minimal IAM roles with least-privilege access:

- **Query Role** - Read-only access to Glue catalog and S3 results
- **Lambda Role** - Athena execution and S3 write permissions

### Lake Formation

Fine-grained access control via LF-Tags:
- Database-level permissions
- Table-level permissions
- Column-level filtering (optional)

### Best Practices

1. **Use IAM Roles** - Don't use long-term credentials
2. **Enable CloudTrail** - Audit all API calls
3. **Encrypt at Rest** - S3 buckets use SSE-S3 encryption
4. **Encrypt in Transit** - All AWS API calls use HTTPS
5. **Regular Reviews** - Audit permissions quarterly

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Development Setup

```bash
# Clone your fork
git clone <your-fork-url>
cd amazon-connect-cross-account

# Create a branch
git checkout -b feature/your-feature

# Make changes and test
terraform plan
terraform apply

# Commit and push
git add .
git commit -m "Description of changes"
git push origin feature/your-feature
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📚 Additional Resources

- [AWS Glue Resource Links Documentation](https://docs.aws.amazon.com/glue/latest/dg/resource-links.html)
- [AWS Lake Formation Documentation](https://docs.aws.amazon.com/lake-formation/latest/dg/what-is-lake-formation.html)
- [Amazon Connect Analytics Data Lake](https://docs.aws.amazon.com/connect/latest/adminguide/amazon-connect-analytics-data-lake.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 🆘 Support

For issues and questions:

1. Check [TERRAFORM_LIMITATION.md](TERRAFORM_LIMITATION.md) for technical details
2. Review [CROSS_ACCOUNT_SOLUTION.md](CROSS_ACCOUNT_SOLUTION.md) for architecture
3. Search existing GitHub issues
4. Create a new issue with:
   - Terraform version
   - AWS CLI version
   - Error messages
   - Steps to reproduce

---

**Made with ❤️ for the Amazon Connect community**
