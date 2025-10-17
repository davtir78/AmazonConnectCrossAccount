#------------------------------------------------------------------------------
# AMAZON CONNECT ANALYTICS DATA LAKE CONSUMER - LAMBDA EXPORT
#------------------------------------------------------------------------------
# Lambda function for exporting Amazon Connect users data to S3
#
# LAMBDA ARCHITECTURE:
# - Scheduled execution via EventBridge (cron-based)
# - Queries Amazon Connect data via Athena and Resource Links
# - Exports results to S3 in JSON format with date partitioning
# - Handles errors gracefully with comprehensive logging
#
# USE CASES:
# - Automated daily user data exports
# - Integration with downstream systems
# - Data archiving and backup
# - Reporting and analytics workflows
#
# DEPENDENCIES:
# - Requires Lake Formation permissions on Resource Links
# - Needs Athena workgroup access
# - S3 bucket for output storage
# - IAM role with proper permissions

#------------------------------------------------------------------------------
# LAMBDA FUNCTION FOR USERS EXPORT
#------------------------------------------------------------------------------
# This Lambda function demonstrates how to programmatically access
# Amazon Connect analytics data via Resource Links and Athena

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

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.project_name}-Lambda-Users-Export"
      Description = "Lambda for Amazon Connect users export"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs[0],
    aws_iam_role_policy_attachment.lambda_athena[0],
    aws_iam_role_policy_attachment.lambda_s3[0],
    aws_cloudwatch_log_group.lambda_logs[0]
  ]
}

#------------------------------------------------------------------------------
# LAMBDA IAM ROLE
#------------------------------------------------------------------------------

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

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.project_name}-Lambda-Role"
      Description = "Lambda execution role"
    }
  )
}

#------------------------------------------------------------------------------
# LAMBDA IAM POLICIES
#------------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  count      = var.enable_lambda_export ? 1 : 0
  role       = aws_iam_role.lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_athena" {
  count      = var.enable_lambda_export ? 1 : 0
  role       = aws_iam_role.lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  count      = var.enable_lambda_export ? 1 : 0
  role       = aws_iam_role.lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy" "lambda_lakeformation" {
  count = var.enable_lambda_export ? 1 : 0
  name  = "${var.project_name}-lambda-lf-policy"
  role  = aws_iam_role.lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CLOUDWATCH LOG GROUP FOR LAMBDA
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_lambda_export ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-users-export"
  retention_in_days = 7

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.project_name}-Lambda-Logs"
      Description = "Lambda CloudWatch log group"
    }
  )
}

#------------------------------------------------------------------------------
# EVENTBRIDGE SCHEDULE FOR LAMBDA
#------------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  count               = var.enable_lambda_export ? 1 : 0
  name                = "${var.project_name}-lambda-schedule"
  description         = "Schedule for Amazon Connect users export"
  schedule_expression = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.project_name}-Lambda-Schedule"
      Description = "EventBridge schedule for Lambda"
    }
  )
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  count     = var.enable_lambda_export ? 1 : 0
  rule      = aws_cloudwatch_event_rule.lambda_schedule[0].name
  target_id = "LambdaTarget"
  arn       = aws_lambda_function.users_export[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_lambda_export ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.users_export[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule[0].arn
}

#------------------------------------------------------------------------------
# S3 BUCKET FOR LAMBDA CODE
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "lambda_bucket" {
  count  = var.enable_lambda_export ? 1 : 0
  bucket = "${var.project_name}-lambda-code-${random_string.poc_suffix.result}"

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.project_name}-Lambda-Code-Bucket"
      Description = "S3 bucket for Lambda deployment package"
    }
  )
}

