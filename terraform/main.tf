provider "aws" {
  region = var.aws_region
}

resource "aws_dynamodb_table" "okta_alerts" {
  name           = var.dynamodb_table
  hash_key       = "group_name"
  range_key      = "timestamp"
  billing_mode   = "PAY_PER_REQUEST"

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

resource "aws_iam_role" "lambda_exec" {
  name = "okta_lambda_exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

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

resource "aws_apigatewayv2_api" "okta_api" {
  name          = "okta-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.okta_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.webhook_handler.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.okta_api.id
  route_key = "POST /okta-webhook"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.okta_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.okta_api.execution_arn}/*/*"
}
