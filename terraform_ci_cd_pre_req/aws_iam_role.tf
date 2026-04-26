data "aws_iam_policy_document" "cicd_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subjects
    }
  }
}

resource "aws_iam_role" "terraform_cicd" {
  name                 = local.role_name
  assume_role_policy   = data.aws_iam_policy_document.cicd_trust.json
  max_session_duration = 3600

  tags = {
    Name        = local.role_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.terraform_cicd.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "region_lock" {
  name = "region-lock"
  role = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyOutsideRegion"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringNotEqualsIfExists = {
            "aws:RequestedRegion" = local.aws_region
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "deny_critical" {
  name = "deny-critical-actions"
  role = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyCriticalActions"
        Effect = "Deny"
        Action = [
          "aws-portal:*",
          "account:*",
          "organizations:*",
          "iam:DeleteAccountPasswordPolicy",
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "config:DeleteConfigRule",
          "guardduty:DeleteDetector",
          "ec2:DisableEbsEncryptionByDefault"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "iam_with_boundary" {
  name = "iam-create-with-boundary-only"
  role = aws_iam_role.terraform_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUserRoleManagementWithoutBoundary"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:AttachUserPolicy",
          "iam:CreateAccessKey",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy",
          "iam:DetachUserPolicy",
          "iam:CreateRole",
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "iam:PermissionsBoundary" = aws_iam_policy.terraform_created_users_boundary.arn
          }
        }
      },
      {
        Sid      = "DenyPassRoleToIAM"
        Effect   = "Deny"
        Action   = ["iam:PassRole"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "iam.amazonaws.com"
          }
        }
      }
    ]
  })
}