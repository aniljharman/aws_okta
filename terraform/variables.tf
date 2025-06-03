variable "aws_region" {
  default = "us-east-1"
}

variable "dynamodb_table" {
  default = "OktaGroupRemovals"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL"
  type        = string
}
