#!/usr/bin/env bash
# validate_oidc_setup.sh
# Validates the Terraform CI/CD OIDC setup against AWS
# Usage: ./validate_oidc_setup.sh
# Reads values from terraform output automatically

set -euo pipefail

# ─── Read from Terraform Outputs ──────────────────────────────────────────────

echo "Reading Terraform outputs..."

ROLE_ARN=$(terraform output -raw cicd_role_arn)
BOUNDARY_ARN=$(terraform output -raw boundary_policy_arn)
OIDC_ARN=$(terraform output -raw oidc_provider_arn)

EXPECTED_REGION=$(aws configure get region)
ACCOUNT_ID=$(echo "$ROLE_ARN" | cut -d':' -f5)
ROLE_NAME=$(echo "$ROLE_ARN" | cut -d'/' -f2)
BOUNDARY_NAME=$(echo "$BOUNDARY_ARN" | cut -d'/' -f2)

# ─── Helpers ──────────────────────────────────────────────────────────────────

PASS=0
FAIL=0
WARN=0

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1"; ((FAIL++)) || true; }
warn() { echo "  WARN: $1"; ((WARN++)) || true; }
info() { echo "  INFO: $1"; }
header() {
  echo
  echo "────────────────────────────────────────────────────"
  echo "  $1"
  echo "────────────────────────────────────────────────────"
}

# ─── 1. OIDC Provider ─────────────────────────────────────────────────────────

header "1. OIDC Provider"

