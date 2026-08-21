#!/usr/bin/env bash
# =============================================================================
# Centralized Code Review Script
# =============================================================================
# This script handles the complete AI code review process using Claude API.
# It is designed to be called from GitHub Actions workflows.
#
# Usage:
#   ./scripts/code-review.sh \
#     --agent <path-to-agent.md> \
#     --model <claude-model-id> \
#     --arch-threshold <0-10> \
#     --quality-threshold <0-10> \
#     --test-threshold <0-10> \
#     --file-pattern <regex>          # e.g., '\.py$' or '\.(ts|tsx)$'
#     --context-pattern <regex>       # optional: files shown but never scored,
#                                     # e.g. locale catalogs the code references
#     --scope-label <label>           # e.g., 'Python' or 'Next.js/TypeScript'
#
# Required environment variables:
#   ANTHROPIC_API_KEY  - Claude API key
#   GH_TOKEN           - GitHub token with PR comment permissions
#   PR_NUMBER          - Pull request number
#   PR_TITLE           - Pull request title
#   PR_AUTHOR          - Pull request author login
#   BASE_REF           - Base branch name
#   HEAD_REF           - Head branch name
#   HEAD_SHA           - Head commit SHA
#   REPOSITORY         - GitHub repository (owner/repo)
#   PR_BODY            - Pull request body (optional)
# =============================================================================

set -euo pipefail

# =============================================================================
# Default configuration
# =============================================================================
AGENT_FILE=""
MODEL="claude-sonnet-4-6"
ARCH_THRESHOLD=7
QUALITY_THRESHOLD=7
TEST_THRESHOLD=8
# Per-section byte cap (applied separately to the diffs and to the final file
# contents). Measured on a real 27-file TypeScript PR, the prompt runs about
# 2.6 bytes per token, so the worst-case input is roughly (2 x this) / 2.6.
# At 300000 that is ~233K tokens; the 1M-context models leave plenty of room to
# raise it, but every byte is billed on every push, so it is a cost dial as much
# as a quality one. Override per project with --max-diff-size.
MAX_DIFF_SIZE=300000
MAX_OUTPUT_TOKENS=16384  # Allow thorough reasoning over large PRs

# --- Thinking-model controls (all opt-in; defaults reproduce the pre-existing
# --- request body byte for byte, so workflows that don't pass them are unaffected)
#
# On Sonnet 5 / Opus 5 / Fable 5, extended thinking is ON when `thinking` is
# omitted, and thinking tokens are billed against max_tokens. A large PR can
# therefore consume the entire output budget reasoning and never emit a single
# character of review. Raise --max-tokens, cap depth with --effort, or (only on
# models that accept it) pass --thinking disabled.
EFFORT=""     # low|medium|high|xhigh|max -> output_config.effort. Empty = omit.
THINKING=""   # adaptive|disabled -> thinking.type. Empty = omit (model default).
STREAM="false"  # Required for large max_tokens: a non-streaming request that
                # could run past the server's duration limit is rejected.
MAX_FILES=50  # Maximum number of changed files allowed for review
FILE_PATTERN='\.py$'  # Regex pattern for reviewable files (e.g., '\.py$', '\.(ts|tsx)$')
SCOPE_LABEL="Python"  # Label for scope messages (e.g., "Python", "Next.js/TypeScript")

# Files the reviewer needs to READ but must not SCORE: locale message catalogs,
# schemas, fixtures — anything the source code references by name and that the
# file pattern deliberately leaves out.
#
# Without this, a reference the reviewer cannot resolve looks like a bug. A PR
# that adds `t('limits')` to a component and the key to `es.json`/`en.json` shows
# up as a component calling a key that "does not exist", because the JSON never
# reached the prompt — and it stays that way review after review, since no amount
# of new commits can put a file into a section the pattern filters out.
#
# Only the DIFF of these files travels, never their full contents: catalogs run
# to hundreds of KB, they are billed on every push, and what closes the question
# is the added line, not the whole file. Empty = off, and the prompt then looks
# exactly like it did before this flag existed.
CONTEXT_PATTERN=''

# =============================================================================
# Parse arguments
# =============================================================================
while [[ $# -gt 0 ]]; do
  case $1 in
    --agent)
      AGENT_FILE="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --arch-threshold)
      ARCH_THRESHOLD="$2"
      shift 2
      ;;
    --quality-threshold)
      QUALITY_THRESHOLD="$2"
      shift 2
      ;;
    --test-threshold)
      TEST_THRESHOLD="$2"
      shift 2
      ;;
    --max-files)
      MAX_FILES="$2"
      shift 2
      ;;
    --max-tokens)
      MAX_OUTPUT_TOKENS="$2"
      shift 2
      ;;
    --max-diff-size)
      MAX_DIFF_SIZE="$2"
      shift 2
      ;;
    --effort)
      EFFORT="$2"
      shift 2
      ;;
    --thinking)
      THINKING="$2"
      shift 2
      ;;
    --stream)
      STREAM="true"
      shift
      ;;
    --file-pattern)
      FILE_PATTERN="$2"
      shift 2
      ;;
    --scope-label)
      SCOPE_LABEL="$2"
      shift 2
      ;;
    --context-pattern)
      CONTEXT_PATTERN="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# =============================================================================
