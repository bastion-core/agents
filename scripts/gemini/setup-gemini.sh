#!/usr/bin/env bash
# =============================================================================
# Gemini CLI Setup Script — Service Account Impersonation
# =============================================================================
# Automates the configuration of GCP Service Account Impersonation so that
# developers can use Gemini CLI with Vertex AI without re-authenticating daily.
#
# Usage:
#   ./scripts/gemini/setup-gemini.sh [FLAGS]
#
# Examples:
#   ./scripts/gemini/setup-gemini.sh --project my-project --email juan@empresa.com --dev-name juan
#   ./scripts/gemini/setup-gemini.sh --dry-run
#   ./scripts/gemini/setup-gemini.sh --cleanup --dev-name juan
#
# Flags:
#   --project, -p   GCP project ID (default: still-smithy-407213)
#   --email, -e     Developer email (default: active gcloud account)
#   --dev-name, -n  Developer identifier for SA naming (default: email username)
#   --region, -r    Vertex AI region (default: global)
#   --dry-run, -d   Show commands without executing
#   --cleanup, -c   Revert all configuration
#   --help, -h      Show this help
# =============================================================================

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="setup-gemini.sh"
readonly SA_PREFIX="gemini"
readonly TOTAL_STEPS=7

# =============================================================================
# ANSI Colors
# =============================================================================
if [[ -z "${NO_COLOR:-}" ]]; then
  readonly COLOR_INFO='\033[0;34m'     # Blue
  readonly COLOR_SUCCESS='\033[0;32m'  # Green
  readonly COLOR_WARNING='\033[0;33m'  # Yellow
  readonly COLOR_ERROR='\033[0;31m'    # Red
  readonly COLOR_DRY='\033[0;36m'      # Cyan
  readonly COLOR_BOLD='\033[1m'        # Bold
  readonly COLOR_RESET='\033[0m'       # Reset
else
  readonly COLOR_INFO=''
  readonly COLOR_SUCCESS=''
  readonly COLOR_WARNING=''
  readonly COLOR_ERROR=''
  readonly COLOR_DRY=''
  readonly COLOR_BOLD=''
  readonly COLOR_RESET=''
fi

# =============================================================================
# Logging functions
# =============================================================================
log_info()    { echo -e "${COLOR_INFO}[INFO]${COLOR_RESET} $*"; }
log_success() { echo -e "${COLOR_SUCCESS}[OK]${COLOR_RESET} $*"; }
log_warning() { echo -e "${COLOR_WARNING}[WARN]${COLOR_RESET} $*"; }
log_error()   { echo -e "${COLOR_ERROR}[ERROR]${COLOR_RESET} $*" >&2; }
log_dry_run() { echo -e "${COLOR_DRY}[DRY RUN]${COLOR_RESET} $*"; }
log_step()    { echo -e "\n${COLOR_BOLD}[Step $1/${TOTAL_STEPS}]${COLOR_RESET} $2"; }

# =============================================================================
# Default configuration
# =============================================================================
PROJECT_ID="still-smithy-407213"
USER_EMAIL=""
DEV_NAME=""
REGION="global"
DRY_RUN=false
CLEANUP=false
SA_EMAIL=""

# =============================================================================
# Error trap handler
# =============================================================================
error_handler() {
  local line="$1"
  local code="$2"
  log_error "Failed at line ${line} (exit code ${code})"

  case "${code}" in
    2) log_error "Prerequisite not met. Verify gcloud is installed and you are authenticated." ;;
    3) log_error "Insufficient GCP permissions. You need roles/iam.admin or roles/owner on the project." ;;
    4) log_error "Network error. Verify your internet connection." ;;
    5) log_error "Vertex AI access verification failed. Check that the API is enabled and permissions have propagated." ;;
  esac

  if [[ "${CLEANUP}" == false ]]; then
    log_info "To revert partial changes run: ./${SCRIPT_NAME} --cleanup --project ${PROJECT_ID} --dev-name ${DEV_NAME}"
  fi
  exit "${code}"
}

trap 'error_handler ${LINENO} $?' ERR

# =============================================================================
# Helper: execute or dry-run
# =============================================================================
execute_or_dry_run() {
  if [[ "${DRY_RUN}" == true ]]; then
    log_dry_run "$*"
    return 0
  fi
  "$@"
}

