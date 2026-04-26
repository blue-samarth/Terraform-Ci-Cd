output "s3_bucket_id" {
  description = "The ID (name) of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.id
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "s3_bucket_region" {
  description = "The region where the S3 bucket is located"
  value       = aws_s3_bucket.terraform_state.region
}

output "s3_bucket_domain_name" {
  description = "The domain name of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.bucket_domain_name
}

output "s3_bucket_versioning_enabled" {
  description = "Whether versioning is enabled on the S3 bucket"
  value       = local.versioning_enabled
}

# Backend Configuration Output
# Paste this into your other Terraform projects' backend.tf
output "terraform_backend_config" {
  description = "Backend configuration to use this state storage"
  value = {
    bucket       = aws_s3_bucket.terraform_state.id
    key          = "terraform.tfstate"
    region       = local.aws_region
    encrypt      = local.server_side_encryption
    use_lockfile = local.use_lockfile # no dynamodb_table needed!
  }
}

output "project_name" {
  description = "The name of the project"
  value       = local.name
}

output "environment" {
  description = "The environment name"
  value       = local.environment
}

output "aws_account_id" {
  description = "The AWS account ID where resources are created"
  value       = local.aws_account_id
}

output "aws_region" {
  description = "The AWS region where resources are created"
  value       = local.aws_region
}