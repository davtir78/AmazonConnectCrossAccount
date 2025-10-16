# Lambda Lake Formation Permissions Setup Guide

## Overview

This guide provides step-by-step instructions to grant Lake Formation permissions to the Lambda function after Terraform deployment. This is a **required one-time setup** to enable the Lambda function to query Amazon Connect data.

## Why This Step Is Required

The Lambda function needs Lake Formation permissions to query resource links, but these cannot be granted automatically via Terraform because:
1. Resource links are created by a bash script (not tracked in Terraform state)
2. Lake Formation permissions require the tables to exist first
3. The hybrid deployment approach prevents automatic permission grants

**This is a one-time manual setup that takes approximately 5 minutes.**

## Prerequisites

- ✅ Terraform deployment completed successfully
- ✅ Resource links created (32 tables ending in `_link`)
- ✅ Lambda function deployed: `connect-analytics-users-export`

## Step-by-Step Instructions

### Method 1: AWS Console (Recommended - Most Reliable)

#### Step 1: Navigate to Lake Formation

1. Open AWS Console
2. Go to **Lake Formation** service
3. Ensure you're in the correct region (e.g., `ap-southeast-2`)

#### Step 2: Grant Database Permissions

1. In Lake Formation, click **Permissions** in the left menu
2. Click **Data lake permissions**
3. Click **Grant** button

4. Configure the grant:
   - **Principals:**
     - Select **IAM users and roles**
     - Choose: `connect-analytics-lambda-execution-role`
   
   - **LF-Tags or catalog resources:**
     - Select **Named data catalog resources**
   
   - **Databases:**
     - Choose: `connect_analytics_consumer`
   
   - **Database permissions:**
     - Check: ☑ **Describe**
   
   - **Grantable permissions:**
     - Leave unchecked

5. Click **Grant**

#### Step 3: Grant DESCRIBE on Resource Links

1. Click "Grant" button again

2. Configure the grant:
   - **Principals:**
     - Select **IAM users and roles**
     - Choose: `connect-analytics-lambda-execution-role`
   
   - **LF-Tags or catalog resources:**
     - Select **Named data catalog resources**
   
   - **Databases:**
     - Choose: `connect_analytics_consumer`
   
   - **Tables:**
     - Select **All tables** (grants on all resource links)
     - OR select individual tables: `users_link`, `contacts_link`, etc.
   
   - **Table permissions:**
     - Check: ☑ **Describe** ONLY
   
   - **Grantable permissions:**
     - Leave unchecked

3. Click **Grant**

#### Step 4: Grant SELECT on Target Tables (Critical!)

**IMPORTANT:** This is the second required step per AWS documentation. You must grant SELECT on the *target tables* behind the resource links.

1. In Lake Formation Console, go to **Tables**

2. For each resource link (or select all):
   - Select the resource link (e.g., `users_link`)
   - Click **Actions** → **Grant on target**
   
3. Configure the grant:
   - **Principals:**
     - Select **IAM users and roles**
     - Choose: `connect-analytics-lambda-execution-role`
   
   - **Table permissions:**
     - Check: ☑ **Select**
   
   - **Grantable permissions:**
     - Leave unchecked

4. Click **Grant**

5. Repeat for all resource links you want the Lambda to access

**Note:** The "Grant on target" option grants permissions on the underlying producer table, not the resource link itself. This is required for queries to work.

#### Step 4: Verify Permissions

Check that permissions were granted:

1. In Lake Formation, go to **Permissions** → **Data lake permissions**
2. Filter by Principal: `connect-analytics-lambda-execution-role`
3. You should see:
   - Database: `connect_analytics_consumer` with `DESCRIBE` permission
   - Tables: All tables with `DESCRIBE` and `SELECT` permissions

### Method 2: AWS CLI (Alternative)

If you prefer CLI, use these commands:

```bash
# Set variables
LAMBDA_ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/connect-analytics-lambda-execution-role"
DATABASE="connect_analytics_consumer"

# Grant database permissions
aws lakeformation grant-permissions \
  --principal DataLakePrincipalIdentifier=$LAMBDA_ROLE_ARN \
  --permissions "DESCRIBE" \
  --resource "{\"Database\":{\"CatalogId\":\"$(aws sts get-caller-identity --query Account --output text)\",\"Name\":\"$DATABASE\"}}"

# Grant table permissions (all tables)
aws lakeformation grant-permissions \
  --principal DataLakePrincipalIdentifier=$LAMBDA_ROLE_ARN \
  --permissions "DESCRIBE" "SELECT" \
  --resource "{\"Table\":{\"CatalogId\":\"$(aws sts get-caller-identity --query Account --output text)\",\"DatabaseName\":\"$DATABASE\",\"TableWildcard\":{}}}"
```