# =============================================================================
# show_help
# =============================================================================
show_help() {
  cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}
Automates GCP Service Account Impersonation setup for Gemini CLI + Vertex AI.

USAGE
  ./${SCRIPT_NAME} [FLAGS]

FLAGS
  --project, -p <id>     GCP project ID (default: still-smithy-407213)
  --email,   -e <email>  Developer GCP email (default: active gcloud account)
  --dev-name,-n <name>   Identifier for the Service Account (default: email username)
  --region,  -r <region> Vertex AI region (default: global)
  --dry-run, -d          Preview commands without executing
  --cleanup, -c          Revert all configuration created by this script
  --help,    -h          Show this help

EXAMPLES
  # Full setup
  ./${SCRIPT_NAME} --project my-project --email dev@company.com --dev-name juan

  # Preview what would happen
  ./${SCRIPT_NAME} --dry-run

  # Revert everything
  ./${SCRIPT_NAME} --cleanup --dev-name juan
EOF
  exit 0
}

# =============================================================================
# Parse flags
# =============================================================================
parse_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project|-p)  PROJECT_ID="$2";  shift 2 ;;
      --email|-e)    USER_EMAIL="$2";  shift 2 ;;
      --dev-name|-n) DEV_NAME="$2";    shift 2 ;;
      --region|-r)   REGION="$2";      shift 2 ;;
      --dry-run|-d)  DRY_RUN=true;     shift ;;
      --cleanup|-c)  CLEANUP=true;     shift ;;
      --help|-h)     show_help ;;
      *)
        log_error "Unknown flag: $1"
        log_info "Run ./${SCRIPT_NAME} --help for usage."
        exit 1
        ;;
    esac
  done

  if [[ "${DRY_RUN}" == true && "${CLEANUP}" == true ]]; then
    # Allow combining --dry-run with --cleanup to preview cleanup
    true
  fi
}

