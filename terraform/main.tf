terraform {
  backend "s3" {
    bucket = "ajoseterraformstates"          
    key    = "okta-alerts/terraform.tfstate"    
    region = "us-east-1"                         
    encrypt = true                               
  }
}

provider "aws" {
  region = var.aws_region
}

# DynamoDB table to track removals
resource "aws_dynamodb_table" "okta_alerts" {
  name         = var.dynamodb_table
  hash_key     = "group_name"
  range_key    = "timestamp"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "group_name"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec" {
  name = "okta_lambda_exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach DynamoDB access policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamo_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# attach cloudwatch logs to lambda

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# Lambda Function to process Okta webhooks
resource "aws_lambda_function" "webhook_handler" {
  function_name = "okta-webhook-handler"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  filename      = "../lambda.zip"
  source_code_hash = filebase64sha256("../lambda.zip")

  environment {
    variables = {
      DDB_TABLE             = var.dynamodb_table
      SLACK_WEBHOOK_URL     = var.slack_webhook_url
      ALERT_THRESHOLD        = "5"
      ALERT_WINDOW_SECONDS   = "300"
    }
  }
}

# Create a new HTTP-based API Gateway to expose an endpoint for Okta webhooks
resource "aws_apigatewayv2_api" "okta_api" {
  name          = "okta-api"
  protocol_type = "HTTP"
}

# Integrate the Lambda function with API Gateway using AWS_PROXY
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                  = aws_apigatewayv2_api.okta_api.id
  integration_type        = "AWS_PROXY"
  integration_uri         = aws_lambda_function.webhook_handler.invoke_arn
  integration_method      = "POST"
  payload_format_version  = "2.0"
}

# Define the specific route (POST /okta-webhook) that will be called by Okta
resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.okta_api.id
  route_key = "POST /okta-webhook"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create a default stage for API Gateway and enable auto-deploy so no manual deployment needed
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.okta_api.id
  name        = "$default"
  auto_deploy = true
}

# Grant API Gateway permission to invoke the Lambda function
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowInvokeFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.okta_api.execution_arn}/*/*"
}