# Validate required inputs
# =============================================================================
validate_inputs() {
  local missing=()

  [[ -z "${AGENT_FILE}" ]] && missing+=("--agent")
  [[ -z "${ANTHROPIC_API_KEY:-}" ]] && missing+=("ANTHROPIC_API_KEY")
  [[ -z "${GH_TOKEN:-}" ]] && missing+=("GH_TOKEN")
  [[ -z "${PR_NUMBER:-}" ]] && missing+=("PR_NUMBER")
  [[ -z "${PR_TITLE:-}" ]] && missing+=("PR_TITLE")
  [[ -z "${PR_AUTHOR:-}" ]] && missing+=("PR_AUTHOR")
  [[ -z "${BASE_REF:-}" ]] && missing+=("BASE_REF")
  [[ -z "${HEAD_REF:-}" ]] && missing+=("HEAD_REF")
  [[ -z "${HEAD_SHA:-}" ]] && missing+=("HEAD_SHA")
  [[ -z "${REPOSITORY:-}" ]] && missing+=("REPOSITORY")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "::error::Missing required inputs: ${missing[*]}"
    exit 1
  fi

  if [[ ! -f "${AGENT_FILE}" ]]; then
    echo "::error::Agent file not found: ${AGENT_FILE}"
    exit 1
  fi

  echo "Configuration:"
  echo "  Agent: ${AGENT_FILE}"
  echo "  Model: ${MODEL}"
  echo "  Thresholds: Arch>=${ARCH_THRESHOLD}, Quality>=${QUALITY_THRESHOLD}, Test>=${TEST_THRESHOLD}"
  echo "  Max files: ${MAX_FILES}"
  echo "  Max output tokens: ${MAX_OUTPUT_TOKENS}"
  echo "  Max diff size: ${MAX_DIFF_SIZE} bytes per section"
  echo "  Effort: ${EFFORT:-<omitted>}"
  echo "  Thinking: ${THINKING:-<omitted, model default>}"
  echo "  Streaming: ${STREAM}"
  echo "  File pattern: ${FILE_PATTERN}"
  echo "  Context pattern: ${CONTEXT_PATTERN:-<none>}"
  echo "  Scope label: ${SCOPE_LABEL}"
  echo "  Repository: ${REPOSITORY}"
  echo "  PR #${PR_NUMBER}: ${PR_TITLE}"
}

# =============================================================================
# Step 1: Get previous reviews
# =============================================================================
get_previous_reviews() {
  echo ""
  echo "=== Step 1: Getting previous reviews ==="

  gh api "repos/${REPOSITORY}/issues/${PR_NUMBER}/comments" \
    --jq '.[] | select(.body | contains("AI Code Review by Claude"))' \
    > previous_reviews.json || true

  REVIEW_COUNT=$(jq -s 'length' previous_reviews.json)
  echo "Found ${REVIEW_COUNT} previous review(s)"

  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    jq -s '.[-1]' previous_reviews.json > last_review.json

    LAST_REVIEW_DATE=$(jq -r '.created_at' last_review.json)
    REVIEW_BODY=$(jq -r '.body' last_review.json)

    # Extract previous scores from section headers (format: "Architecture (Score: X/10)")
    LAST_ARCH=$(echo "${REVIEW_BODY}" | grep -oP 'Architecture \(Score: \K\d+(?=/10\))' | head -1 || echo "N/A")
    LAST_QUALITY=$(echo "${REVIEW_BODY}" | grep -oP 'Code Quality \(Score: \K\d+(?=/10\))' | head -1 || echo "N/A")
    LAST_TEST=$(echo "${REVIEW_BODY}" | grep -oP 'Testing \(Score: \K\d+(?=/10\))' | head -1 || echo "N/A")

    # Fallback: try details/summary format (format: "**Architecture**: X/10")
    if [[ "${LAST_ARCH}" = "N/A" ]]; then
      LAST_ARCH=$(echo "${REVIEW_BODY}" | grep -oP '\*\*Architecture\*\*:\s*\K\d+(?=/10)' | head -1 || echo "N/A")
    fi
    if [[ "${LAST_QUALITY}" = "N/A" ]]; then
      LAST_QUALITY=$(echo "${REVIEW_BODY}" | grep -oP '\*\*Code Quality\*\*:\s*\K\d+(?=/10)' | head -1 || echo "N/A")
    fi
    if [[ "${LAST_TEST}" = "N/A" ]]; then
      LAST_TEST=$(echo "${REVIEW_BODY}" | grep -oP '\*\*Testing\*\*:\s*\K\d+(?=/10)' | head -1 || echo "N/A")
    fi

    echo "Previous metrics: Arch=${LAST_ARCH}, Quality=${LAST_QUALITY}, Testing=${LAST_TEST}"

    echo "${REVIEW_BODY}" > last_review_body.txt
    echo "${REVIEW_BODY}" | sed -n '/Action Items/,/^---$/p' > previous_action_items.txt || true
  else
    echo "This is the first review for this PR"
    LAST_REVIEW_DATE=""
    LAST_ARCH="N/A"
    LAST_QUALITY="N/A"
    LAST_TEST="N/A"
  fi
}

