# =============================================================================
# AWS Glue Resource Links Configuration - Updated Based on Working Analysis
# =============================================================================
# Direct resource link creation without RAM shares - based on successful manual setup
# Key insight: Resource links work directly with proper Lake Formation permissions
#
# ARCHITECTURAL DECISION:
# - Resource Links are virtual tables that point to producer account tables
# - They enable cross-account access without data duplication
# - Lake Formation permissions control access to these virtual tables
# - No RAM shares needed - Resource Links work directly with LF permissions

# -----------------------------------------------------------------------------
# Create Resource Links for Cross-Account Table Access
# -----------------------------------------------------------------------------

# Glue resource policy removed due to cross-account issues
# Resource links work with Lake Formation permissions directly

# TERRAFORM LIMITATION WORKAROUND:
# NOTE: Terraform AWS provider does not support storage_descriptor with target_table
# This is a known limitation where terraform cannot create resource links with
# storage_descriptor, which is required for automatic schema population.
#
# SOLUTION: Use local-exec provisioner to call AWS CLI which supports full functionality
# See recreate_resource_links.sh for the implementation details

# Automatically create resource links with storage_descriptor using AWS CLI
resource "null_resource" "resource_links_creator" {
  count = var.enable_resource_links ? 1 : 0
  
  # Triggers ensure recreation when configuration changes
  triggers = {
    tables_hash         = sha256(jsonencode(var.connect_tables))  # Recreate if table list changes
    database            = var.consumer_database_name             # Recreate if consumer DB changes
    producer_database   = var.producer_database_name             # Recreate if producer DB changes
  }
  
  # Create resource links using bash script that calls AWS CLI
  provisioner "local-exec" {
    command     = "bash ${path.module}/recreate_resource_links.sh"
    interpreter = ["bash", "-c"]
  }
  
  # Ensure consumer database exists before creating resource links
  depends_on = [
    aws_glue_catalog_database.consumer_database
  ]
}

# -----------------------------------------------------------------------------
# Grant Table Permissions to Consumer Account on Producer Side
# -----------------------------------------------------------------------------
# NOTE: These permissions are NOT needed when using RAM/Lake Formation shares
# The producer account has already shared access via RAM (Resource Access Manager)
# Commenting out to avoid cross-account permission errors

# resource "aws_lakeformation_permissions" "producer_table_access" {
#   for_each = var.enable_resource_links ? toset(var.connect_tables) : toset([])
#   provider = aws.producer
#   
#   permissions = ["DESCRIBE"]
#   
#   principal = local.consumer_account_id
#   
#   table {
#     catalog_id    = var.producer_account_id
#     database_name = var.producer_database_name
#     name          = each.key
#   }
#   
#   depends_on = []
# }

# -----------------------------------------------------------------------------
# Grant Database Permissions to Consumer Account on Producer Side
# -----------------------------------------------------------------------------
# NOTE: Not needed with RAM share - commenting out

# resource "aws_lakeformation_permissions" "producer_database_access" {
#   count    = var.enable_resource_links ? 1 : 0
#   provider = aws.producer
#   
#   permissions = ["DESCRIBE"]
#   
#   principal = local.consumer_account_id
#   
#   database {
#     catalog_id = var.producer_account_id
#     name       = var.producer_database_name
#   }
#   
#   depends_on = []
# }

# -----------------------------------------------------------------------------
# Apply LF-Tags to Producer Tables (if producer LF-Tags are configured)
# Note: This requires producer account Lake Formation admin access
# -----------------------------------------------------------------------------

# This section would be implemented in the producer account's Terraform
# For now, we assume producer tables are already tagged with the required LF-Tags

# -----------------------------------------------------------------------------
# Glue Catalog Resource Policy - Producer Account
# Note: Cross-account resource links don't require explicit catalog policies
# The existing Lake Formation permissions are sufficient
# -----------------------------------------------------------------------------

# Resource links work at the Lake Formation level, not Glue catalog policy level
# No Glue resource policy needed for resource links