OIDC_JSON=$(aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$OIDC_ARN" 2>/dev/null || echo "")

if [[ -n "$OIDC_JSON" ]]; then
  pass "OIDC provider exists: $OIDC_ARN"

  CLIENT_IDS=$(echo "$OIDC_JSON" | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['ClientIDList'])")

  if echo "$CLIENT_IDS" | grep -q "sts.amazonaws.com"; then
    pass "Audience is sts.amazonaws.com"
  else
    fail "Audience is not sts.amazonaws.com — got: $CLIENT_IDS"
  fi

  THUMBPRINT=$(echo "$OIDC_JSON" | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['ThumbprintList'][0])")
  info "Thumbprint in use: $THUMBPRINT"
else
  fail "OIDC provider not found at $OIDC_ARN"
fi

# ─── 2. CI/CD Role ────────────────────────────────────────────────────────────

header "2. CI/CD Role"

ROLE_JSON=$(aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null || echo "")

if [[ -n "$ROLE_JSON" ]]; then
  pass "Role exists: $ROLE_NAME"

  MAX_SESSION=$(echo "$ROLE_JSON" | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['Role']['MaxSessionDuration'])")
  if [[ "$MAX_SESSION" == "3600" ]]; then
    pass "Max session duration is 3600s"
  else
    fail "Max session duration is $MAX_SESSION, expected 3600"
  fi

  TRUST=$(echo "$ROLE_JSON" | python3 -c \
    "import sys,json,urllib.parse; \
    doc=json.load(sys.stdin)['Role']['AssumeRolePolicyDocument']; \
    print(json.dumps(doc) if isinstance(doc,dict) else urllib.parse.unquote(doc))")

  if echo "$TRUST" | grep -q "token.actions.githubusercontent.com"; then
    pass "Trust policy references GitHub OIDC"
  else
    fail "Trust policy does not reference GitHub OIDC"
  fi

  if echo "$TRUST" | grep -q "sts:AssumeRoleWithWebIdentity"; then
    pass "Trust policy allows AssumeRoleWithWebIdentity"
  else
    fail "Trust policy does not allow AssumeRoleWithWebIdentity"
  fi

  if echo "$TRUST" | grep -q "sts.amazonaws.com"; then
    pass "Trust policy aud condition is sts.amazonaws.com"
  else
    fail "Trust policy aud condition missing sts.amazonaws.com"
  fi
else
  fail "Role not found: $ROLE_NAME"
fi

# ─── 3. Admin Policy Attachment ───────────────────────────────────────────────

header "3. Admin Policy Attachment"

ATTACHED=$(aws iam list-attached-role-policies \
  --role-name "$ROLE_NAME" \
  --query 'AttachedPolicies[].PolicyArn' --output json 2>/dev/null || echo "[]")

if echo "$ATTACHED" | grep -q "arn:aws:iam::aws:policy/AdministratorAccess"; then
  pass "AdministratorAccess is attached"
else
  fail "AdministratorAccess is NOT attached"
fi

# ─── 4. Inline Policies ───────────────────────────────────────────────────────

header "4. Inline Policies"

INLINE_POLICIES=$(aws iam list-role-policies \
  --role-name "$ROLE_NAME" \
  --query 'PolicyNames' --output json 2>/dev/null || echo "[]")

info "Inline policies found: $INLINE_POLICIES"

for EXPECTED in "region-lock" "deny-critical-actions" "iam-create-with-boundary-only"; do
  if echo "$INLINE_POLICIES" | grep -q "$EXPECTED"; then
    pass "Inline policy exists: $EXPECTED"
  else
    fail "Inline policy missing: $EXPECTED"
  fi
done

# ─── 5. Region Lock Validation ────────────────────────────────────────────────

header "5. Region Lock Policy"

REGION_LOCK=$(aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "region-lock" \
  --query 'PolicyDocument' --output json 2>/dev/null \
  | python3 -c "import sys,json,urllib.parse; \
    raw=sys.stdin.read().strip(); \
    print(urllib.parse.unquote(raw))" || echo "")

if echo "$REGION_LOCK" | grep -q "StringNotEqualsIfExists"; then
  pass "Region lock uses StringNotEqualsIfExists"
else
  fail "Region lock does not use StringNotEqualsIfExists"
fi

if echo "$REGION_LOCK" | grep -q "$EXPECTED_REGION"; then
  pass "Region lock targets $EXPECTED_REGION"
else
  fail "Region lock does not target $EXPECTED_REGION"
fi

if echo "$REGION_LOCK" | grep -q '"Effect": "Deny"'; then
  pass "Region lock effect is Deny"
else
  fail "Region lock effect is not Deny"
fi

# ─── 6. Critical Deny Policy ──────────────────────────────────────────────────

header "6. Critical Deny Policy"

CRITICAL=$(aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "deny-critical-actions" \
  --query 'PolicyDocument' --output json 2>/dev/null \
  | python3 -c "import sys,json,urllib.parse; \
    raw=sys.stdin.read().strip(); \
    print(urllib.parse.unquote(raw))" || echo "")

for ACTION in "cloudtrail:DeleteTrail" "cloudtrail:StopLogging" \
              "guardduty:DeleteDetector" "organizations:*" \
              "account:*" "ec2:DisableEbsEncryptionByDefault"; do
  if echo "$CRITICAL" | grep -q "$ACTION"; then
    pass "Critical deny includes: $ACTION"
  else
    fail "Critical deny missing: $ACTION"
  fi
done

# ─── 7. Boundary Enforcement Policy ──────────────────────────────────────────

header "7. Boundary Enforcement Policy"

BOUNDARY_POLICY=$(aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "iam-create-with-boundary-only" \
  --query 'PolicyDocument' --output json 2>/dev/null \
  | python3 -c "import sys,json,urllib.parse; \
    raw=sys.stdin.read().strip(); \
    print(urllib.parse.unquote(raw))" || echo "")

if echo "$BOUNDARY_POLICY" | grep -q "StringNotEquals"; then
  pass "Boundary enforcement uses StringNotEquals"
else
  fail "Boundary enforcement does not use StringNotEquals"
fi

if echo "$BOUNDARY_POLICY" | grep -q "$BOUNDARY_ARN"; then
  pass "Boundary enforcement references correct boundary ARN"
else
  fail "Boundary enforcement does not reference correct boundary ARN"
fi

if echo "$BOUNDARY_POLICY" | grep -q "iam:CreateAccessKey"; then
  pass "CreateAccessKey is covered by boundary enforcement"
else
  fail "CreateAccessKey is not covered by boundary enforcement"
fi

if echo "$BOUNDARY_POLICY" | grep -q "iam:PassedToService"; then
  pass "PassRole is scoped to iam:PassedToService condition"
else
  fail "PassRole is not scoped — unconditional deny"
fi

# ─── 8. Boundary Policy Itself ────────────────────────────────────────────────

header "8. Boundary Policy Content"

BOUNDARY_DOC=$(aws iam get-policy-version \
  --policy-arn "$BOUNDARY_ARN" \
  --version-id "$(aws iam get-policy \
    --policy-arn "$BOUNDARY_ARN" \
    --query 'Policy.DefaultVersionId' --output text)" \
  --query 'PolicyVersion.Document' --output json 2>/dev/null \
  | python3 -c "import sys,urllib.parse; \
    print(urllib.parse.unquote(sys.stdin.read().strip()))" || echo "")

if echo "$BOUNDARY_DOC" | grep -q "StringEqualsIfExists"; then
  pass "Boundary regional scope uses StringEqualsIfExists"
else
  fail "Boundary regional scope does not use StringEqualsIfExists — global services will break"
fi

if echo "$BOUNDARY_DOC" | grep -q "sts:AssumeRole"; then
  pass "Boundary denies sts:AssumeRole"
else
  fail "Boundary does not deny sts:AssumeRole"
fi

if echo "$BOUNDARY_DOC" | grep -q "organizations:\*"; then
  pass "Boundary denies organizations:*"
else
  fail "Boundary does not deny organizations:*"
fi

# ─── 9. Simulate Key Denials ──────────────────────────────────────────────────

header "9. Policy Simulation — Deny Checks"

info "Simulating actions against role — this uses iam:SimulatePrincipalPolicy"

simulate() {
  local ACTION="$1"
  local EXPECTED="$2"
  local CONTEXT_KEY="${3:-}"
  local CONTEXT_VAL="${4:-}"

  local ARGS=(
    --policy-source-arn "$ROLE_ARN"
    --action-names "$ACTION"
    --resource-arns "*"
  )

  if [[ -n "$CONTEXT_KEY" ]]; then
    ARGS+=(--context-entries "ContextKeyName=${CONTEXT_KEY},ContextKeyValues=${CONTEXT_VAL},ContextKeyType=string")
  fi

  RESULT=$(aws iam simulate-principal-policy "${ARGS[@]}" \
    --query 'EvaluationResults[0].EvalDecision' --output text 2>/dev/null || echo "error")

  if [[ "$RESULT" == "$EXPECTED" ]]; then
    pass "[$ACTION] -> $RESULT (expected $EXPECTED)"
  else
    fail "[$ACTION] -> $RESULT (expected $EXPECTED)"
  fi
}

# Should be denied — outside region
simulate "ec2:DescribeInstances" "implicitDeny" \
  "aws:RequestedRegion" "eu-west-1"

# Should be denied — critical action
simulate "cloudtrail:DeleteTrail" "explicitDeny"

# Should be denied — org action
simulate "organizations:ListAccounts" "explicitDeny"

# Should be denied — PassRole to IAM
simulate "iam:PassRole" "explicitDeny" \
  "iam:PassedToService" "iam.amazonaws.com"

# Should be allowed — PassRole to Lambda
simulate "iam:PassRole" "allowed" \
  "iam:PassedToService" "lambda.amazonaws.com"

# Should be denied — creating user without boundary
simulate "iam:CreateUser" "explicitDeny" \
  "iam:PermissionsBoundary" "arn:aws:iam::${ACCOUNT_ID}:policy/some-other-policy"

# Should be allowed — ec2 in correct region
simulate "ec2:DescribeInstances" "allowed" \
  "aws:RequestedRegion" "$EXPECTED_REGION"

# ─── Summary ──────────────────────────────────────────────────────────────────

header "Summary"

echo "  Total checks : $((PASS + FAIL + WARN))"
echo "  Passed       : $PASS"
echo "  Failed       : $FAIL"
echo "  Warnings     : $WARN"
echo

if [[ $FAIL -gt 0 ]]; then
  echo "  VALIDATION FAILED — $FAIL check(s) did not pass"
  exit 1
else
  echo "  ALL CHECKS PASSED — setup is valid"
  exit 0
fi