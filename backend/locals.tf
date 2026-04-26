data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = data.aws_region.current.id

  name        = coalesce(var.project_name, "Samarths-Project")
  short_name  = coalesce(var.short_name, "samproj")
  environment = coalesce(var.environment, "development")
  namespace   = coalesce(var.namespace, "terraform")
  name_prefix = "${local.short_name}-${local.environment}"

  bucket_name               = coalesce(var.s3_bucket_name, "${local.name_prefix}-tfstate-bucket-${local.aws_account_id}")
  s3_expiration_days        = coalesce(var.s3_expiration_days, 90)
  block_public_access       = coalesce(var.block_public_access, true)
  versioning_enabled        = coalesce(var.versioning_enabled, true)
  server_side_encryption    = coalesce(var.server_side_encryption, true)
  prevent_s3_bucket_destroy = coalesce(var.prevent_s3_bucket_destroy, false)
  s3_force_destroy          = coalesce(var.s3_force_destroy, false)
  use_lockfile              = coalesce(var.use_lockfile, true)
}