# ─── S3: static web app bucket (served through the CDN) ─────────────────────

resource "aws_s3_bucket" "static_web_app" {
  bucket = "${local.name_prefix}-${var.static_web_app_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.static_web_app_bucket_name}"
  })
}

resource "aws_s3_bucket_public_access_block" "static_web_app" {
  bucket = aws_s3_bucket.static_web_app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── SageMaker: Stable Diffusion model endpoint (pre-built ML solution) ──────

resource "aws_iam_role" "model_endpoint" {
  name = "${local.name_prefix}-model-endpoint"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "sagemaker.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "model_endpoint_basic" {
  role       = aws_iam_role.model_endpoint.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_model" "stable_diffusion" {
  name               = "${local.name_prefix}-stable-diffusion"
  execution_role_arn = aws_iam_role.model_endpoint.arn

  primary_container {
    image = var.stable_diffusion_image_uri
  }

  tags = local.common_tags
}

resource "aws_sagemaker_endpoint_configuration" "stable_diffusion" {
  name = "${local.name_prefix}-stable-diffusion-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.stable_diffusion.name
    initial_instance_count = 1
    instance_type          = var.sagemaker_instance_type
  }

  tags = local.common_tags
}

resource "aws_sagemaker_endpoint" "stable_diffusion" {
  name                 = "${local.name_prefix}-stable-diffusion-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.stable_diffusion.name

  tags = local.common_tags
}

# ─── Lambda: toxicity_detection — Amazon Comprehend text toxicity check ─────

resource "aws_iam_role" "toxicity_detection_exec" {
  name = "${local.name_prefix}-toxicity-detection"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "toxicity_detection_basic" {
  role       = aws_iam_role.toxicity_detection_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "toxicity_detection_comprehend" {
  name = "${local.name_prefix}-toxicity-detection-comprehend"
  role = aws_iam_role.toxicity_detection_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["comprehend:DetectToxicContent"]
      Resource = "*"
    }]
  })
}

resource "null_resource" "toxicity_detection_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/toxicity_detection/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} toxicity_detection"
  }
}

data "archive_file" "toxicity_detection_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/toxicity_detection/handler.py"
  output_path = "${path.module}/.build/toxicity_detection.zip"

  depends_on = [null_resource.toxicity_detection_package]
}

resource "aws_lambda_function" "toxicity_detection" {
  function_name = "${local.name_prefix}-toxicity-detection"
  role          = aws_iam_role.toxicity_detection_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 15
  memory_size   = 128

  filename         = data.archive_file.toxicity_detection_zip.output_path
  source_code_hash = data.archive_file.toxicity_detection_zip.output_base64sha256

  environment {
    variables = {
      REGION             = var.aws_region
      TOXICITY_THRESHOLD = var.toxicity_threshold
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-toxicity-detection"
  })

  depends_on = [
    aws_iam_role_policy_attachment.toxicity_detection_basic,
    aws_iam_role_policy.toxicity_detection_comprehend,
  ]
}

# ─── Lambda: image_moderation — Amazon Rekognition image moderation check ───

resource "aws_iam_role" "image_moderation_exec" {
  name = "${local.name_prefix}-image-moderation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "image_moderation_basic" {
  role       = aws_iam_role.image_moderation_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "image_moderation_rekognition" {
  name = "${local.name_prefix}-image-moderation-rekognition"
  role = aws_iam_role.image_moderation_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rekognition:DetectModerationLabels"]
      Resource = "*"
    }]
  })
}

resource "null_resource" "image_moderation_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/image_moderation/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} image_moderation"
  }
}

data "archive_file" "image_moderation_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/image_moderation/handler.py"
  output_path = "${path.module}/.build/image_moderation.zip"

  depends_on = [null_resource.image_moderation_package]
}

resource "aws_lambda_function" "image_moderation" {
  function_name = "${local.name_prefix}-image-moderation"
  role          = aws_iam_role.image_moderation_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 15
  memory_size   = 128

  filename         = data.archive_file.image_moderation_zip.output_path
  source_code_hash = data.archive_file.image_moderation_zip.output_base64sha256

  environment {
    variables = {
      REGION                          = var.aws_region
      MODERATION_CONFIDENCE_THRESHOLD = var.moderation_confidence_threshold
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-image-moderation"
  })

  depends_on = [
    aws_iam_role_policy_attachment.image_moderation_basic,
    aws_iam_role_policy.image_moderation_rekognition,
  ]
}

# ─── Lambda: coordinator — coordinates the AWS AI services + model endpoint ─