resource "aws_s3_bucket_versioning" "lambda_bucket" {
  count  = var.enable_lambda_export ? 1 : 0
  bucket = aws_s3_bucket.lambda_bucket[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_bucket" {
  count  = var.enable_lambda_export ? 1 : 0
  bucket = aws_s3_bucket.lambda_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#------------------------------------------------------------------------------
# LAMBDA DEPLOYMENT PACKAGE
#------------------------------------------------------------------------------

data "archive_file" "lambda_zip" {
  count       = var.enable_lambda_export ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/lambda_package"
  output_path = "${path.module}/lambda_users_export.zip"
  
  depends_on = [
    null_resource.lambda_package_dir
  ]
}

# Create directory for Lambda package
resource "null_resource" "lambda_package_dir" {
  count = var.enable_lambda_export ? 1 : 0
  
  provisioner "local-exec" {
    command     = "if not exist lambda_package mkdir lambda_package && copy /Y lambda_function.py lambda_package\\"
    interpreter = ["cmd", "/C"]
  }
  
  depends_on = [
    local_file.lambda_function
  ]
  
  triggers = {
    lambda_code = local_file.lambda_function[0].content
  }
}

resource "aws_s3_object" "lambda_code" {
  count  = var.enable_lambda_export ? 1 : 0
  bucket = aws_s3_bucket.lambda_bucket[0].id
  key    = "lambda_users_export.zip"
  source = data.archive_file.lambda_zip[0].output_path

  etag = data.archive_file.lambda_zip[0].output_md5
}

#------------------------------------------------------------------------------
# LAMBDA FUNCTION CODE
#------------------------------------------------------------------------------

resource "local_file" "lambda_function" {
  count    = var.enable_lambda_export ? 1 : 0
  filename = "${path.module}/lambda_function.py"
  content  = <<-EOT
import json
import boto3
import os
import datetime
from urllib.parse import unquote_plus

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
    
    try:
        # Generate date-based partition
        current_date = datetime.datetime.utcnow()
        date_partition = current_date.strftime('%Y/%m/%d')
        output_key = f"{output_prefix}/{date_partition}/users_data.json"
        
        # Simple query for testing - use fully qualified table name
        query = f"""
        SELECT 
            user_id,
            agent_username,
            agent_email,
            first_name,
            last_name,
            mobile,
            is_active
        FROM {athena_database}.{table_name}
        WHERE 1=1
        LIMIT 100
        """
        
        print(f"Executing query: {query}")
        
        # Start Athena query
        response = athena.start_query_execution(
            QueryString=query,
            QueryExecutionContext={
                'Database': athena_database
            },
            WorkGroup=athena_workgroup,
            ResultConfiguration={
                'OutputLocation': f's3://{output_bucket}/temp-results/'
            }
        )
        
        query_execution_id = response['QueryExecutionId']
        print(f"Query started with ID: {query_execution_id}")
        
        # Wait for query completion
        query_status = None
        while query_status != 'SUCCEEDED':
            response = athena.get_query_execution(QueryExecutionId=query_execution_id)
            query_status = response['QueryExecution']['Status']['State']
            
            if query_status == 'FAILED':
                error_message = response['QueryExecution']['Status'].get('StateChangeReason', 'Unknown error')
                raise Exception(f"Query failed: {error_message}")
            elif query_status == 'CANCELLED':
                raise Exception("Query was cancelled")
            
            print(f"Query status: {query_status}")
            import time
            time.sleep(2)
        
        # Get query results
        results_response = athena.get_query_results(QueryExecutionId=query_execution_id)
        
        # Process results
        users_data = []
        
        # Extract column names from metadata
        columns = [col['Name'] for col in results_response['ResultSet']['ResultSetMetadata']['ColumnInfo']]
        
        # Process data rows (skip header row if present)
        for row in results_response['ResultSet']['Rows'][1:]:
            row_data = {}
            for i, col in enumerate(row['Data']):
                if i < len(columns):
                    row_data[columns[i]] = col.get('VarCharValue', '')
            users_data.append(row_data)
        
        # Create JSON output
        output_data = {
            'export_timestamp': current_date.isoformat(),
            'total_records': len(users_data),
            'data': users_data
        }
        
        # Upload to S3
        s3.put_object(
            Bucket=output_bucket,
            Key=output_key,
            Body=json.dumps(output_data, indent=2, default=str),
            ContentType='application/json'
        )
        
        print(f"Successfully exported {len(users_data)} users to s3://{output_bucket}/{output_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Users export completed successfully',
                'records_exported': len(users_data),
                'output_location': f"s3://{output_bucket}/{output_key}",
                'query_execution_id': query_execution_id
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Lambda execution failed',
                'message': str(e)
            })
        }
EOT
}
