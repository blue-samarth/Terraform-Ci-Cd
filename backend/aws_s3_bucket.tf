resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.bucket_name
  force_destroy = true

  lifecycle { prevent_destroy = false }

  tags = {
    Name        = "Terraform State Bucket"
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration { status = local.versioning_enabled ? "Enabled" : "Suspended" }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = local.block_public_access
  block_public_policy     = local.block_public_access
  ignore_public_acls      = local.block_public_access
  restrict_public_buckets = local.block_public_access
}


resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "ExpireObjects"
    status = "Enabled"
    expiration { days = local.s3_expiration_days }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  count  = local.server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}


resource "aws_s3_bucket_policy" "terraform_state_ssl" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.terraform_state]
}
