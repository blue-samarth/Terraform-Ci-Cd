output "cicd_role_arn" {
  description = "ARN of the Terraform CI/CD role — add this as a GitHub Actions secret"
  value       = aws_iam_role.terraform_cicd.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = local.oidc_provider_arn
}

output "boundary_policy_arn" {
  description = "ARN of the permission boundary — use this when Terraform creates IAM users"
  value       = aws_iam_policy.terraform_created_users_boundary.arn
}

output "github_subject_claim" {
  description = "The exact subject claim locked to your repo and branch"
  value       = local.github_subjects
}