# =============================================================================
# Validate prerequisites
# =============================================================================
validate_prerequisites() {
  log_info "Validating prerequisites..."

  # 0. Clear any active impersonation so IAM steps run with user credentials
  local current_impersonation
  current_impersonation=$(gcloud config get auth/impersonate_service_account 2>/dev/null || true)
  if [[ -n "${current_impersonation}" && "${current_impersonation}" != "(unset)" ]]; then
    log_warning "Active impersonation detected (${current_impersonation}). Clearing for setup."
    gcloud config unset auth/impersonate_service_account 2>/dev/null || true
  fi

  # 1. gcloud installed
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI is not installed. Install it from https://cloud.google.com/sdk/docs/install"
    exit 2
  fi
  log_success "gcloud CLI found"

  # 2. User authenticated
  local active_account
  active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
  if [[ -z "${active_account}" ]]; then
    log_error "No active gcloud session. Run: gcloud auth login"
    exit 2
  fi
  log_success "Authenticated as ${active_account}"

  # Default email from active account
  if [[ -z "${USER_EMAIL}" ]]; then
    USER_EMAIL="${active_account}"
    log_info "Using email from active session: ${USER_EMAIL}"
  fi

  # 3. Project configured and accessible
  if [[ -z "${PROJECT_ID}" ]]; then
    log_error "No GCP project configured. Pass --project <id> or run: gcloud config set project <id>"
    exit 2
  fi
  log_info "Using project: ${PROJECT_ID}"

  if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
    log_error "Project '${PROJECT_ID}' not found or not accessible."
    exit 2
  fi
  log_success "Project '${PROJECT_ID}' is accessible"

  # 4. Vertex AI API enabled
  local api_enabled
  api_enabled=$(gcloud services list --enabled --filter="name:aiplatform.googleapis.com" --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null)
  if [[ -z "${api_enabled}" ]]; then
    log_error "Vertex AI API is not enabled. Run:"
    log_error "  gcloud services enable aiplatform.googleapis.com --project=${PROJECT_ID}"
    exit 2
  fi
  log_success "Vertex AI API is enabled"

  # 5. Validate dev-name
  if [[ -z "${DEV_NAME}" ]]; then
    DEV_NAME="${USER_EMAIL%%@*}"
    log_info "Using dev-name from email: ${DEV_NAME}"
  fi

  # Sanitize: lowercase, replace dots/underscores with hyphens
  DEV_NAME=$(echo "${DEV_NAME}" | tr '[:upper:]' '[:lower:]' | tr '._' '-')

  if ! [[ "${DEV_NAME}" =~ ^[a-z][a-z0-9-]{0,23}$ ]]; then
    log_error "Invalid dev-name '${DEV_NAME}'. Must be 1-24 lowercase chars, numbers, hyphens. Must start with a letter."
    exit 1
  fi

  # Build SA email
  SA_EMAIL="${SA_PREFIX}-${DEV_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

  # 6. Check IAM permissions (only for setup, not cleanup)
  if [[ "${CLEANUP}" == false ]]; then
    # Skip IAM check if SA already exists with all bindings (admin already ran the commands)
    local sa_exists=false
    local role_exists=false
    local imp_exists=false

    if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
      sa_exists=true
    fi

    local role_check
    role_check=$(gcloud projects get-iam-policy "${PROJECT_ID}" \
      --flatten="bindings[].members" \
      --filter="bindings.role:roles/aiplatform.user AND bindings.members:serviceAccount:${SA_EMAIL}" \
      --format="value(bindings.role)" 2>/dev/null || true)
    if [[ -n "${role_check}" ]]; then
      role_exists=true
    fi

    local imp_check
    imp_check=$(gcloud iam service-accounts get-iam-policy "${SA_EMAIL}" \
      --flatten="bindings[].members" \
      --filter="bindings.role:roles/iam.serviceAccountTokenCreator AND bindings.members:user:${USER_EMAIL}" \
      --format="value(bindings.role)" 2>/dev/null || true)
    if [[ -n "${imp_check}" ]]; then
      imp_exists=true
    fi

    if [[ "${sa_exists}" == true && "${role_exists}" == true && "${imp_exists}" == true ]]; then
      log_success "IAM resources already configured (SA + roles + impersonation). Skipping permissions check."
    else
      local has_iam_perms
      has_iam_perms=$(gcloud projects test-iam-permissions "${PROJECT_ID}" \
        --permissions="iam.serviceAccounts.create,resourcemanager.projects.setIamPolicy" \
        --format="value(permissions)" 2>/dev/null || true)

      if [[ "${has_iam_perms}" != *"resourcemanager.projects.setIamPolicy"* ]]; then
        log_error "Your account does not have permission to assign IAM roles on this project."
        log_error ""
        log_error "Share the following commands with your GCP admin:"
        echo ""
        echo "# ============================================================"
        echo "# Commands for GCP Admin — Gemini CLI setup for ${DEV_NAME}"
        echo "# Project: ${PROJECT_ID}"
        echo "# Developer: ${USER_EMAIL}"
        echo "# ============================================================"
        echo ""
        echo "# 1. Create Service Account (skip if already exists)"
        echo "gcloud iam service-accounts create ${SA_PREFIX}-${DEV_NAME} \\"
        echo "  --project=${PROJECT_ID} \\"
        echo "  --display-name=\"Gemini Dev - ${DEV_NAME}\""
        echo ""
        echo "# 2. Assign Vertex AI role to the Service Account"
        echo "gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
        echo "  --member=\"serviceAccount:${SA_EMAIL}\" \\"
        echo "  --role=\"roles/aiplatform.user\" \\"
        echo "  --condition=None --quiet"
        echo ""
        echo "# 3. Grant impersonation permission to the developer"
        echo "gcloud iam service-accounts add-iam-policy-binding ${SA_EMAIL} \\"
        echo "  --member=\"user:${USER_EMAIL}\" \\"
        echo "  --role=\"roles/iam.serviceAccountTokenCreator\" \\"
        echo "  --quiet"
        echo ""
        echo "# ============================================================"
        echo "# After the admin runs these commands, the developer runs:"
        echo "#   ./scripts/gemini/setup-gemini.sh --dev-name ${DEV_NAME}"
        echo "# (Steps 1-3 will be skipped, only Steps 4-7 will execute)"
        echo "# ============================================================"
        echo ""
        exit 3
      fi
      log_success "IAM permissions verified"
    fi
  fi

  # Show config summary
  echo ""
  log_info "Configuration summary:"
  log_info "  Project:         ${PROJECT_ID}"
  log_info "  User email:      ${USER_EMAIL}"
  log_info "  Dev name:        ${DEV_NAME}"
  log_info "  Service Account: ${SA_EMAIL}"
  log_info "  Region:          ${REGION}"
  log_info "  Mode:            $(if [[ "${CLEANUP}" == true ]]; then echo 'CLEANUP'; elif [[ "${DRY_RUN}" == true ]]; then echo 'DRY RUN'; else echo 'SETUP'; fi)"
  echo ""
}

