#!/usr/bin/env bash
# =============================================================================
# Claude Code Setup Script — Vertex AI Authentication
# =============================================================================
# Configures Claude Code CLI to consume Anthropic models through Google Vertex
# AI, using GCP credits instead of a Claude.ai subscription.
#
# Usage:
#   ./scripts/claude/setup-claude-vertex.sh [FLAGS]
#
# Examples:
#   ./scripts/claude/setup-claude-vertex.sh
#   ./scripts/claude/setup-claude-vertex.sh --project my-project --region us-east5
#   ./scripts/claude/setup-claude-vertex.sh --dry-run
#   ./scripts/claude/setup-claude-vertex.sh --cleanup
#
# Flags:
#   --project, -p     GCP project ID (default: still-smithy-407213)
#   --region,  -r     Vertex AI region (default: global)
#   --shell-rc, -s    Shell rc file to modify (default: ~/.zshrc)
#   --skip-adc        Skip the gcloud application-default login step
#   --dry-run, -d     Show commands without executing
#   --cleanup, -c     Remove configuration block from shell rc
#   --help,    -h     Show this help
# =============================================================================

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="setup-claude-vertex.sh"
readonly TOTAL_STEPS=5
readonly CONFIG_BLOCK_START="# >>> claude-code vertex-ai setup >>>"
readonly CONFIG_BLOCK_END="# <<< claude-code vertex-ai setup <<<"

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
REGION="global"
SHELL_RC="${HOME}/.zshrc"
SKIP_ADC=false
DRY_RUN=false
CLEANUP=false

DEFAULT_OPUS_MODEL="claude-opus-4-7"
DEFAULT_SONNET_MODEL="claude-sonnet-4-6"
DEFAULT_HAIKU_MODEL="claude-haiku-4-5@20251001"

# =============================================================================
# Error trap handler
# =============================================================================
error_handler() {
  local line="$1"
  local code="$2"
  log_error "Failed at line ${line} (exit code ${code})"

  case "${code}" in
    2) log_error "Prerequisite not met. Verify gcloud and claude are installed and you are authenticated." ;;
    3) log_error "Insufficient GCP permissions. Verify your account has access to Vertex AI in the project." ;;
    4) log_error "Network error. Verify your internet connection." ;;
    5) log_error "Could not write to ${SHELL_RC}. Check file permissions." ;;
  esac

  if [[ "${CLEANUP}" == false ]]; then
    log_info "To revert partial changes run: ./${SCRIPT_NAME} --cleanup"
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
Configures Claude Code CLI to use Google Vertex AI for model access.

USAGE
  ./${SCRIPT_NAME} [FLAGS]

FLAGS
  --project,  -p <id>      GCP project ID (default: still-smithy-407213)
  --region,   -r <region>  Vertex AI region (default: global)
  --shell-rc, -s <path>    Shell rc file to modify (default: ~/.zshrc)
  --skip-adc               Skip 'gcloud auth application-default login'
  --dry-run,  -d           Preview commands without executing
  --cleanup,  -c           Remove configuration block from shell rc
  --help,     -h           Show this help

EXAMPLES
  # Full setup with defaults
  ./${SCRIPT_NAME}

  # Custom project and region
  ./${SCRIPT_NAME} --project my-project --region us-east5

  # Use bash instead of zsh
  ./${SCRIPT_NAME} --shell-rc ~/.bashrc

  # Preview without changes
  ./${SCRIPT_NAME} --dry-run

  # Revert configuration
  ./${SCRIPT_NAME} --cleanup
EOF
  exit 0
}

# =============================================================================
# Parse flags
# =============================================================================
parse_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project|-p)  PROJECT_ID="$2"; shift 2 ;;
      --region|-r)   REGION="$2";     shift 2 ;;
      --shell-rc|-s) SHELL_RC="$2";   shift 2 ;;
      --skip-adc)    SKIP_ADC=true;   shift ;;
      --dry-run|-d)  DRY_RUN=true;    shift ;;
      --cleanup|-c)  CLEANUP=true;    shift ;;
      --help|-h)     show_help ;;
      *)
        log_error "Unknown flag: $1"
        log_info "Run ./${SCRIPT_NAME} --help for usage."
        exit 1
        ;;
    esac
  done
}