# =============================================================================
# Step 1.5: Check if PR has reviewable files (Out of Scope detection)
# =============================================================================
check_scope() {
  echo ""
  echo "=== Step 1.5: Checking PR scope ==="

  # Get ALL changed files (unfiltered) for the out-of-scope comment
  git diff --name-only "origin/${BASE_REF}...HEAD" > all_changed_files.txt || true

  # Get only files matching the configured pattern in reviewable paths
  git diff --name-only "origin/${BASE_REF}...HEAD" \
    | grep -E "${FILE_PATTERN}" \
    | tee changed_files.txt || true

  # Supporting files: read, never scored. They do NOT decide scope — a PR that
  # only touches locale catalogs still has nothing for this reviewer to score,
  # and must keep taking the out-of-scope path below.
  > context_files.txt
  if [[ -n "${CONTEXT_PATTERN}" ]]; then
    grep -E "${CONTEXT_PATTERN}" all_changed_files.txt >> context_files.txt || true
    echo "Supporting files: $(wc -l < context_files.txt | tr -d ' ')"
  fi

  local FILE_COUNT
  FILE_COUNT=$(wc -l < changed_files.txt | tr -d ' ')

  if [[ "${FILE_COUNT}" -eq 0 ]]; then
    echo "No reviewable ${SCOPE_LABEL} files found in this PR."
    echo "Activating out-of-scope flow (skipping Claude API call)."

    # Build the list of changed files for the comment
    local FILE_LIST=""
    while IFS= read -r file; do
      FILE_LIST="${FILE_LIST}- \`${file}\`
"
    done < all_changed_files.txt

    # Post out-of-scope comment on PR
    local OOS_COMMENT="## AI Code Review by Claude (Out of Scope)

**Reviewer**: Claude (${MODEL})
**Review Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')

---

## Code Review - Out of Scope

**Decision: APPROVE**

The modified files in this PR are outside the scope of the technical code review.
This review focuses on ${SCOPE_LABEL} source code, and none of the changed files
match the reviewable file patterns.

**Changed files:**
${FILE_LIST}
No architectural, code quality, or testing analysis is required for these changes.
Approving to unblock the merge process.

---
*Automated review by ${SCOPE_LABEL} Code Reviewer Agent*"

    gh issue comment "${PR_NUMBER}" --body "${OOS_COMMENT}"
    echo "Out-of-scope comment posted successfully."

    # Create check run with SUCCESS conclusion
    curl -s -X POST \
      -H "Authorization: token ${GH_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/${REPOSITORY}/check-runs" \
      -d "{
        \"name\": \"Claude Code Review\",
        \"head_sha\": \"${HEAD_SHA}\",
        \"status\": \"completed\",
        \"conclusion\": \"success\",
        \"output\": {
          \"title\": \"Code Review - Out of Scope\",
          \"summary\": \"No reviewable ${SCOPE_LABEL} files found. PR approved to unblock merge.\",
          \"text\": \"Changed files are outside the review scope for ${SCOPE_LABEL}.\"
        }
      }" > /dev/null

    echo "Check run created: success (out-of-scope)"

    # Generate summary if available
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      cat >> "${GITHUB_STEP_SUMMARY}" <<EOF
# Claude Code Review Summary

## PR Information
- **PR #**: ${PR_NUMBER}
- **Title**: ${PR_TITLE}
- **Author**: @${PR_AUTHOR}

## Scope Check
**Result**: Out of Scope — No reviewable ${SCOPE_LABEL} files found.

## Decision
**APPROVE** (automated — no ${SCOPE_LABEL} files to review)

---

See PR comments for details.
EOF
    fi

    echo ""
    echo "=== Out-of-scope flow completed. Exiting successfully. ==="
    exit 0
  fi

  echo "Found ${FILE_COUNT} reviewable ${SCOPE_LABEL} file(s). Continuing with full review pipeline."
}

# =============================================================================
# Step 2: Get changed files and diffs
# =============================================================================
get_changes() {
  echo ""
  echo "=== Step 2: Getting changed files and diffs ==="

  # changed_files.txt already populated by check_scope
  CHANGED_COUNT=$(wc -l < changed_files.txt | tr -d ' ')

  # Validate max files limit
  if [[ ${CHANGED_COUNT} -gt ${MAX_FILES} ]]; then
    echo "::error::PR has ${CHANGED_COUNT} changed ${SCOPE_LABEL} files, exceeding the maximum of ${MAX_FILES}."
    echo ""
    echo "The code review cannot process more than ${MAX_FILES} files reliably."
    echo "Please split this PR into smaller, focused pull requests."
    exit 1
  fi

  LINES_ADDED=$(git diff --numstat "origin/${BASE_REF}...HEAD" | awk '{sum+=$1} END {print sum+0}')
  LINES_DELETED=$(git diff --numstat "origin/${BASE_REF}...HEAD" | awk '{sum+=$2} END {print sum+0}')

  echo "Changed files: ${CHANGED_COUNT}, +${LINES_ADDED} / -${LINES_DELETED}"

  # Create diffs and collect final file contents
  mkdir -p diffs
  > diffs/all_diffs.txt
  > diffs/final_contents.txt

  while IFS= read -r file; do
    if [[ -f "${file}" ]]; then
      # Collect diff
      echo "=== DIFF FOR: ${file} ===" >> diffs/all_diffs.txt
      git diff "origin/${BASE_REF}...HEAD" -- "${file}" >> diffs/all_diffs.txt
      echo "" >> diffs/all_diffs.txt

      # Collect final file content (current HEAD state) for accurate review
      local ext="${file##*.}"
      echo "### ${file}" >> diffs/final_contents.txt
      echo "\`\`\`${ext}" >> diffs/final_contents.txt
      cat "${file}" >> diffs/final_contents.txt
      echo "" >> diffs/final_contents.txt
      echo "\`\`\`" >> diffs/final_contents.txt
      echo "" >> diffs/final_contents.txt
    fi
  done < changed_files.txt

  # Supporting files: diff only, and capped apart from the code diff so a big
  # catalog can never push reviewable code out of the prompt.
  > diffs/context_diffs.txt
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    echo "=== DIFF FOR: ${file} ===" >> diffs/context_diffs.txt
    git diff "origin/${BASE_REF}...HEAD" -- "${file}" >> diffs/context_diffs.txt
    echo "" >> diffs/context_diffs.txt
  done < context_files.txt

  CONTEXT_SIZE=$(wc -c < diffs/context_diffs.txt | tr -d ' ')
  if [[ ${CONTEXT_SIZE} -gt ${MAX_DIFF_SIZE} ]]; then
    echo "::warning::Supporting-file diffs truncated: ${CONTEXT_SIZE} bytes exceeds the ${MAX_DIFF_SIZE}-byte cap."
    head -c ${MAX_DIFF_SIZE} diffs/context_diffs.txt > diffs/context_diffs_truncated.txt
    printf "\n\n[... Supporting diff truncated due to size ...]" >> diffs/context_diffs_truncated.txt
    mv diffs/context_diffs_truncated.txt diffs/context_diffs.txt
  fi

  # Truncate diffs if too large
  DIFF_SIZE=$(wc -c < diffs/all_diffs.txt | tr -d ' ')
  if [[ ${DIFF_SIZE} -gt ${MAX_DIFF_SIZE} ]]; then
    echo "::warning::Diffs truncated: ${DIFF_SIZE} bytes exceeds the ${MAX_DIFF_SIZE}-byte cap. Raise --max-diff-size or split the PR."
    head -c ${MAX_DIFF_SIZE} diffs/all_diffs.txt > diffs/all_diffs_truncated.txt
    printf "\n\n[... Diff truncated due to size ...]" >> diffs/all_diffs_truncated.txt
    mv diffs/all_diffs_truncated.txt diffs/all_diffs.txt
  fi

  # Truncate final contents if too large (use same limit)
  CONTENT_SIZE=$(wc -c < diffs/final_contents.txt | tr -d ' ')
  if [[ ${CONTENT_SIZE} -gt ${MAX_DIFF_SIZE} ]]; then
    # This section is the one the prompt declares as the SOURCE OF TRUTH, so
    # cutting it means the reviewer scores code it never saw. Say so loudly.
    echo "::warning::Final file contents truncated: ${CONTENT_SIZE} bytes exceeds the ${MAX_DIFF_SIZE}-byte cap. The reviewer will not see the tail of this PR. Raise --max-diff-size or split the PR."
    head -c ${MAX_DIFF_SIZE} diffs/final_contents.txt > diffs/final_contents_truncated.txt
    printf "\n\n[... Content truncated due to size ...]" >> diffs/final_contents_truncated.txt
    mv diffs/final_contents_truncated.txt diffs/final_contents.txt
  fi
}