resource "aws_iam_role" "coordinator_exec" {
  name = "${local.name_prefix}-coordinator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "coordinator_basic" {
  role       = aws_iam_role.coordinator_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "coordinator_invoke_ai_services" {
  name = "${local.name_prefix}-coordinator-invoke-ai-services"
  role = aws_iam_role.coordinator_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        aws_lambda_function.toxicity_detection.arn,
        aws_lambda_function.image_moderation.arn,
      ]
    }]
  })
}

resource "aws_iam_role_policy" "coordinator_invoke_model_endpoint" {
  name = "${local.name_prefix}-coordinator-invoke-model-endpoint"
  role = aws_iam_role.coordinator_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sagemaker:InvokeEndpoint"]
      Resource = aws_sagemaker_endpoint.stable_diffusion.arn
    }]
  })
}

resource "null_resource" "coordinator_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/coordinator/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} coordinator"
  }
}

data "archive_file" "coordinator_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/coordinator/handler.py"
  output_path = "${path.module}/.build/coordinator.zip"

  depends_on = [null_resource.coordinator_package]
}

resource "aws_lambda_function" "coordinator" {
  function_name = "${local.name_prefix}-coordinator"
  role          = aws_iam_role.coordinator_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.coordinator_zip.output_path
  source_code_hash = data.archive_file.coordinator_zip.output_base64sha256

  environment {
    variables = {
      REGION                           = var.aws_region
      TOXICITY_DETECTION_FUNCTION_NAME = aws_lambda_function.toxicity_detection.function_name
      IMAGE_MODERATION_FUNCTION_NAME   = aws_lambda_function.image_moderation.function_name
      MODEL_ENDPOINT_NAME              = aws_sagemaker_endpoint.stable_diffusion.name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-coordinator"
  })

  depends_on = [
    aws_iam_role_policy_attachment.coordinator_basic,
    aws_iam_role_policy.coordinator_invoke_ai_services,
    aws_iam_role_policy.coordinator_invoke_model_endpoint,
  ]
}

# ─── API Gateway: REST API used by the web app ───────────────────────────────

resource "aws_api_gateway_rest_api" "content_moderator" {
  name        = "${local.name_prefix}-api"
  description = "REST API used by the web app to request a moderated, AI-generated image from a text prompt."

  tags = local.common_tags
}

resource "aws_api_gateway_resource" "generate" {
  rest_api_id = aws_api_gateway_rest_api.content_moderator.id
  parent_id   = aws_api_gateway_rest_api.content_moderator.root_resource_id
  path_part   = "generate"
}

resource "aws_api_gateway_method" "post_generate" {
  rest_api_id   = aws_api_gateway_rest_api.content_moderator.id
  resource_id   = aws_api_gateway_resource.generate.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_generate" {
  rest_api_id             = aws_api_gateway_rest_api.content_moderator.id
  resource_id             = aws_api_gateway_resource.generate.id
  http_method             = aws_api_gateway_method.post_generate.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.coordinator.invoke_arn
}

resource "aws_lambda_permission" "apigw_invoke_coordinator" {
  statement_id  = "AllowAPIGatewayInvokeCoordinator"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.coordinator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.content_moderator.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "content_moderator" {
  rest_api_id = aws_api_gateway_rest_api.content_moderator.id

  triggers = {
    redeployment = sha1(jsonencode([aws_api_gateway_integration.post_generate]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.post_generate]
}

resource "aws_api_gateway_stage" "content_moderator" {
  rest_api_id   = aws_api_gateway_rest_api.content_moderator.id
  deployment_id = aws_api_gateway_deployment.content_moderator.id
  stage_name    = var.api_stage_name

  tags = local.common_tags
}

# ─── Web app content: uploaded to S3, distributed through the CDN ───────────

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static_web_app.id
  key          = "index.html"
  content_type = "text/html"

  content = templatefile("${path.module}/web/index.html.tftpl", {
    project_name = var.project_name
    api_endpoint = "${aws_api_gateway_stage.content_moderator.invoke_url}/generate"
  })
}

resource "aws_cloudfront_origin_access_control" "static_web_app" {
  name                              = "${local.name_prefix}-static-web-app-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "static_web_app" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "Distributes the ${var.project_name} static web app content."

  origin {
    domain_name              = aws_s3_bucket.static_web_app.bucket_regional_domain_name
    origin_id                = "static-web-app-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_web_app.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "static-web-app-s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags
}

resource "aws_s3_bucket_policy" "static_web_app_cloudfront" {
  bucket = aws_s3_bucket.static_web_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipalReadOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.static_web_app.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.static_web_app.arn
        }
      }
    }]
  })
}