# =============================================================================
# Validate prerequisites
# =============================================================================
validate_prerequisites() {
  log_info "Validating prerequisites..."

  # 1. gcloud installed
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI is not installed. Install it from https://cloud.google.com/sdk/docs/install"
    exit 2
  fi
  log_success "gcloud CLI found"

  # 2. claude CLI installed
  if ! command -v claude &>/dev/null; then
    log_warning "Claude Code CLI ('claude') not found in PATH."
    log_warning "Install it from https://docs.claude.com/en/docs/claude-code/setup before running Claude."
  else
    log_success "Claude Code CLI found"
  fi

  # 3. User authenticated
  local active_account
  active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
  if [[ -z "${active_account}" ]]; then
    log_error "No active gcloud session. Run: gcloud auth login"
    exit 2
  fi
  log_success "Authenticated as ${active_account}"

  # 4. Project accessible
  if [[ -z "${PROJECT_ID}" ]]; then
    log_error "No GCP project configured. Pass --project <id>."
    exit 2
  fi

  if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
    log_error "Project '${PROJECT_ID}' not found or not accessible."
    exit 2
  fi
  log_success "Project '${PROJECT_ID}' is accessible"

  # 5. Vertex AI API enabled
  local api_enabled
  api_enabled=$(gcloud services list --enabled --filter="name:aiplatform.googleapis.com" --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null)
  if [[ -z "${api_enabled}" ]]; then
    log_error "Vertex AI API is not enabled. Run:"
    log_error "  gcloud services enable aiplatform.googleapis.com --project=${PROJECT_ID}"
    exit 2
  fi
  log_success "Vertex AI API is enabled"

  # 6. Shell rc file exists (create if missing)
  if [[ ! -f "${SHELL_RC}" ]]; then
    log_warning "Shell rc file '${SHELL_RC}' does not exist. It will be created."
    if [[ "${DRY_RUN}" == false ]]; then
      touch "${SHELL_RC}" || { log_error "Cannot create ${SHELL_RC}"; exit 5; }
    fi
  fi
  log_success "Shell rc file: ${SHELL_RC}"
}

# =============================================================================
# Step 1 — Show current Claude status
# =============================================================================
step_show_current_status() {
  log_step 1 "Checking current Claude Code authentication"

  if ! command -v claude &>/dev/null; then
    log_warning "Skipping: 'claude' CLI is not installed."
    return 0
  fi

  log_info "Current 'claude' status (review the 'Auth' line):"
  if [[ "${DRY_RUN}" == true ]]; then
    log_dry_run "claude /status"
    return 0
  fi

  # claude /status is interactive; print a hint if it cannot run non-interactively
  claude /status 2>/dev/null || log_warning "Could not run 'claude /status' non-interactively. Run it manually inside a Claude session."
}

# =============================================================================
# Step 2 — Refresh Application Default Credentials
# =============================================================================
step_refresh_adc() {
  log_step 2 "Refreshing Application Default Credentials (ADC)"

  if [[ "${SKIP_ADC}" == true ]]; then
    log_warning "Skipping ADC login (--skip-adc enabled)."
  else
    log_info "Opening browser for 'gcloud auth application-default login'..."
    execute_or_dry_run gcloud auth application-default login
  fi

  log_info "Verifying ADC token..."
  if [[ "${DRY_RUN}" == true ]]; then
    log_dry_run "gcloud auth application-default print-access-token"
  else
    if gcloud auth application-default print-access-token &>/dev/null; then
      log_success "ADC token retrieved successfully"
    else
      log_error "ADC token could not be retrieved. Re-run without --skip-adc."
      exit 3
    fi
  fi

  log_info "Setting active gcloud project to '${PROJECT_ID}'..."
  execute_or_dry_run gcloud config set project "${PROJECT_ID}"
}

# =============================================================================
# Step 3 — Remove existing configuration block
# =============================================================================
remove_config_block() {
  if [[ ! -f "${SHELL_RC}" ]]; then
    return 0
  fi

  if ! grep -qF "${CONFIG_BLOCK_START}" "${SHELL_RC}"; then
    return 0
  fi

  log_info "Removing existing configuration block from ${SHELL_RC}..."
  if [[ "${DRY_RUN}" == true ]]; then
    log_dry_run "sed -i '/${CONFIG_BLOCK_START}/,/${CONFIG_BLOCK_END}/d' ${SHELL_RC}"
    return 0
  fi

  local tmp_file
  tmp_file=$(mktemp)
  awk -v start="${CONFIG_BLOCK_START}" -v end="${CONFIG_BLOCK_END}" '
    $0 == start { skip = 1; next }
    $0 == end   { skip = 0; next }
    !skip       { print }
  ' "${SHELL_RC}" > "${tmp_file}"
  mv "${tmp_file}" "${SHELL_RC}"
  log_success "Existing block removed"
}