# =============================================================================
# Step 3: Build prompt and call Claude API
# =============================================================================
call_claude_api() {
  echo ""
  echo "=== Step 3: Calling Claude API ==="

  local REVIEW_NUMBER=$((REVIEW_COUNT + 1))

  # Build review context JSON
  cat > review_context.json <<EOF
{
  "pr_number": "${PR_NUMBER}",
  "pr_title": "${PR_TITLE}",
  "pr_author": "${PR_AUTHOR}",
  "base_branch": "${BASE_REF}",
  "head_branch": "${HEAD_REF}",
  "files_changed": ${CHANGED_COUNT},
  "lines_added": ${LINES_ADDED},
  "lines_deleted": ${LINES_DELETED},
  "repository": "${REPOSITORY}"
}
EOF

  # Build user prompt
  echo "Please review this Pull Request:" > user_prompt.txt
  echo "" >> user_prompt.txt
  echo "## PR Information" >> user_prompt.txt
  cat review_context.json >> user_prompt.txt
  echo "" >> user_prompt.txt

  # PR description
  echo "## PR Description" >> user_prompt.txt
  echo "${PR_BODY:-No description provided}" >> user_prompt.txt
  echo "" >> user_prompt.txt

  # Changed files list
  echo "## Changed Files" >> user_prompt.txt
  cat changed_files.txt >> user_prompt.txt
  echo "" >> user_prompt.txt

  # Final file contents FIRST (ground truth - must come before diffs and previous context)
  echo "## Final File Contents (Current HEAD State)" >> user_prompt.txt
  echo "" >> user_prompt.txt
  echo "**SOURCE OF TRUTH**: The section below shows the ACTUAL CURRENT content of each changed file." >> user_prompt.txt
  echo "Base ALL your evaluations (architecture, code quality, security) on this code." >> user_prompt.txt
  echo "Do NOT report issues unless they are present in the code below." >> user_prompt.txt
  echo "" >> user_prompt.txt
  cat diffs/final_contents.txt >> user_prompt.txt
  echo "" >> user_prompt.txt

  # Diffs SECOND (for understanding what changed)
  echo "## File Diffs (for reference)" >> user_prompt.txt
  echo "" >> user_prompt.txt
  echo "The diffs below show what changed from the base branch. For multi-commit PRs, these may include intermediate states." >> user_prompt.txt
  echo "Always verify against the Final File Contents above before reporting any issue." >> user_prompt.txt
  echo "" >> user_prompt.txt
  echo '```diff' >> user_prompt.txt
  cat diffs/all_diffs.txt >> user_prompt.txt
  echo '```' >> user_prompt.txt
  echo "" >> user_prompt.txt

  # Supporting files: context, never a score.
  if [[ -s diffs/context_diffs.txt ]]; then
    echo "## Supporting Files (context only — NOT reviewed, NOT scored)" >> user_prompt.txt
    echo "" >> user_prompt.txt
    echo "These files changed in this PR but fall outside the review scope. They are here" >> user_prompt.txt
    echo "so you can RESOLVE REFERENCES made by the reviewable code — a message key, a" >> user_prompt.txt
    echo "schema field, a fixture — instead of reporting them as missing." >> user_prompt.txt
    echo "" >> user_prompt.txt
    echo "**Rules for this section:**" >> user_prompt.txt
    echo "- A line added here is proof that the thing exists. If the code calls a key and" >> user_prompt.txt
    echo "  you see that key added below, the reference RESOLVES — do not report it as" >> user_prompt.txt
    echo "  missing, and close any previous action item that claimed it was." >> user_prompt.txt
    echo "- Only the diff is shown, never the whole file. Something ABSENT here is not" >> user_prompt.txt
    echo "  missing from the codebase — it simply predates this branch. Never infer a" >> user_prompt.txt
    echo "  missing reference from its absence in this section." >> user_prompt.txt
    echo "- Do NOT raise findings about these files, and do NOT let them move any score." >> user_prompt.txt
    echo "  They are not part of the reviewed file count." >> user_prompt.txt
    echo "" >> user_prompt.txt
    echo "**Files:**" >> user_prompt.txt
    cat context_files.txt >> user_prompt.txt
    echo "" >> user_prompt.txt
    echo '```diff' >> user_prompt.txt
    cat diffs/context_diffs.txt >> user_prompt.txt
    echo '```' >> user_prompt.txt
    echo "" >> user_prompt.txt
  fi

  # Previous review context LAST (scores + action items + key issues)
  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    cat >> user_prompt.txt <<EOF

## Previous Review Context

**This is an INCREMENTAL REVIEW** - Review #${REVIEW_NUMBER}

- **Previous Review Date**: ${LAST_REVIEW_DATE}
- **Previous Metrics**: Architecture: ${LAST_ARCH}/10, Code Quality: ${LAST_QUALITY}/10, Testing: ${LAST_TEST}/10

EOF

    # Include previous action items and key issues
    echo "### Previous Review Feedback" >> user_prompt.txt
    echo "" >> user_prompt.txt

    if [[ -f last_review_body.txt ]]; then
      # Extract Action Items section
      if grep -q "Action Items" last_review_body.txt; then
        echo "**Previous Action Items:**" >> user_prompt.txt
        sed -n '/Action Items/,/^---$/p' last_review_body.txt | head -80 >> user_prompt.txt
        echo "" >> user_prompt.txt
      fi

      # Extract key issues from previous review
      echo "**Key Issues from Previous Review:**" >> user_prompt.txt
      grep -A 3 '❌\|⚠️\|Issues Found\|Must Fix\|CRITICAL\|NOT ADDRESSED' last_review_body.txt | head -100 >> user_prompt.txt || echo "No critical issues in previous review" >> user_prompt.txt
      echo "" >> user_prompt.txt
    fi

    cat >> user_prompt.txt <<EOF

**IMPORTANT**: Review the previous feedback above. Verify each previous action item against
the Final File Contents to determine if it was addressed. Track persistent issues across reviews.
Only report issues you can verify in the current code.

---

EOF
  fi

  # Incremental review instructions
  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    cat >> user_prompt.txt <<EOF

## CRITICAL INSTRUCTIONS FOR INCREMENTAL REVIEW

**THIS IS REVIEW #${REVIEW_NUMBER}** - The PR has been reviewed ${REVIEW_COUNT} time(s) before.

You MUST follow this process:

1. **Use Final File Contents as Source of Truth**:
   - The "Final File Contents" section shows the ACTUAL CURRENT state of each file
   - When checking if a previous issue was fixed, look at the FINAL FILE CONTENTS, NOT the diffs
   - The diffs may show intermediate commit states where issues existed but were later corrected
   - If the final file content shows the issue is resolved, mark it as COMPLETED regardless of what the diff shows

2. **Validate Progress**:
   - Mark previous action items as COMPLETED if the final file content shows the fix is in place
   - Mark as PARTIALLY COMPLETED if partially addressed
   - Mark as NOT ADDRESSED only if the issue is still present in the FINAL FILE CONTENTS
   - Identify any NEW ISSUES not mentioned before

3. **Update Metrics Based on Final State**:
   - Base your metrics on the CURRENT CODE (final file contents), not on intermediate diff states
   - **INCREASE** metrics if critical issues were fixed
   - **DECREASE** metrics if new critical issues appeared or quality regressed
   - **MAINTAIN** metrics if no significant change
   - Previous: Arch=${LAST_ARCH}, Quality=${LAST_QUALITY}, Testing=${LAST_TEST}

4. **Structure Your Review**:
   - Start with a "Progress Since Last Review" section
   - Show metric evolution with arrows (increased, decreased, unchanged)
   - Explain WHY each metric changed or stayed the same
   - Only mention NEW issues or PERSISTENT unresolved issues verified against final file contents
   - Acknowledge and recognize improvements made

5. **Decision Logic**:
   - APPROVE if all previous critical issues are fixed in the final code AND no new critical issues
   - REQUEST_CHANGES if previous critical issues remain in the final code OR new critical issues found

**IMPORTANT**: Do NOT re-report issues from previous reviews unless you have verified the issue STILL EXISTS in the "Final File Contents" section. The diffs show the full branch history and may include code from earlier commits that was subsequently fixed. Always verify against the final state.

---

EOF
  fi

  # Final instructions
  cat >> user_prompt.txt <<EOF
Provide a comprehensive code review following your review process. Include:
1. Overall assessment (APPROVE/REQUEST_CHANGES)
2. Architecture analysis
3. Code quality issues
4. Testing coverage
5. Security concerns
6. Specific actionable recommendations

Format your response in Markdown.
EOF

  # Create API request
  # Optional blocks. Each stays out of the body entirely when its flag is unset,
  # so a workflow that passes none of them sends exactly the request this script
  # has always sent.
  local EXTRA='{}'
  if [[ -n "${EFFORT}" ]]; then
    EXTRA=$(jq -n --arg e "${EFFORT}" '{output_config: {effort: $e}}')
  fi

  local THINKING_JSON='null'
  if [[ -n "${THINKING}" ]]; then
    THINKING_JSON=$(jq -n --arg t "${THINKING}" '{type: $t}')
  fi

  local STREAM_JSON='{}'
  if [[ "${STREAM}" = "true" ]]; then
    STREAM_JSON='{"stream": true}'
  fi

  jq -n \
    --rawfile system "${AGENT_FILE}" \
    --rawfile prompt user_prompt.txt \
    --arg model "${MODEL}" \
    --argjson max_tokens "${MAX_OUTPUT_TOKENS}" \
    --argjson extra "${EXTRA}" \
    --argjson thinking "${THINKING_JSON}" \
    --argjson streaming "${STREAM_JSON}" \
    '{
      "model": $model,
      "max_tokens": $max_tokens,
      "system": $system,
      "messages": [
        {
          "role": "user",
          "content": $prompt
        }
      ]
    }
    + $extra
    + $streaming
    + (if $thinking == null then {} else {thinking: $thinking} end)' > api_request.json

  # Call Claude API
  local STOP_REASON="" API_ERROR=""

  if [[ "${STREAM}" = "true" ]]; then
    curl -sS -N -X POST https://api.anthropic.com/v1/messages \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d @api_request.json > api_response_raw.txt

    # Concatenate text deltas only. Thinking deltas arrive as their own block
    # type and must not land in the review.
    REVIEW_CONTENT=$(grep '^data: ' api_response_raw.txt | sed 's/^data: //' \
      | jq -rj 'select(.type=="content_block_delta")
                | select(.delta.type=="text_delta")
                | .delta.text' 2>/dev/null || true)

    STOP_REASON=$(grep '^data: ' api_response_raw.txt | sed 's/^data: //' \
      | jq -r 'select(.type=="message_delta") | .delta.stop_reason // empty' 2>/dev/null \
      | tail -1 || true)

    # An error can arrive as an SSE event or, when the request is rejected
    # before the stream opens, as a plain JSON body.
    API_ERROR=$(grep '^data: ' api_response_raw.txt | sed 's/^data: //' \
      | jq -r 'select(.type=="error") | .error.message // empty' 2>/dev/null | head -1 || true)
    if [[ -z "${API_ERROR}" ]]; then
      API_ERROR=$(jq -r 'select(.type=="error") | .error.message // empty' \
        api_response_raw.txt 2>/dev/null | head -1 || true)
    fi
  else
    curl -sS -X POST https://api.anthropic.com/v1/messages \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d @api_request.json > api_response_raw.txt

    # Join every text block. Indexing .content[0] breaks the moment the model
    # emits a thinking block first, which thinking-enabled models always do.
    REVIEW_CONTENT=$(jq -r '[.content[]? | select(.type=="text") | .text] | join("")' \
      api_response_raw.txt 2>/dev/null || true)
    STOP_REASON=$(jq -r '.stop_reason // empty' api_response_raw.txt 2>/dev/null || true)
    API_ERROR=$(jq -r 'select(.type=="error") | .error.message // empty' \
      api_response_raw.txt 2>/dev/null | head -1 || true)
  fi

  if [[ -n "${API_ERROR}" ]]; then
    echo "::error::Claude API rejected the request: ${API_ERROR}"
    echo "Request parameters: model=${MODEL} max_tokens=${MAX_OUTPUT_TOKENS} effort=${EFFORT:-<omitted>} thinking=${THINKING:-<omitted>} stream=${STREAM}"
    exit 1
  fi

  if [[ "${REVIEW_CONTENT}" == "null" ]] || [[ -z "${REVIEW_CONTENT}" ]]; then
    if [[ "${STOP_REASON}" = "max_tokens" ]]; then
      echo "::error::The model used the entire ${MAX_OUTPUT_TOKENS}-token output budget without emitting any review text."
      echo ""
      echo "On thinking-enabled models (Sonnet 5, Opus 5, Fable 5) extended thinking is ON"
      echo "by default and its tokens count against max_tokens. On a large PR the model can"
      echo "spend the whole budget reasoning and never reach the report."
      echo ""
      echo "Fix by any of:"
      echo "  --max-tokens <n>     give thinking and the report room (32000 is a good start)"
      echo "  --effort medium      cap how deep the model reasons"
      echo "  --thinking disabled  only on models that accept it (Sonnet 5 does; Fable 5 returns 400)"
    else
      echo "::error::Failed to get review from Claude API (stop_reason=${STOP_REASON:-unknown})"
    fi
    echo ""
    echo "First 2000 bytes of the API response:"
    head -c 2000 api_response_raw.txt
    exit 1
  fi

  if [[ "${STOP_REASON}" = "max_tokens" ]]; then
    echo "::warning::Review was truncated at the ${MAX_OUTPUT_TOKENS}-token limit; scores or sections may be missing. Consider raising --max-tokens."
  fi

  echo "${REVIEW_CONTENT}" > claude_review.md

  # Determine decision (check REQUEST_CHANGES first since "APPROVE" appears inside it)
  if echo "${REVIEW_CONTENT}" | grep -qE "REQUEST_CHANGES|REQUEST CHANGES"; then
    DECISION="REQUEST_CHANGES"
  elif echo "${REVIEW_CONTENT}" | grep -q "APPROVE"; then
    DECISION="APPROVE"
  else
    DECISION="COMMENT"
  fi

  # Extract scores from section headers (format: "Architecture (Score: X/10)")
  ARCH_SCORE=$(echo "${REVIEW_CONTENT}" | grep -oP 'Architecture \(Score: \K\d+(?=/10\))' | head -1 || echo "N/A")
  QUALITY_SCORE=$(echo "${REVIEW_CONTENT}" | grep -oP 'Code Quality \(Score: \K\d+(?=/10\))' | head -1 || echo "N/A")
  TEST_SCORE=$(echo "${REVIEW_CONTENT}" | grep -oP 'Testing \(Score: \K\d+(?=/10\))' | head -1 || echo "N/A")

  echo "Decision: ${DECISION}"
  echo "Scores: Arch=${ARCH_SCORE}, Quality=${QUALITY_SCORE}, Testing=${TEST_SCORE}"
}

