#!/usr/bin/env bash
#
# bootstrap_github_secrets.sh
#
# Obtains a GitHub PAT via gh CLI, caches it, then sets
# GitHub Actions secrets for the CI/CD pipeline.
#
# Usage: ./bootstrap_github_secrets.sh -o <owner> -r <repo>
#
# Options:
#   -o, --owner <n>     GitHub owner/organization (required)
#   -r, --repo <n>      Repository name (required)
#   -s, --store <path>  Token cache file (default: .github_pat_store)
#   -h, --help          Show help
#
# Requires: gh CLI (run `gh auth login` first), terraform (applied)
#

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { printf "${BLUE} INFO ${NC}    %s\n" "$*"; }
warn()    { printf "${YELLOW} WARNING ${NC} %s\n" "$*" >&2; }
success() { printf "${GREEN} SUCCESS ${NC} %s\n" "$*"; }
error()   { printf "${RED} ERROR ${NC}   %s\n" "$*" >&2; }

OWNER=""
REPO=""
STORE_FILE=".github_pat_store"
FINAL_TOKEN=""
REQUIRED_SCOPES="repo,user"

show_usage() {
  cat <<EOF
Usage: $(basename "$0") -o <owner> -r <repo> [options]

Required:
  -o, --owner <n>     GitHub owner or organization
  -r, --repo <n>      Repository name

Optional:
  -s, --store <path>  Token cache file (default: $STORE_FILE)
  -h, --help          Show this help

Examples:
  $(basename "$0") -o blue-samarth -r my-repo
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--owner)  OWNER="$2"; shift 2 ;;
    -r|--repo)   REPO="$2"; shift 2 ;;
    -s|--store)  STORE_FILE="$2"; shift 2 ;;
    -h|--help)   show_usage ;;
    *) error "Unknown option: $1"; show_usage ;;
  esac
done

if [[ -z "$OWNER" ]] || [[ -z "$REPO" ]]; then
  error "Both --owner and --repo are required"
  exit 1
fi

if ! [[ "$OWNER" =~ ^[A-Za-z0-9._-]+$ ]] || ! [[ "$REPO" =~ ^[A-Za-z0-9._-]+$ ]]; then
  error "Invalid owner or repo name"
  exit 1
fi

# ─── Dependency checks ────────────────────────────────────────────────────────

for cmd in gh curl terraform; do
  if ! command -v "$cmd" &>/dev/null; then
    error "$cmd is required but not installed"
    exit 1
  fi
done

# ─── Repo check ───────────────────────────────────────────────────────────────

verify_repo() {
  info "Verifying ${OWNER}/${REPO}..."
  if ! gh repo view "${OWNER}/${REPO}" &>/dev/null; then
    error "Repository ${OWNER}/${REPO} not found or not accessible"
    exit 1
  fi
  success "Repository ${OWNER}/${REPO} is accessible"
}

# ─── PAT management ───────────────────────────────────────────────────────────

validate_token() {
  local token="$1"

  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: token $token" \
    "https://api.github.com/user")

  if [[ "$http_code" != "200" ]]; then
    warn "Token is no longer valid (HTTP $http_code)"
    return 1
  fi

  local scopes
  scopes=$(curl -s -D - -o /dev/null \
    -H "Authorization: token $token" \
    "https://api.github.com/user" \
    | grep -i "^x-oauth-scopes:" \
    | sed 's/^[^:]*://;s/\r//;s/ //g')

  if echo "$scopes" | grep -q "repo"; then
    return 0
  fi

  warn "Token is missing required scopes (has: $scopes)"
  return 1
}

read_stored_token() {
  [[ ! -f "$STORE_FILE" ]] && return 1

  local perms
  perms=$(stat -c '%a' "$STORE_FILE" 2>/dev/null || stat -f '%Lp' "$STORE_FILE" 2>/dev/null) || {
    error "Cannot determine permissions on $STORE_FILE"
    exit 1
  }

  if [[ "$perms" != "600" ]]; then
    warn "Fixing insecure permissions on $STORE_FILE ($perms → 600)"
    chmod 600 "$STORE_FILE"
  fi

  local stored
  stored=$(cat "$STORE_FILE" 2>/dev/null || true)
  [[ -z "$stored" ]] && return 1

  if validate_token "$stored"; then
    success "Found valid cached token"
    FINAL_TOKEN="$stored"
    return 0
  fi

  rm -f "$STORE_FILE"
  return 1
}

obtain_token() {
  local token
  token=$(gh auth token 2>/dev/null) || true

  if [[ -n "$token" ]] && validate_token "$token"; then
    FINAL_TOKEN="$token"
    success "Token obtained from gh CLI"
    return
  fi

  warn "Current gh token invalid or missing scopes. Re-authenticating..."
  if ! gh auth refresh --scopes "$REQUIRED_SCOPES"; then
    error "gh auth refresh failed"
    exit 1
  fi

  token=$(gh auth token 2>/dev/null) || {
    error "Failed to retrieve token after refresh"
    exit 1
  }

  if [[ -z "$token" ]] || ! validate_token "$token"; then
    error "Freshly obtained token failed validation"
    exit 1
  fi

  FINAL_TOKEN="$token"
  success "Token obtained successfully"
}

persist_token() {
  echo -n "$FINAL_TOKEN" > "$STORE_FILE"
  chmod 600 "$STORE_FILE"
  success "Token cached to $STORE_FILE"
}

# ─── Terraform outputs ────────────────────────────────────────────────────────

get_terraform_outputs() {
  info "Reading Terraform outputs..."

  if ! terraform output cicd_role_arn &>/dev/null; then
    error "Could not read Terraform outputs — has the OIDC module been applied?"
    exit 1
  fi

  ROLE_ARN=$(terraform output -raw cicd_role_arn)
  success "Got cicd_role_arn: $ROLE_ARN"
}

# ─── Set GitHub secrets ───────────────────────────────────────────────────────

set_secret() {
  local name="$1"
  local value="$2"

  if gh secret set "$name" \
    --repo "${OWNER}/${REPO}" \
    --body "$value"; then
    success "Secret set: $name"
  else
    error "Failed to set secret: $name"
    ((FAILED++)) || true
  fi
}

set_variable() {
  local name="$1"
  local value="$2"

  if gh variable set "$name" \
    --repo "${OWNER}/${REPO}" \
    --body "$value"; then
    success "Variable set: $name"
  else
    error "Failed to set variable: $name"
    ((FAILED++)) || true
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

FAILED=0

main() {
  info "=== GitHub Secrets Bootstrap ==="
  info "Target: ${OWNER}/${REPO}"

  verify_repo

  if ! read_stored_token; then
    obtain_token
    persist_token
  fi

  get_terraform_outputs

  info "Setting secrets..."
  set_secret "AWS_ROLE_ARN" "$ROLE_ARN"

  info "Setting variables..."
  set_variable "ENVIRONMENT" "development"
  set_variable "AWS_REGION"  "us-east-1"

  echo
  if [[ $FAILED -gt 0 ]]; then
    error "$FAILED item(s) failed to set"
    exit 1
  fi

  success "=== Done — all secrets and variables set ==="
}

main "$@"