# =============================================================================
# Pipeline Step 1: Create Service Account
# =============================================================================
step_create_service_account() {
  log_step 1 "Creating Service Account..."

  # Check if SA already exists
  if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
    log_warning "Service Account ${SA_EMAIL} already exists. Skipping creation."
    return 0
  fi

  execute_or_dry_run gcloud iam service-accounts create "${SA_PREFIX}-${DEV_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Gemini Dev - ${DEV_NAME}"

  log_success "Service Account created: ${SA_EMAIL}"
}

# =============================================================================
# Pipeline Step 2: Assign Vertex AI role
# =============================================================================
step_assign_vertex_role() {
  log_step 2 "Assigning Vertex AI role..."

  local existing
  existing=$(gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/aiplatform.user AND bindings.members:serviceAccount:${SA_EMAIL}" \
    --format="value(bindings.role)" 2>/dev/null || true)

  if [[ -n "${existing}" ]]; then
    log_warning "Role roles/aiplatform.user already assigned to ${SA_EMAIL}. Skipping."
    return 0
  fi

  execute_or_dry_run gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/aiplatform.user" \
    --condition=None \
    --quiet

  log_success "Role roles/aiplatform.user assigned to ${SA_EMAIL}"
}

# =============================================================================
# Pipeline Step 3: Grant impersonation permission
# =============================================================================
step_grant_impersonation() {
  log_step 3 "Granting impersonation permission..."

  local existing
  existing=$(gcloud iam service-accounts get-iam-policy "${SA_EMAIL}" \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/iam.serviceAccountTokenCreator AND bindings.members:user:${USER_EMAIL}" \
    --format="value(bindings.role)" 2>/dev/null || true)

  if [[ -n "${existing}" ]]; then
    log_warning "Impersonation already granted to ${USER_EMAIL}. Skipping."
    return 0
  fi

  execute_or_dry_run gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
    --member="user:${USER_EMAIL}" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --quiet

  log_success "Impersonation granted: ${USER_EMAIL} -> ${SA_EMAIL}"
}

# =============================================================================
# Pipeline Step 4: Configure gcloud impersonation default
# =============================================================================
step_configure_gcloud() {
  log_step 4 "Configuring gcloud impersonation default..."

  execute_or_dry_run gcloud config set auth/impersonate_service_account "${SA_EMAIL}"

  log_success "gcloud configured to impersonate ${SA_EMAIL}"
}

# =============================================================================
# Pipeline Step 5: Generate Application Default Credentials
# =============================================================================
step_generate_adc() {
  log_step 5 "Generating Application Default Credentials..."

  log_info "This step will open your browser for OAuth authorization."

  execute_or_dry_run gcloud auth application-default login \
    --impersonate-service-account="${SA_EMAIL}"

  log_success "ADC generated with impersonation"
}

# =============================================================================
# Pipeline Step 6: Verify access
# =============================================================================
step_verify_access() {
  log_step 6 "Verifying Vertex AI access..."

  # Vertex AI models list requires a specific region, not 'global'
  local verify_region="${REGION}"
  if [[ "${verify_region}" == "global" ]]; then
    verify_region="us-central1"
    log_info "Using us-central1 for verification (Vertex AI does not support 'global' for model listing)"
  fi

  if ! execute_or_dry_run gcloud ai models list --region="${verify_region}" --limit=1; then
    log_error "Vertex AI access verification failed."
    log_error "Possible causes:"
    log_error "  - IAM permissions may take a few minutes to propagate"
    log_error "  - Vertex AI API may not be enabled in region ${verify_region}"
    log_error "  - Service Account may not have sufficient permissions"
    exit 5
  fi

  log_success "Vertex AI access verified in region ${verify_region}"
}

# =============================================================================
# Pipeline Step 7: Show summary
# =============================================================================
step_show_summary() {
  log_step 7 "Setup complete"

  echo ""
  echo -e "${COLOR_SUCCESS}╔══════════════════════════════════════════════════════════════╗${COLOR_RESET}"
  echo -e "${COLOR_SUCCESS}║              Gemini CLI — Configuration Complete            ║${COLOR_RESET}"
  echo -e "${COLOR_SUCCESS}╠══════════════════════════════════════════════════════════════╣${COLOR_RESET}"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET} Service Account: ${COLOR_BOLD}${SA_EMAIL}${COLOR_RESET}"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET} Roles:           roles/aiplatform.user"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET} Impersonation:   ${USER_EMAIL} -> SA"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET} Region:          ${REGION}"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET} Project:         ${PROJECT_ID}"
  echo -e "${COLOR_SUCCESS}╠══════════════════════════════════════════════════════════════╣${COLOR_RESET}"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET} ${COLOR_BOLD}Next steps:${COLOR_RESET}"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET}   1. cd gemini/spec-generator/"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET}   2. gemini"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET}   3. Select \"Vertex AI\" when prompted"
  echo -e "${COLOR_SUCCESS}╠══════════════════════════════════════════════════════════════╣${COLOR_RESET}"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET} To revert: ./scripts/gemini/${SCRIPT_NAME} --cleanup --dev-name ${DEV_NAME}"
  echo -e "${COLOR_SUCCESS}║${COLOR_RESET} Billing:   GCP Console > Billing > filter by SA"
  echo -e "${COLOR_SUCCESS}╚══════════════════════════════════════════════════════════════╝${COLOR_RESET}"
  echo ""
}