# =============================================================================
# Step 4 — Append environment variables to shell rc
# =============================================================================
step_write_env_vars() {
  log_step 3 "Writing environment variables to ${SHELL_RC}"

  remove_config_block

  log_info "Appending Claude Code → Vertex AI configuration block..."

  if [[ "${DRY_RUN}" == true ]]; then
    log_dry_run "Append the following block to ${SHELL_RC}:"
    cat <<EOF
${CONFIG_BLOCK_START}
# Claude Code -> Vertex AI
export CLAUDE_CODE_USE_VERTEX=1
export ANTHROPIC_VERTEX_PROJECT_ID="${PROJECT_ID}"
export CLOUD_ML_REGION="${REGION}"
export ANTHROPIC_DEFAULT_OPUS_MODEL="${DEFAULT_OPUS_MODEL}"
export ANTHROPIC_DEFAULT_SONNET_MODEL="${DEFAULT_SONNET_MODEL}"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="${DEFAULT_HAIKU_MODEL}"
${CONFIG_BLOCK_END}
EOF
    return 0
  fi

  {
    echo ""
    echo "${CONFIG_BLOCK_START}"
    echo "# Claude Code -> Vertex AI"
    echo "export CLAUDE_CODE_USE_VERTEX=1"
    echo "export ANTHROPIC_VERTEX_PROJECT_ID=\"${PROJECT_ID}\""
    echo "export CLOUD_ML_REGION=\"${REGION}\""
    echo "export ANTHROPIC_DEFAULT_OPUS_MODEL=\"${DEFAULT_OPUS_MODEL}\""
    echo "export ANTHROPIC_DEFAULT_SONNET_MODEL=\"${DEFAULT_SONNET_MODEL}\""
    echo "export ANTHROPIC_DEFAULT_HAIKU_MODEL=\"${DEFAULT_HAIKU_MODEL}\""
    echo "${CONFIG_BLOCK_END}"
  } >> "${SHELL_RC}" || { log_error "Failed to write to ${SHELL_RC}"; exit 5; }

  log_success "Configuration block written to ${SHELL_RC}"
}

# =============================================================================
# Step 5 — Final instructions
# =============================================================================
step_final_instructions() {
  log_step 4 "Apply configuration in your current shell"
  log_info "Run the following command to load the new variables:"
  echo -e "  ${COLOR_BOLD}source ${SHELL_RC}${COLOR_RESET}"

  log_step 5 "Validate inside Claude Code"
  log_info "Launch Claude and check authentication:"
  echo -e "  ${COLOR_BOLD}claude${COLOR_RESET}"
  log_info "Inside the session, type:"
  echo -e "  ${COLOR_BOLD}/status${COLOR_RESET}"
  log_info "You should see:"
  cat <<EOF
    Auth:    Google Vertex AI
    Project: ${PROJECT_ID}
    Region:  ${REGION}
    Model:   ${DEFAULT_SONNET_MODEL}
EOF
}

# =============================================================================
# Cleanup mode
# =============================================================================
run_cleanup() {
  log_info "Cleanup mode — removing Vertex AI configuration from ${SHELL_RC}"

  if [[ ! -f "${SHELL_RC}" ]]; then
    log_warning "Shell rc file '${SHELL_RC}' does not exist. Nothing to clean."
    exit 0
  fi

  if ! grep -qF "${CONFIG_BLOCK_START}" "${SHELL_RC}"; then
    log_warning "No Claude Code Vertex AI configuration block found in ${SHELL_RC}."
    exit 0
  fi

  remove_config_block
  log_success "Cleanup complete. Run: source ${SHELL_RC}"
  log_info "Restart Claude Code to fall back to your previous authentication."
}

# =============================================================================
# Main
# =============================================================================
main() {
  parse_flags "$@"

  echo -e "${COLOR_BOLD}Claude Code → Vertex AI Setup v${SCRIPT_VERSION}${COLOR_RESET}"
  echo "============================================================"

  if [[ "${CLEANUP}" == true ]]; then
    run_cleanup
    exit 0
  fi

  validate_prerequisites
  step_show_current_status
  step_refresh_adc
  step_write_env_vars
  step_final_instructions

  echo ""
  log_success "Setup complete."
  if [[ "${DRY_RUN}" == true ]]; then
    log_warning "Dry-run mode: no changes were applied."
  fi
}

main "$@"