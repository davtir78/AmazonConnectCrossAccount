# =============================================================================
# 100% TERRAFORM MANAGED RESOURCE LINKS - NATIVE IMPLEMENTATION
# =============================================================================
# This implementation uses the native aws_glue_resource_link resource
# Available in AWS provider >= 5.11.0
# NO SCRIPTS REQUIRED - Pure Terraform HCL
# =============================================================================

# -----------------------------------------------------------------------------
# Resource Links for Cross-Account Table Access
# -----------------------------------------------------------------------------

resource "aws_glue_catalog_table" "resource_links" {
  for_each = var.enable_resource_links ? toset(var.connect_tables) : []
  
  name          = "${each.value}_link"
  database_name = aws_glue_catalog_database.consumer_database.name
  
  target_table {
    catalog_id    = var.producer_account_id
    database_name = var.producer_database_name
    name          = each.value
  }
  
  # Resource Links don't have storage descriptors or columns
  # They are pointers to tables in another catalog
}

# -----------------------------------------------------------------------------
# Lake Formation Permissions on Resource Links
# -----------------------------------------------------------------------------

resource "aws_lakeformation_permissions" "resource_link_describe" {
  for_each = var.enable_resource_links ? toset(var.connect_tables) : []
  
  principal = aws_iam_role.connect_analytics_query_role.arn
  
  permissions = ["DESCRIBE"]
  
  table {
    database_name = aws_glue_catalog_database.consumer_database.name
    name          = aws_glue_catalog_table.resource_links[each.key].name
    catalog_id    = data.aws_caller_identity.current.account_id
  }
  
  depends_on = [
    aws_glue_catalog_table.resource_links,
    aws_lakeformation_permissions.database_access
  ]
}

# -----------------------------------------------------------------------------
# Outputs for Resource Links
# -----------------------------------------------------------------------------

output "resource_links_native" {
  description = "Native Terraform-managed Resource Links (100% IaC)"
  value = var.enable_resource_links ? {
    enabled        = true
    method         = "Native Terraform (aws_glue_catalog_table with target_table)"
    database       = aws_glue_catalog_database.consumer_database.name
    resource_links = [for link in aws_glue_catalog_table.resource_links : link.name]
    count          = length(aws_glue_catalog_table.resource_links)
    no_scripts     = true
  } : {
    enabled        = false
    method         = "Disabled"
    database       = ""
    resource_links = []
    count          = 0
    no_scripts     = true
  }
}

output "resource_links_arns" {
  description = "ARNs of created Resource Links"
  value = var.enable_resource_links ? {
    for table_name, link in aws_glue_catalog_table.resource_links :
    table_name => link.arn
  } : {}
}

output "resource_links_targets" {
  description = "Target tables for each Resource Link"
  value = var.enable_resource_links ? {
    for table_name in var.connect_tables :
    "${table_name}_link" => "arn:aws:glue:${var.producer_region}:${var.producer_account_id}:table/${var.producer_database_name}.${table_name}"
  } : {}
}