**Note:** The CLI method grants permissions on ALL tables in the database using the wildcard. This is simpler than granting permissions on each individual resource link.

## Testing the Lambda Function

After granting permissions, test the Lambda function:

### Test 1: Manual Invocation

```bash
# Invoke the Lambda function
aws lambda invoke \
  --function-name connect-analytics-users-export \
  --payload '{}' \
  response.json

# Check the response
cat response.json
```

**Expected Output:**
```json
{
  "statusCode": 200,
  "body": "{\"message\": \"Query executed successfully\", \"query_id\": \"...\", \"output_location\": \"s3://...\"}"
}
```

### Test 2: Check CloudWatch Logs

```bash
# View recent logs
aws logs tail /aws/lambda/connect-analytics-users-export --follow

# Or view in AWS Console
# CloudWatch → Log groups → /aws/lambda/connect-analytics-users-export
```

**Expected Log Output:**
```
START RequestId: ...
Executing query: SELECT user_id, username, email FROM users_link LIMIT 100
Query started with ID: ...
Query status: SUCCEEDED
Query completed successfully
END RequestId: ...
```

### Test 3: Verify Query Results

```bash
# Get the S3 output location from the Lambda response
OUTPUT_LOCATION="s3://connect-analytics-athena-results-<account-id>/lambda-exports/users_export_<timestamp>.csv"

# Download and view the results
aws s3 cp $OUTPUT_LOCATION ./users_export.csv
head users_export.csv
```

## Troubleshooting

### Error: "Insufficient Lake Formation permission(s)"

**Cause:** Permissions not granted correctly

**Solution:**
1. Verify the Lambda role name is exactly: `connect-analytics-lambda-execution-role`
2. Check permissions in Lake Formation Console
3. Ensure you granted permissions on the correct database: `connect_analytics_consumer`
4. Try granting permissions via Console instead of CLI

### Error: "Table StorageDescriptor is null"

**Cause:** Resource links don't have schemas

**Solution:**
```bash
# Recreate resource links with schemas
bash recreate_resource_links.sh

# Verify schema populated
aws glue get-table \
  --database-name connect_analytics_consumer \
  --name users_link \
  --query "Table.[StorageDescriptor.Columns[0].Name,IsRegisteredWithLakeFormation]"
```

### Error: "Access Denied" when querying

**Cause:** RAM share not accepted or Lake Formation permissions missing

**Solution:**
1. Check RAM share status:
   ```bash
   aws ram get-resource-share-invitations
   ```

2. Accept if pending:
   ```bash
   aws ram accept-resource-share-invitation --resource-share-invitation-arn <arn>
   ```

3. Re-grant Lake Formation permissions

### Lambda Function Times Out

**Cause:** Query taking too long or Athena workgroup issue

**Solution:**
1. Check Athena workgroup exists:
   ```bash
   aws athena get-work-group --work-group connect_analytics_workgroup
   ```

2. Increase Lambda timeout in `lambda.tf`:
   ```hcl
   timeout = 300  # 5 minutes
   ```

3. Redeploy:
   ```bash
   terraform apply
   ```

## Verification Checklist

After setup, verify:

- [ ] Lake Formation permissions granted to Lambda role
- [ ] Database permission: `DESCRIBE` on `connect_analytics_consumer`
- [ ] Table permissions: `DESCRIBE` and `SELECT` on all tables
- [ ] Lambda function invokes successfully
- [ ] CloudWatch logs show "Query completed successfully"
- [ ] Query results appear in S3
- [ ] No "Insufficient permissions" errors

## Automated Schedule

Once permissions are set up, the Lambda function will run automatically:

- **Schedule:** Daily at 2 AM UTC (configurable in `terraform.tfvars`)
- **Trigger:** EventBridge rule
- **Output:** S3 bucket with timestamped CSV files

To check scheduled executions:

```bash
# View EventBridge rule
aws events describe-rule --name connect-analytics-lambda-schedule

# View recent Lambda executions
aws lambda list-invocations --function-name connect-analytics-users-export
```

## Summary

**Time Required:** ~5 minutes (one-time setup)

**Steps:**
1. ✅ Grant database permissions via Lake Formation Console
2. ✅ Grant table permissions via Lake Formation Console  
3. ✅ Test Lambda function
4. ✅ Verify query results in S3

**Result:** Lambda function can now query Amazon Connect data automatically on schedule!

---

**Need Help?** Check [LAMBDA_LIMITATION.md](LAMBDA_LIMITATION.md) for detailed technical explanation of why this manual step is required.
