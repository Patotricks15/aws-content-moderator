output "generate_api_endpoint" {
  description = "Invoke URL of the REST API's generate endpoint."
  value       = "${aws_api_gateway_stage.content_moderator.invoke_url}/generate"
}

output "coordinator_function_name" {
  description = "Name of the coordinator Lambda that orchestrates the AI services and the model endpoint."
  value       = aws_lambda_function.coordinator.function_name
}

output "model_endpoint_name" {
  description = "Name of the Stable Diffusion SageMaker-style model endpoint."
  value       = aws_sagemaker_endpoint.stable_diffusion.name
}

output "static_web_app_bucket" {
  description = "Name of the S3 bucket holding the static web app assets."
  value       = aws_s3_bucket.static_web_app.bucket
}

output "cloudfront_domain_name" {
  description = "CDN domain name distributing the static web app content."
  value       = aws_cloudfront_distribution.static_web_app.domain_name
}
