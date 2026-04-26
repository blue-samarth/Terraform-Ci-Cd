data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = data.aws_region.current.id

  name        = coalesce(var.project_name, "Samarths-Project")
  short_name  = coalesce(var.short_name, "samproj")
  environment = coalesce(var.environment, "development")
  name_prefix = "${local.short_name}-${local.environment}"

  github_org    = var.github_org
  github_repo   = var.github_repo
  github_branch = var.github_branch

  github_subject_push = "repo:${local.github_org}/${local.github_repo}:ref:refs/heads/${local.github_branch}"
  github_subject_pr   = "repo:${local.github_org}/${local.github_repo}:pull_request"
  github_subjects     = [local.github_subject_push, local.github_subject_pr]

  role_name     = "${local.name_prefix}-terraform-cicd-role"
  boundary_name = "${local.name_prefix}-terraform-created-users-boundary"
}