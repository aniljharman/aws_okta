output "api_url" {
  value = "${aws_apigatewayv2_api.okta_api.api_endpoint}/okta-webhook"
}
