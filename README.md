# Amazon Connect Cross-Account Analytics

A Terraform-based solution for setting up cross-account Amazon Connect analytics using AWS Lake Formation and resource links.

## Overview

This project enables secure cross-account access to Amazon Connect data from a producer account to a consumer account using Lake Formation resource links and proper permission management.

## Architecture

```
PRODUCER ACCOUNT
├── connect_datalake Database
│   ├── users Table
│   ├── contacts Table
│   └── agent_hierarchy_groups Table
│
└── Lake Formation Permissions
    └── SELECT on target tables for consumer Lambda role

CONSUMER ACCOUNT
├── connect_analytics_consumer Database
│   ├── users_link ← Resource Link
│   ├── contacts_link ← Resource Link
│   └── agent_hierarchy_groups_link ← Resource Link
│
├── Lambda Role (connect-analytics-lambda-execution-role)
│   └── Lake Formation Permissions
│
└── Analytics Lambda Function
    └── Exports data to S3
```

## Prerequisites

- AWS CLI configured with credentials for both accounts
- Terraform >= 1.0
- Lake Formation admin permissions in both accounts
- Cross-account trust relationship established

## Quick Start

### 1. Configure Variables

Create `terraform.tfvars`:

```hcl
# Account Configuration
producer_account_id = "PRODUCER_ACCOUNT_ID"
consumer_account_id = "CONSUMER_ACCOUNT_ID"

# Database Configuration
producer_database_name = "connect_datalake"
consumer_database_name = "connect_analytics_consumer"

# Project Configuration
project_name = "connect-analytics"
environment  = "production"
region       = "ap-southeast-2"

# Feature Flags
enable_resource_links = true
enable_lambda_export  = true

# Lambda Configuration
lambda_role_name = "connect-analytics-lambda-execution-role"
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Plan and Apply

```bash
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

## Core Components

### Terraform Files

| File | Purpose |
|------|---------|
| `main.tf` | Main infrastructure configuration |
| `variables.tf` | Variable definitions and defaults |
| `resource_links.tf` | Cross-account resource links |
| `lakeformation_permissions.tf` | Lake Formation permissions |
| `lambda.tf` | Lambda function and IAM roles |
| `terraform.tfvars.example` | Example configuration |

### Shell Scripts

| Script | Purpose |
|--------|---------|
| `export_table_metadata.sh` | Export table metadata to CSV |
| `grant_lambda_permissions.sh` | Grant Lambda execution permissions |
| `recreate_resource_links.sh` | Recreate resource links if needed |
| `verify_deployment.sh` | Verify deployment status |

## Configuration

### Required Variables

- `producer_account_id` - AWS account ID of the Connect data producer
- `consumer_account_id` - AWS account ID of the analytics consumer
- `producer_database_name` - Source database name in producer account
- `consumer_database_name` - Target database name in consumer account

### Optional Variables

- `enable_resource_links` - Enable cross-account resource links (default: true)
- `enable_lambda_export` - Enable Lambda export functionality (default: true)
- `lambda_role_name` - Name of the Lambda execution role
- `project_name` - Project name for resource tagging
- `environment` - Environment identifier

## Permission Model

This implementation uses the correct Lake Formation permission model:

### Consumer Account
- **DESCRIBE** permissions on resource links
- Allows metadata access to linked tables

### Producer Account
- **SELECT** permissions on target tables
- Allows data access through resource links

### Cross-Account Access
Resource links bridge the two accounts, enabling the consumer to query producer data while maintaining security boundaries.

## Deployment

### Step 1: Consumer Account Setup

Deploy the consumer account resources first:

```bash
# Ensure AWS CLI is configured for consumer account
aws sts get-caller-identity

# Deploy consumer resources
terraform apply -var-file=terraform.tfvars
```

### Step 2: Producer Account Setup

Switch to producer account credentials and apply Lake Formation permissions:

```bash
# Switch to producer account profile
export AWS_PROFILE=producer-account

# Apply producer permissions
terraform apply -var-file=terraform.tfvars \
  -target=aws_lakeformation_permissions.producer_permissions
```

### Step 3: Verify Deployment

Run the verification script:

```bash
./verify_deployment.sh
```

## Validation

### Check Resource Links