# =============================================================================
# Cleanup pipeline (reverse order)
# =============================================================================
run_cleanup() {
  log_info "Starting cleanup..."
  echo ""

  # 1. Unset gcloud impersonation config
  log_step 1 "Unsetting gcloud impersonation config..."
  execute_or_dry_run gcloud config unset auth/impersonate_service_account 2>/dev/null || true
  log_success "gcloud impersonation config cleared"

  # 2. Revoke impersonation permission
  log_step 2 "Revoking impersonation permission..."
  local imp_exists
  imp_exists=$(gcloud iam service-accounts get-iam-policy "${SA_EMAIL}" \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/iam.serviceAccountTokenCreator AND bindings.members:user:${USER_EMAIL}" \
    --format="value(bindings.role)" 2>/dev/null || true)

  if [[ -n "${imp_exists}" ]]; then
    execute_or_dry_run gcloud iam service-accounts remove-iam-policy-binding "${SA_EMAIL}" \
      --member="user:${USER_EMAIL}" \
      --role="roles/iam.serviceAccountTokenCreator" \
      --quiet
    log_success "Impersonation revoked"
  else
    log_warning "Impersonation binding not found. Skipping."
  fi

  # 3. Revoke Vertex AI role
  log_step 3 "Revoking Vertex AI role..."
  local role_exists
  role_exists=$(gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/aiplatform.user AND bindings.members:serviceAccount:${SA_EMAIL}" \
    --format="value(bindings.role)" 2>/dev/null || true)

  if [[ -n "${role_exists}" ]]; then
    execute_or_dry_run gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="roles/aiplatform.user" \
      --quiet
    log_success "Vertex AI role revoked"
  else
    log_warning "Vertex AI role binding not found. Skipping."
  fi

  # 4. Delete Service Account
  log_step 4 "Deleting Service Account..."
  if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
    execute_or_dry_run gcloud iam service-accounts delete "${SA_EMAIL}" --quiet
    log_success "Service Account deleted: ${SA_EMAIL}"
  else
    log_warning "Service Account ${SA_EMAIL} not found. Skipping."
  fi

  echo ""
  log_success "Cleanup complete. All resources have been removed."
  echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
  echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
  echo ""

  parse_flags "$@"
  validate_prerequisites

  if [[ "${CLEANUP}" == true ]]; then
    run_cleanup
  else
    step_create_service_account
    step_assign_vertex_role
    step_grant_impersonation
    step_configure_gcloud
    step_generate_adc
    step_verify_access
    step_show_summary
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    echo ""
    log_dry_run "No operations were executed."
  fi
}

main "$@"
