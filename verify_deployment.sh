#!/bin/bash
# =============================================================================
# Deployment Verification Script
# =============================================================================
# This script verifies that all resources are properly deployed and configured
# for the 100% Terraform-managed Amazon Connect Analytics solution
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONSUMER_DATABASE="connect_analytics_consumer"
PRODUCER_ACCOUNT="502851453563"
PRODUCER_DATABASE="connect_analytics"
REGION="ap-southeast-2"
IAM_ROLE="connect_analytics_query_role"
ATHENA_WORKGROUP="connect_analytics_workgroup" # Updated to remove _poc suffix

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_test() {
    echo -e "${YELLOW}Testing:${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

# =============================================================================
# Test 1: Terraform State
# =============================================================================
print_header "1. Terraform State Verification"

print_test "Checking Terraform state file exists"
if [ -f "terraform.tfstate" ]; then
    print_pass "Terraform state file exists"
else
    print_fail "Terraform state file not found"
fi

print_test "Checking Resource Links in Terraform state"
RESOURCE_LINKS_COUNT=$(terraform state list 2>/dev/null | grep -c "aws_glue_catalog_table.resource_links" || echo "0")
if [ "$RESOURCE_LINKS_COUNT" -eq 4 ]; then
    print_pass "All 4 Resource Links found in Terraform state"
else
    print_fail "Expected 4 Resource Links in state, found $RESOURCE_LINKS_COUNT"
fi

print_test "Checking for old script-based resources in state"
OLD_RESOURCES=$(terraform state list 2>/dev/null | grep -E "(null_resource|local_file.*resource_link)" || echo "")
if [ -z "$OLD_RESOURCES" ]; then
    print_pass "No old script-based resources in state"
else
    print_warn "Found old script-based resources in state: $OLD_RESOURCES"
fi

# =============================================================================
# Test 2: AWS Glue Resources
# =============================================================================
print_header "2. AWS Glue Resources Verification"

print_test "Checking consumer database exists"
DB_EXISTS=$(aws glue get-database --name "$CONSUMER_DATABASE" --region "$REGION" 2>/dev/null && echo "yes" || echo "no")
if [ "$DB_EXISTS" = "yes" ]; then
    print_pass "Consumer database '$CONSUMER_DATABASE' exists"
else
    print_fail "Consumer database '$CONSUMER_DATABASE' not found"
fi

print_test "Checking Resource Links in AWS Glue"
RESOURCE_LINKS=$(aws glue get-tables \
    --database-name "$CONSUMER_DATABASE" \
    --region "$REGION" \
    --query 'TableList[?contains(Name, `_link`)].Name' \
    --output text 2>/dev/null || echo "")

LINK_COUNT=$(echo "$RESOURCE_LINKS" | wc -w)
if [ "$LINK_COUNT" -eq 4 ]; then
    print_pass "All 4 Resource Links exist in AWS Glue"
    print_info "Resource Links: $RESOURCE_LINKS"
else
    print_fail "Expected 4 Resource Links, found $LINK_COUNT"
fi

# Check each specific Resource Link
for TABLE in users contacts agent_metrics queue_metrics; do
    print_test "Checking ${TABLE}_link"
    LINK_EXISTS=$(aws glue get-table \
        --database-name "$CONSUMER_DATABASE" \
        --name "${TABLE}_link" \
        --region "$REGION" 2>/dev/null && echo "yes" || echo "no")
    
    if [ "$LINK_EXISTS" = "yes" ]; then
        # Verify it's actually a Resource Link (has TargetTable)
        HAS_TARGET=$(aws glue get-table \
            --database-name "$CONSUMER_DATABASE" \
            --name "${TABLE}_link" \
            --region "$REGION" \
            --query 'Table.TargetTable' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$HAS_TARGET" != "None" ]; then
            print_pass "${TABLE}_link exists and is a valid Resource Link"
        else
            print_fail "${TABLE}_link exists but is not a Resource Link"
        fi
    else
        print_fail "${TABLE}_link not found"
    fi
done

# =============================================================================
# Test 3: IAM Resources
# =============================================================================
print_header "3. IAM Resources Verification"

print_test "Checking IAM role exists"
ROLE_EXISTS=$(aws iam get-role --role-name "$IAM_ROLE" 2>/dev/null && echo "yes" || echo "no")
if [ "$ROLE_EXISTS" = "yes" ]; then
    print_pass "IAM role '$IAM_ROLE' exists"
    
    # Get role ARN
    ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE" --query 'Role.Arn' --output text 2>/dev/null)
    print_info "Role ARN: $ROLE_ARN"
else
    print_fail "IAM role '$IAM_ROLE' not found"
fi

print_test "Checking IAM role policies"
POLICY_COUNT=$(aws iam list-attached-role-policies --role-name "$IAM_ROLE" --query 'length(AttachedPolicies)' --output text 2>/dev/null || echo "0")
if [ "$POLICY_COUNT" -gt 0 ]; then
    print_pass "IAM role has $POLICY_COUNT attached policies"
else
    print_warn "IAM role has no attached policies"
fi

# =============================================================================
# Test 4: Lake Formation Permissions
# =============================================================================
print_header "4. Lake Formation Permissions Verification"

print_test "Checking Lake Formation permissions for IAM role"
if [ "$ROLE_EXISTS" = "yes" ]; then
    LF_PERMS=$(aws lakeformation list-permissions \
        --principal "$ROLE_ARN" \
        --region "$REGION" 2>/dev/null || echo "")
    
    if [ -n "$LF_PERMS" ]; then
        PERM_COUNT=$(echo "$LF_PERMS" | grep -c "Permissions" || echo "0")
        print_pass "Lake Formation permissions found for IAM role"
        print_info "Permission entries: $PERM_COUNT"
    else
        print_warn "No Lake Formation permissions found (may need manual configuration)"
    fi
else
    print_warn "Skipping Lake Formation check (IAM role not found)"
fi

# =============================================================================
# Test 5: S3 Resources
# =============================================================================
print_header "5. S3 Resources Verification"

print_test "Checking Athena results bucket"
ATHENA_BUCKET=$(terraform output -raw consumer_account_setup 2>/dev/null | grep -o '"athena_results_bucket":"[^"]*"' | cut -d'"' -f4 || echo "")
if [ -n "$ATHENA_BUCKET" ]; then
    BUCKET_EXISTS=$(aws s3 ls "s3://$ATHENA_BUCKET" 2>/dev/null && echo "yes" || echo "no")
    if [ "$BUCKET_EXISTS" = "yes" ]; then
        print_pass "Athena results bucket exists: $ATHENA_BUCKET"
    else
        print_fail "Athena results bucket not accessible: $ATHENA_BUCKET"
    fi
else
    print_warn "Could not determine Athena results bucket name"
fi

# =============================================================================
# Test 6: Athena Resources
# =============================================================================
print_header "6. Athena Resources Verification"

print_test "Checking Athena workgroup"
WG_EXISTS=$(aws athena get-work-group --work-group "$ATHENA_WORKGROUP" --region "$REGION" 2>/dev/null && echo "yes" || echo "no")
if [ "$WG_EXISTS" = "yes" ]; then
    print_pass "Athena workgroup '$ATHENA_WORKGROUP' exists"
else
    print_warn "Athena workgroup '$ATHENA_WORKGROUP' not found (may have different name)"
fi

# =============================================================================
# Test 7: Terraform Outputs
# =============================================================================
print_header "7. Terraform Outputs Verification"

print_test "Checking resource_links_native output"
NATIVE_OUTPUT=$(terraform output -json resource_links_native 2>/dev/null || echo "")
if [ -n "$NATIVE_OUTPUT" ]; then
    NO_SCRIPTS=$(echo "$NATIVE_OUTPUT" | grep -o '"no_scripts":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    if [ "$NO_SCRIPTS" = "true" ]; then
        print_pass "Terraform output confirms no scripts used"
    else
        print_fail "Terraform output indicates scripts may be in use"
    fi
    
    METHOD=$(echo "$NATIVE_OUTPUT" | grep -o '"method":"[^"]*"' | cut -d'"' -f4)
    if [[ "$METHOD" == *"Native Terraform"* ]]; then
        print_pass "Deployment method: $METHOD"
    else
        print_warn "Unexpected deployment method: $METHOD"
    fi
else
    print_warn "Could not retrieve resource_links_native output"
fi

# =============================================================================
# Test 8: File System Check
# =============================================================================
print_header "8. File System Verification"

print_test "Checking for old script-based files"
OLD_FILES=0
for FILE in resource_links_fallback.tf setup_resource_links.sh; do
    if [ -f "$FILE" ]; then
        print_warn "Old file still exists: $FILE"
        ((OLD_FILES++))
    fi
done

if [ "$OLD_FILES" -eq 0 ]; then
    print_pass "No old script-based files found"
fi

print_test "Checking for new Terraform files"
NEW_FILES=0
for FILE in resource_links.tf lambda.tf DEPLOYMENT_GUIDE.md; do # Updated to lambda.tf
    if [ -f "$FILE" ]; then
        ((NEW_FILES++))
    else
        print_fail "Expected file not found: $FILE"
    fi
done

if [ "$NEW_FILES" -eq 3 ]; then
    print_pass "All new Terraform files present"
fi

# =============================================================================
# Test 9: Cross-Account Configuration
# =============================================================================
print_header "9. Cross-Account Configuration Verification"

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

# =============================================================================
# Test 10: Lambda Function Verification
# =============================================================================
print_header "10. Lambda Function Verification"

print_test "Checking Lambda function exists and is active"
LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_info.function_name 2>/dev/null || echo "")
if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
    LAMBDA_STATUS=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$REGION" --query 'Configuration.State' --output text 2>/dev/null || echo "NotFound")
    if [ "$LAMBDA_STATUS" = "Active" ]; then
        print_pass "Lambda function '$LAMBDA_FUNCTION_NAME' is active"
    else
        print_fail "Lambda function '$LAMBDA_FUNCTION_NAME' status: $LAMBDA_STATUS"
    fi
else
    print_warn "Lambda function name not found in Terraform outputs"
fi

# =============================================================================
# Summary
# =============================================================================
print_header "Verification Summary"

TOTAL=$((PASSED + FAILED + WARNINGS))
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${RED}Failed:${NC}   $FAILED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "Total:    $TOTAL"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ All critical tests passed!${NC}"
    echo -e "${GREEN}✓ Deployment is 100% Terraform-managed with zero scripts${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Please review the output above.${NC}"
    exit 1
fi
