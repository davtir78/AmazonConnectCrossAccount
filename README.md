# Amazon Connect Analytics Cross-Account Data Sharing POC

## Overview

This proof of concept demonstrates how to share Amazon Connect analytics data lake across AWS accounts using 100% Terraform-managed infrastructure. The solution establishes secure cross-account data access using AWS Glue Resource Links, Lake Formation permissions, and Athena for querying.

## 🎯 POC Objectives

- **Cross-Account Data Sharing**: Enable secure access to Amazon Connect analytics data from producer to consumer accounts
- **100% Terraform Management**: Complete infrastructure as code with zero manual configuration
- **Production-Ready Security**: Implement least-privilege access and data governance
- **Scalable Architecture**: Support multiple tables and extensible for additional data sources

## 🏗️ Architecture

```
Producer Account (502851453563)    Consumer Account (Your Account)
┌─────────────────────────┐      ┌─────────────────────────┐
│ Amazon Connect Data     │      │                         │
│ Lake Formation DB       │◄─────┤ Glue Resource Links    │
│ (connect_analytics)     │      │ (connect_analytics_consumer)│
│                         │      │                         │
│ RAM Share               │      │ Athena Workgroup        │
│ (Shared with Consumer)  │      │ Lake Formation Tags     │
└─────────────────────────┘      │ IAM Role (Query Access) │
                                 │ S3 Bucket (Results)     │
                                 │ Lambda Function         │
                                 └─────────────────────────┘
```

## 📋 Prerequisites

### Required Tools
- Terraform >= 1.0
- AWS CLI >= 2.0
- Git

### AWS Permissions
Your AWS credentials need these permissions in the consumer account:
- Lake Formation: Full access
- Glue: Full access  
- Athena: Full access
- S3: Full access
- IAM: Full access
- CloudWatch: Full access
- Events: Full access
- Lambda: Full access (if using Lambda export)

### RAM Share Acceptance
Ensure the RAM share from the producer account has been accepted in your consumer account before deployment.

## 🚀 Quick Start

### 1. Clone and Configure
```bash
git clone <repository-url>
cd amazon-connect-cross-account-poc
```

### 2. Create Configuration File
Copy the example configuration:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:
```hcl
# Update these values for your environment
producer_account_id = "PRODUCER_ACCOUNT_ID"
consumer_account_id = "YOUR_ACCOUNT_ID"  # Leave empty to auto-detect

# Configure regions
producer_region = "us-east-1"      # Producer's region
consumer_region = "us-east-1"      # Your region

# Project settings
project_name = "connect-analytics"
environment  = "poc"

# Data configuration
connect_tables = [
  "users",
  "contacts", 
  "agent_metrics",
  "queue_metrics"
]
```

### 3. Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### 4. Validate Setup
```bash
# Run verification script
./verify_deployment.sh

# Test Athena query
aws athena start-query-execution \
  --query-string 'SELECT COUNT(*) FROM "connect_analytics_consumer"."users_link" LIMIT 10' \
  --work-group connect_analytics_workgroup
```

## 📁 Project Structure

```
amazon-connect-cross-account-poc/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Input variables
├── resource_links.tf          # Glue Resource Links configuration
├── lakeformation_permissions.tf # Lake Formation setup
├── lambda.tf                  # Lambda function (optional)
├── verify_deployment.sh       # Deployment validation script
├── terraform.tfvars.example   # Configuration template
└── README.md                  # This file
```

## 🔧 Configuration Options

### Core Settings

| Variable | Description | Required |
|----------|-------------|----------|
| `producer_account_id` | AWS Account ID of data producer | Yes |
| `consumer_account_id` | AWS Account ID of data consumer | Auto-detected |
| `producer_region` | Producer account region | Yes |
| `consumer_region` | Consumer account region | Yes |

### Data Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `connect_tables` | Tables to create Resource Links for | `["users", "contacts", "agent_metrics", "queue_metrics"]` |
| `producer_database_name` | Producer database name | `"connect_analytics"` |
| `consumer_database_name` | Consumer database name | `"connect_analytics_consumer"` |

