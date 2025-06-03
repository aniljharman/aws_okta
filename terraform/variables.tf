variable "aws_region" {
  type        = string
  description = "AWS region to deploy into"
}

variable "dynamodb_table" {
  type        = string
  description = "DynamoDB table name"
  default     = "OktaGroupRemovals"
}

variable "slack_webhook_url" {
  type        = string
  description = "Slack Incoming Webhook URL"
}

