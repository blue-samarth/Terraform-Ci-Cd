resource "aws_iam_policy" "terraform_created_users_boundary" {
  name        = local.boundary_name
  description = "Permission boundary for all IAM users and roles created by Terraform CI/CD"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowScopedRegionalAccess"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "aws:RequestedRegion" = local.aws_region
          }
        }
      },
      {
        Sid    = "DenyPrivilegeEscalation"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateAccessKey",
          "iam:AttachUserPolicy",
          "iam:PutUserPolicy",
          "iam:CreateRole",
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy",
          "iam:PassRole",
          "sts:AssumeRole",
          "organizations:*",
          "account:*",
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "guardduty:DeleteDetector",
          "config:DeleteConfigRule"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = local.boundary_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}