### Optional Features

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_lambda_export` | Enable Lambda export function | `true` |
| `enable_lake_formation` | Enable Lake Formation setup | `true` |
| `enable_resource_links` | Enable Resource Links | `true` |

## 🏛️ What Gets Created

### Core Infrastructure
- **IAM Role**: `connect_analytics_query_role` with least-privilege access
- **S3 Bucket**: Athena query results storage with encryption
- **Glue Database**: Consumer database for Resource Links
- **Athena Workgroup**: Dedicated query environment
- **Lake Formation**: LF-Tags and permissions for data governance

### Cross-Account Resources
- **Resource Links**: Glue Resource Links for all specified tables
- **RAM Integration**: Utilizes accepted RAM share from producer
- **Secure Access**: Cross-account permissions via Lake Formation

### Optional Components
- **Lambda Function**: Automated data export (when enabled)
- **EventBridge Schedule**: Lambda execution schedule
- **CloudWatch Logs**: Monitoring and debugging

## 🔍 Validation and Testing

### Automated Verification
Run the comprehensive validation script:
```bash
./verify_deployment.sh
```

This script verifies:
- Terraform state consistency
- AWS resource creation
- Cross-account connectivity
- IAM permissions
- Lake Formation configuration

### Manual Testing

1. **Test Resource Links**
   ```bash
   aws glue get-tables --database-name connect_analytics_consumer
   ```

2. **Query Data via Athena**
   ```bash
   aws athena start-query-execution \
     --query-string 'SELECT * FROM "connect_analytics_consumer"."users_link" LIMIT 5' \
     --work-group connect_analytics_workgroup
   ```

3. **Verify Lambda Function** (if enabled)
   ```bash
   aws lambda invoke --function-name connect-analytics-users-export output.json
   ```

## 🔐 Security Features

### Implemented Controls
- **Least Privilege Access**: IAM roles with minimal required permissions
- **Encryption**: All S3 buckets use server-side encryption
- **Data Classification**: Lake Formation LF-Tags for categorization
- **Cross-Account Security**: Secure Resource Links with proper permissions
- **Audit Logging**: CloudTrail and CloudWatch integration

### Access Control Layers
1. **AWS RAM Share**: Producer controls shared resources
2. **Lake Formation**: Fine-grained data access permissions
3. **IAM Roles**: User and service access controls
4. **Resource Links**: Table-level cross-account access

## 🚨 Troubleshooting

### Common Issues

**RAM Share Not Accepted**
```
Error: Cannot access producer database
```
Solution: Ensure RAM share is accepted in producer account

**Permission Denied**
```
AccessDeniedException: Insufficient permissions
```
Solution: Verify IAM permissions include all required services

**Resource Link Creation Failed**
```
Cannot create resource link: Target not found
```
Solution: Confirm producer database and tables exist

### Debug Commands
```bash
# Check Terraform state
terraform show

# Verify AWS resources
aws glue get-database --name connect_analytics_consumer
aws lakeformation list-permissions

# Check logs
aws logs tail /aws/lambda/connect-analytics-users-export --follow
```

## 🧹 Clean Up

To remove all resources:
```bash
terraform destroy
```

This will remove:
- All created AWS resources
- S3 buckets and their contents
- IAM roles and policies
- Lambda functions
- Resource Links

## 📚 Additional Resources

- [AWS Lake Formation Documentation](https://docs.aws.amazon.com/lake-formation/)
- [Amazon Connect Analytics Guide](https://docs.aws.amazon.com/connect/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Cross-Account Data Sharing](https://docs.aws.amazon.com/whitepapers/latest/cross-account-data-sharing/)

## 🤝 Contributing

This is a proof of concept demonstrating cross-account data sharing patterns. For production use, consider:
- Enhanced monitoring and alerting
- Additional security controls
- Multi-region deployment
- Advanced data governance

## 📄 License

This project is provided as-is for educational and proof-of-concept purposes.

---

**Note**: This POC requires an existing RAM share from the producer account. Ensure the share is accepted before deployment.
