# SELECT Permissions Automation Solution

## Overview

This document describes the automated solution for granting SELECT permissions on target tables in cross-account Amazon Connect analytics setup. The solution addresses the critical missing piece in the original Terraform configuration.

## Problem Statement

The original Terraform code had **missing SELECT permissions** on target tables in the producer account, which prevented actual data access despite having resource links and DESCRIBE permissions.

### What Was Missing

1. **Producer Account SELECT Permissions**: No Terraform resources granted SELECT on target tables
2. **Consumer Account Resource Link Permissions**: SELECT permissions were commented out
3. **Cross-Account Access**: Required manual AWS CLI commands after Terraform deployment

## Solution Components

### 1. Enhanced Terraform Configuration

#### Updated `lakeformation_permissions.tf`

```hcl
# Producer Account SELECT Permissions on Target Tables
resource "aws_lakeformation_permissions" "producer_select_permissions" {
  for_each = var.enable_producer_permissions ? toset(var.connect_tables) : toset([])
  provider = aws.producer
  
  permissions = ["SELECT"]
  
  principal = "arn:aws:iam::${var.consumer_account_id}:role/${var.lambda_role_name}"
  
  table {
    catalog_id    = var.producer_account_id
    database_name = var.producer_database_name
    name          = each.key
  }
}

# Consumer Account DESCRIBE Permissions on Resource Links
resource "aws_lakeformation_permissions" "consumer_describe_permissions" {
  for_each = var.enable_resource_links ? toset(var.connect_tables) : toset([])
  provider = aws.consumer
  
  permissions = ["DESCRIBE"]
  
  principal = aws_iam_role.lambda_role[0].arn
  
  table {
    catalog_id    = local.consumer_account_id
    database_name = var.consumer_database_name
    name          = "${each.key}_link"
  }
}
```

#### New Variables in `variables.tf`

```hcl
variable "enable_producer_permissions" {
  description = "Enable SELECT permissions on producer account target tables"
  type        = bool
  default     = true
}

variable "lambda_role_name" {
  description = "Name of the Lambda execution role"
  type        = string
  default     = "connect-analytics-lambda-execution-role"
}
```

### 2. Automated Shell Script

#### `automate_select_permissions.sh`

A comprehensive bash script that automates the permission granting process with the following features:

- **Prerequisites Check**: Validates AWS CLI, account access, and role existence
- **Dry Run Mode**: Shows commands without executing them
- **Test Mode**: Validates current permissions without changes
- **Cross-Account Support**: Handles both producer and consumer account permissions
- **Error Handling**: Comprehensive error checking and logging
- **Progress Tracking**: Detailed output showing what's being processed

#### Usage Examples

```bash
# Test current permissions (no changes)
./automate_select_permissions.sh --test

# Show what would be done (dry run)
./automate_select_permissions.sh --dry-run

# Actually grant permissions
./automate_select_permissions.sh
```

### 3. Permission Architecture

#### Correct Permission Model

```
Producer Account (502851453563)
├── Target Tables (e.g., users, contacts)
│   └── SELECT permissions for consumer Lambda role
│
Consumer Account (657416661258)
├── Resource Links (e.g., users_link, contacts_link)
│   └── DESCRIBE permissions for Lambda role
│
Cross-Account Access
├── Resource Link points to Producer Target Table
├── Consumer role has DESCRIBE on resource link
└── Consumer role has SELECT on target table
```

#### Why This Works

1. **Resource Links**: Provide metadata access to remote tables
2. **DESCRIBE on Links**: Allows viewing table structure and metadata
3. **SELECT on Targets**: Allows actual data querying
4. **Cross-Account**: Lake Formation handles the secure data access

## Implementation Steps

### Option 1: Full Terraform Automation

1. **Update Configuration**:
   ```bash
   # Enable producer permissions in terraform.tfvars
   enable_producer_permissions = true
   enable_resource_links = true
   ```

2. **Deploy with Terraform**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Verify Permissions**:
   ```bash
   ./automate_select_permissions.sh --test
   ```

### Option 2: Shell Script Automation

1. **Run the Script**:
   ```bash
   chmod +x automate_select_permissions.sh
   ./automate_select_permissions.sh
   ```

2. **Monitor Progress**:
   - Script shows each table being processed
   - Provides success/failure feedback
   - Includes test queries to validate access

### Option 3: Hybrid Approach

1. **Deploy Infrastructure with Terraform**:
   ```bash
   terraform apply -target=aws_glue_catalog_table.resource_links
   ```

2. **Grant Permissions with Script**:
   ```bash
   ./automate_select_permissions.sh
   ```

## Validation and Testing

### Test Cross-Account Access

```bash
# Test query using resource link
aws athena start-query-execution \
  --work-group "connect_analytics_workgroup" \
  --query-string "SELECT COUNT(*) FROM connect_analytics_consumer.users_link LIMIT 5"

# Check permissions
aws lakeformation list-permissions \
  --principal "DataLakePrincipalIdentifier=arn:aws:iam::657416661258:role/connect-analytics-lambda-execution-role" \
  --resource '{"Table":{"CatalogId":"502851453563","DatabaseName":"connect_datalake","Name":"users"}}'
```

### Expected Results

- ✅ Resource links exist in consumer account
- ✅ DESCRIBE permissions on resource links
- ✅ SELECT permissions on producer target tables
- ✅ Cross-account queries work correctly

## Troubleshooting

### Common Issues

1. **AccessDeniedException**: Missing Lake Formation admin permissions
   - Solution: Ensure Lake Formation admin rights in producer account

2. **InvalidInputException**: Resource links don't exist
   - Solution: Run Terraform to create resource links first

3. **Cross-account restrictions**: Wrong account permissions
   - Solution: Use script from consumer account with proper producer access

### Debug Commands

```bash
# Check current account
aws sts get-caller-identity

# Verify resource links
aws glue get-tables --database-name "connect_analytics_consumer" --query "TableList[?contains(Name, '_link')]"

# Check permissions
aws lakeformation list-permissions --principal "DataLakePrincipalIdentifier=arn:aws:iam::657416661258:role/connect-analytics-lambda-execution-role"
```

## Security Considerations

### Principle of Least Privilege

- **SELECT only**: Grant only necessary permissions
- **Specific tables**: Don't use wildcard permissions
- **Role-based**: Use IAM roles, not users

### Audit and Monitoring

- **CloudTrail**: Log all Lake Formation API calls
- **Permission reviews**: Regular audits of granted permissions
- **Access patterns**: Monitor who accesses what data

## Best Practices

### Deployment

1. **Test first**: Always use `--test` and `--dry-run` modes
2. **Incremental**: Grant permissions for a few tables first
3. **Validate**: Test queries after each batch

### Maintenance

1. **Monitor**: Regular permission audits
2. **Update**: Add new tables to configuration
3. **Document**: Keep track of granted permissions

### Security

1. **Rotate**: Regular credential rotation
2. **Limit**: Minimize permission scope
3. **Audit**: Enable detailed logging

## Conclusion

This automated solution provides:

- ✅ **Complete automation** of SELECT permissions
- ✅ **Cross-account access** without manual intervention
- ✅ **Validation and testing** capabilities
- ✅ **Error handling** and troubleshooting
- ✅ **Security best practices** implementation

The combination of enhanced Terraform configuration and the automated shell script provides a robust, repeatable solution for cross-account Amazon Connect analytics access.