# =============================================================================
# Step 3.5: Enforce decision consistency with thresholds
# =============================================================================
enforce_decision() {
  local FAILING_METRICS=()

  if [[ "${ARCH_SCORE}" != "N/A" ]] && [[ "${ARCH_SCORE}" -lt "${ARCH_THRESHOLD}" ]]; then
    FAILING_METRICS+=("Architecture: ${ARCH_SCORE}/10 (required: >= ${ARCH_THRESHOLD}/10)")
  fi

  if [[ "${QUALITY_SCORE}" != "N/A" ]] && [[ "${QUALITY_SCORE}" -lt "${QUALITY_THRESHOLD}" ]]; then
    FAILING_METRICS+=("Code Quality: ${QUALITY_SCORE}/10 (required: >= ${QUALITY_THRESHOLD}/10)")
  fi

  if [[ "${TEST_SCORE}" != "N/A" ]] && [[ "${TEST_SCORE}" -lt "${TEST_THRESHOLD}" ]]; then
    FAILING_METRICS+=("Testing: ${TEST_SCORE}/10 (required: >= ${TEST_THRESHOLD}/10)")
  fi

  if [[ ${#FAILING_METRICS[@]} -gt 0 ]] && [[ "${DECISION}" != "REQUEST_CHANGES" ]]; then
    echo "Decision overridden: ${DECISION} -> REQUEST_CHANGES (scores below thresholds)"
    for metric in "${FAILING_METRICS[@]}"; do
      echo "  - ${metric}"
    done
    DECISION="REQUEST_CHANGES"

    # Build the reason text for the override notice
    local REASONS=""
    for metric in "${FAILING_METRICS[@]}"; do
      REASONS="${REASONS}\n- ${metric}"
    done

    # Patch the review content to reflect the overridden decision
    # Replace Overall Assessment (handles both "APPROVE" and "**APPROVE**")
    sed -i 's/\*\*Overall Assessment\*\*: \*\*APPROVE\*\*/\*\*Overall Assessment\*\*: \*\*REQUEST_CHANGES\*\*/g' claude_review.md
    sed -i 's/\*\*Overall Assessment\*\*: APPROVE/\*\*Overall Assessment\*\*: REQUEST_CHANGES/g' claude_review.md
    # Replace Decision section header emoji (handles #, ##, ###)
    sed -i 's/\(#[#]* \)✅ Decision/\1⚠️ Decision/g' claude_review.md
    # Replace standalone **APPROVE** lines in the Decision section body (handles #, ##, ###)
    sed -i '/#[#]* ⚠️ Decision/,/^---$/{s/^\*\*APPROVE\*\*/\*\*REQUEST_CHANGES\*\*/; s/^APPROVE/\*\*REQUEST_CHANGES\*\*/;}' claude_review.md

    # Append override notice at the end of the review
    cat >> claude_review.md <<EOF

---

> **⚠️ Decision Override**: Claude's initial assessment was APPROVE, but the following metrics did not meet the required thresholds:
$(printf '%s\n' "${FAILING_METRICS[@]}" | sed 's/^/> - /')
>
> The decision has been changed to **REQUEST_CHANGES**. Please address the metrics above before merging.
EOF
  fi
}

# =============================================================================
# Step 4: Post review comment
# =============================================================================
post_review_comment() {
  echo ""
  echo "=== Step 4: Posting review comment ==="

  local REVIEW_NUMBER=$((REVIEW_COUNT + 1))

  # Change indicator function
  get_change_indicator() {
    local current=$1
    local previous=$2

    if [[ "${previous}" = "N/A" ]] || [[ "${current}" = "N/A" ]]; then
      echo ""
      return
    fi

    if [[ "${current}" -gt "${previous}" ]]; then
      echo " (+$((current - previous)))"
    elif [[ "${current}" -lt "${previous}" ]]; then
      echo " (-$((previous - current)))"
    else
      echo " (=)"
    fi
  }

  local ARCH_CHANGE=$(get_change_indicator "${ARCH_SCORE}" "${LAST_ARCH}")
  local QUALITY_CHANGE=$(get_change_indicator "${QUALITY_SCORE}" "${LAST_QUALITY}")
  local TEST_CHANGE=$(get_change_indicator "${TEST_SCORE}" "${LAST_TEST}")

  # Build metrics section
  local METRICS_SECTION
  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    METRICS_SECTION="<details>
<summary>Review Metrics (Review #${REVIEW_NUMBER})</summary>

### Current Scores
- **Architecture**: ${ARCH_SCORE}/10${ARCH_CHANGE}
- **Code Quality**: ${QUALITY_SCORE}/10${QUALITY_CHANGE}
- **Testing**: ${TEST_SCORE}/10${TEST_CHANGE}

### Previous Scores (Review #${REVIEW_COUNT})
- Architecture: ${LAST_ARCH}/10
- Code Quality: ${LAST_QUALITY}/10
- Testing: ${LAST_TEST}/10

**Decision**: \`${DECISION}\`

</details>"
  else
    METRICS_SECTION="<details>
<summary>Review Metrics (Initial Review)</summary>

- **Architecture Score**: ${ARCH_SCORE}/10
- **Code Quality Score**: ${QUALITY_SCORE}/10
- **Testing Score**: ${TEST_SCORE}/10
- **Decision**: \`${DECISION}\`

</details>"
  fi

  # Build review header
  local REVIEW_LABEL=""
  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    REVIEW_LABEL=" (Review #${REVIEW_NUMBER})"
  fi

  local PREV_LINE=""
  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    PREV_LINE="**Previous Review**: ${LAST_REVIEW_DATE}"
  fi

  local REVIEW_BODY
  REVIEW_BODY=$(cat claude_review.md)

  local REVIEW_WITH_HEADER="## AI Code Review by Claude${REVIEW_LABEL}

**Reviewer**: Claude (${MODEL})
**Review Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
**Files Analyzed**: ${CHANGED_COUNT}
**Lines Changed**: +${LINES_ADDED} / -${LINES_DELETED}
${PREV_LINE}

---

${REVIEW_BODY}

---

${METRICS_SECTION}

---

*This review was generated automatically by Claude AI. Please use your judgment when addressing feedback.*"

  gh issue comment "${PR_NUMBER}" --body "${REVIEW_WITH_HEADER}"
  echo "Review comment posted successfully"
}

# =============================================================================
# Step 5: Create check run
# =============================================================================
create_check_run() {
  echo ""
  echo "=== Step 5: Creating check run ==="

  local CONCLUSION TITLE SUMMARY

  if [[ "${DECISION}" = "APPROVE" ]]; then
    CONCLUSION="success"
    TITLE="Code Review Passed"
    SUMMARY="Claude AI approved this PR. All quality criteria met."
  elif [[ "${DECISION}" = "REQUEST_CHANGES" ]]; then
    CONCLUSION="failure"
    TITLE="Code Review: Changes Requested"
    SUMMARY="Claude AI identified issues that need to be addressed before merge."
  else
    CONCLUSION="neutral"
    TITLE="Code Review: Comments"
    SUMMARY="Claude AI provided feedback for consideration."
  fi

  curl -s -X POST \
    -H "Authorization: token ${GH_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPOSITORY}/check-runs" \
    -d "{
      \"name\": \"Claude Code Review\",
      \"head_sha\": \"${HEAD_SHA}\",
      \"status\": \"completed\",
      \"conclusion\": \"${CONCLUSION}\",
      \"output\": {
        \"title\": \"${TITLE}\",
        \"summary\": \"${SUMMARY}\",
        \"text\": \"See PR comments for detailed review.\"
      }
    }" > /dev/null

  echo "Check run created: ${CONCLUSION}"
}

# =============================================================================
# Step 6: Generate summary
# =============================================================================
generate_summary() {
  echo ""
  echo "=== Step 6: Generating summary ==="

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    cat >> "${GITHUB_STEP_SUMMARY}" <<EOF
# Claude Code Review Summary

## PR Information
- **PR #**: ${PR_NUMBER}
- **Title**: ${PR_TITLE}
- **Author**: @${PR_AUTHOR}

## Changes
- **Files Changed**: ${CHANGED_COUNT}
- **Lines Added**: ${LINES_ADDED}
- **Lines Deleted**: ${LINES_DELETED}

## Review Scores
- **Architecture**: ${ARCH_SCORE}/10
- **Code Quality**: ${QUALITY_SCORE}/10
- **Testing**: ${TEST_SCORE}/10

## Decision
**${DECISION}**

---

See PR comments for detailed feedback.
EOF
  fi
}

# =============================================================================
# Step 7: Quality gate
# =============================================================================
quality_gate() {
  echo ""
  echo "=== Step 7: Quality gate ==="

  local BLOCKING_ISSUES=()

  if [[ "${ARCH_SCORE}" != "N/A" ]] && [[ "${ARCH_SCORE}" -lt "${ARCH_THRESHOLD}" ]]; then
    BLOCKING_ISSUES+=("Architecture: ${ARCH_SCORE}/10 (required: >= ${ARCH_THRESHOLD}/10)")
  fi

  if [[ "${QUALITY_SCORE}" != "N/A" ]] && [[ "${QUALITY_SCORE}" -lt "${QUALITY_THRESHOLD}" ]]; then
    BLOCKING_ISSUES+=("Code Quality: ${QUALITY_SCORE}/10 (required: >= ${QUALITY_THRESHOLD}/10)")
  fi

  if [[ "${TEST_SCORE}" != "N/A" ]] && [[ "${TEST_SCORE}" -lt "${TEST_THRESHOLD}" ]]; then
    BLOCKING_ISSUES+=("Testing: ${TEST_SCORE}/10 (required: >= ${TEST_THRESHOLD}/10)")
  fi

  # Check reviewer decision only when scores are not available
  # When all numeric scores meet thresholds, scores take precedence over textual decision
  local ALL_SCORES_AVAILABLE=true
  if [[ "${ARCH_SCORE}" = "N/A" ]] || [[ "${QUALITY_SCORE}" = "N/A" ]] || [[ "${TEST_SCORE}" = "N/A" ]]; then
    ALL_SCORES_AVAILABLE=false
  fi

  if [[ "${ALL_SCORES_AVAILABLE}" = false ]] && [[ "${DECISION}" = "REQUEST_CHANGES" ]]; then
    BLOCKING_ISSUES+=("Decision: REQUEST_CHANGES - Reviewer requested changes before merge")
  fi

  if [[ ${#BLOCKING_ISSUES[@]} -gt 0 ]]; then
    echo "::error::PR does not meet quality standards for merge"
    echo ""
    echo "Quality Gate: FAILED"
    echo ""
    echo "Blocking Issues:"
    for issue in "${BLOCKING_ISSUES[@]}"; do
      echo "  - ${issue}"
    done
    echo ""
    echo "Current Metrics:"
    echo "  Architecture: ${ARCH_SCORE}/10"
    echo "  Code Quality: ${QUALITY_SCORE}/10"
    echo "  Testing: ${TEST_SCORE}/10"
    echo "  Decision: ${DECISION}"
    echo ""
    echo "Required Metrics:"
    echo "  Architecture: >= ${ARCH_THRESHOLD}/10"
    echo "  Code Quality: >= ${QUALITY_THRESHOLD}/10"
    echo "  Testing: >= ${TEST_THRESHOLD}/10"
    echo "  Decision: APPROVE"
    exit 1
  fi

  echo "Quality Gate: PASSED"
  echo "  Architecture: ${ARCH_SCORE}/10 (required: >= ${ARCH_THRESHOLD}/10)"
  echo "  Code Quality: ${QUALITY_SCORE}/10 (required: >= ${QUALITY_THRESHOLD}/10)"
  echo "  Testing: ${TEST_SCORE}/10 (required: >= ${TEST_THRESHOLD}/10)"
  echo "  Decision: ${DECISION}"
}

# =============================================================================
# Main execution
# =============================================================================
main() {
  validate_inputs
  get_previous_reviews
  check_scope
  get_changes
  call_claude_api
  enforce_decision
  post_review_comment
  create_check_run
  generate_summary
  quality_gate
}

main