```bash
aws glue get-tables \
  --database-name connect_analytics_consumer \
  --query 'TableList[?contains(Name, `_link`)]'
```

### Test Cross-Account Query

```bash
aws athena start-query-execution \
  --work-group connect_analytics_workgroup \
  --query-string "SELECT COUNT(*) FROM connect_analytics_consumer.users_link LIMIT 10"
```

### Check Permissions

```bash
# Consumer permissions
aws lakeformation list-permissions \
  --principal "DataLakePrincipalIdentifier=arn:aws:iam::CONSUMER_ACCOUNT_ID:role/connect-analytics-lambda-execution-role"
```

## Lambda Export Function

The Lambda function exports Amazon Connect data to S3:

### Features
- Exports users, contacts, and agent hierarchy data
- Configurable export schedules
- Error handling and retry logic
- CloudWatch logging

### Configuration

```hcl
enable_lambda_export = true
lambda_role_name    = "connect-analytics-lambda-execution-role"
```

### Manual Export

```bash
./grant_lambda_permissions.sh
```

## Troubleshooting

### Common Issues

#### Resource Links Not Visible
- Verify producer account has Lake Formation admin permissions
- Check RAM share acceptance status
- Validate cross-account trust relationship

#### Permission Errors
- Ensure both consumer and producer permissions are granted
- Verify IAM role ARNs are correct
- Check Lake Formation permission propagation

#### Lambda Failures
- Verify Lambda role has necessary permissions
- Check CloudWatch logs for error details
- Ensure VPC configuration is correct

### Debug Mode

Enable detailed logging:

```hcl
enable_cloudwatch_logging = true
enable_detailed_monitoring = true
```

## Maintenance

### Regular Tasks

1. **Permission Validation**: Monthly verification of cross-account permissions
2. **Resource Link Health**: Quarterly check of resource link status
3. **Lambda Monitoring**: Weekly review of export function logs
4. **Cost Optimization**: Monthly review of Athena query costs

### Backup and Recovery

- **Terraform State**: Regular backups of terraform.tfstate files
- **Permission Documentation**: Export current Lake Formation permissions
- **Configuration Backup**: Version control of terraform.tfvars

## Cost Considerations

### AWS Service Costs
- **Lake Formation**: No additional cost
- **Athena**: $5 per TB scanned (queries)
- **Lambda**: $0.20 per 1M requests + compute time
- **CloudWatch Logs**: ~$5-10/month (configurable)

### Cost Optimization
- Use result caching for Athena queries
- Configure appropriate S3 lifecycle policies
- Set CloudWatch log retention periods
- Monitor Lambda execution times

## Security

### Implemented Controls
- **Least Privilege**: Table-specific permissions only
- **Role Separation**: Separate roles for different functions
- **Audit Logging**: CloudTrail integration
- **Cross-Account Governance**: Controlled resource sharing

### Compliance
- **Data Privacy**: No sensitive data stored in Terraform state
- **Access Control**: IAM role-based access
- **Change Management**: Terraform state tracking
- **Audit Trail**: Complete permission change logging

## Archive

Additional documentation and test files are stored in the `archive/` directory:
- Historical analysis documents
- Test scripts and results
- Implementation guides
- Technical validation reports

## Support

### Getting Help
1. Check `archive/` directory for detailed technical documentation
2. Review CloudWatch logs for Lambda and Athena errors
3. Verify Terraform state for resource configuration
4. Consult AWS documentation for Lake Formation permissions

### Useful Commands

```bash
# Check current AWS identity
aws sts get-caller-identity

# List Glue databases
aws glue get-databases --query "DatabaseList[].Name"

# List Lake Formation permissions
aws lakeformation list-permissions --principal "DataLakePrincipalIdentifier=arn:aws:iam::CONSUMER_ACCOUNT_ID:role/connect-analytics-lambda-execution-role"

# Test Athena query
aws athena start-query-execution --work-group connect_analytics_workgroup --query-string "SELECT 1"
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Version History

- **v2.0** - Enhanced automation with ~90% automation level
- **v1.0** - Initial cross-account implementation

---

**Note**: This project implements the validated Lake Formation permission model for cross-account Amazon Connect analytics. Ensure you have the necessary AWS permissions and cross-account trust relationships before deployment.
