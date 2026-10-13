variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "floci-content-moderator"
}

variable "aws_region" {
  description = "AWS region (simulated by floci)."
  type        = string
  default     = "us-east-1"
}

variable "static_web_app_bucket_name" {
  description = "Name of the S3 bucket hosting the static web app assets, served through CloudFront."
  type        = string
  default     = "static-web-app"
}

variable "api_stage_name" {
  description = "API Gateway deployment stage name."
  type        = string
  default     = "prod"
}

variable "stable_diffusion_image_uri" {
  description = "Container image URI for the pre-built Stable Diffusion inference solution (SageMaker JumpStart style)."
  type        = string
  default     = "763104351884.dkr.ecr.us-east-1.amazonaws.com/stabilityai-pytorch-inference:2.0.0-gpu-py310"
}

variable "sagemaker_instance_type" {
  description = "Instance type used by the Stable Diffusion model endpoint."
  type        = string
  default     = "ml.g5.2xlarge"
}

variable "toxicity_threshold" {
  description = "Comprehend toxicity score (0-1) above which a prompt is blocked before image generation."
  type        = number
  default     = 0.5
}

variable "moderation_confidence_threshold" {
  description = "Minimum Rekognition moderation label confidence (0-100) that flags a generated image as unsafe."
  type        = number
  default     = 70
}
