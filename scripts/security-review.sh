#!/usr/bin/env bash
# =============================================================================
# Centralized Security Review Script
# =============================================================================
# Sibling of code-review.sh, specialized for SECURITY reviews.
#
# It is a separate script on purpose: code-review.sh is hard-wired to the
# Architecture / Code Quality / Testing triad, uses the comment marker
# "AI Code Review by Claude" and the check-run name "Claude Code Review".
# Running a second reviewer through it on the same PR would make each reviewer
# read the other's comment as its own "previous review" and overwrite the other's
# check-run. This script owns its own marker, its own check-run name and its own
# metric triad, so both reviewers can run on the same PR without interfering.
#
# Metrics (all extracted from headers of the form "<Name> (Score: X/10)"):
#   - Auth & Access Control
#   - Data Protection
#   - Input Validation
#
# Extra gate: the agent must emit a line "**Critical Findings**: N".
# Any N > 0 forces REQUEST_CHANGES and fails the gate, regardless of scores.
#
# Usage:
#   ./scripts/security-review.sh \
#     --agent <path-to-agent.md> \
#     --model <claude-model-id> \
#     --auth-threshold <0-10> \
#     --data-threshold <0-10> \
#     --input-threshold <0-10> \
#     --file-pattern <regex> \
#     --scope-label <label> \
#     --max-files <n>
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
MODEL="claude-fable-5"
AUTH_THRESHOLD=9
DATA_THRESHOLD=9
INPUT_THRESHOLD=9
# Per-section byte cap (diffs and final file contents each). The prompt runs
# about 2.6 bytes per token, so worst-case input is roughly (2 x this) / 2.6.
# Truncation matters more here than in the quality review: a vulnerability the
# reviewer never saw is reported as absent. Override with --max-diff-size.
MAX_DIFF_SIZE=300000

# Thinking on Claude Fable 5 is ALWAYS ON and cannot be disabled: sending
# `thinking: {type: "disabled"}` returns a 400, and `budget_tokens` was removed.
# Thinking tokens are billed against max_tokens, so the only levers are a budget
# large enough to hold the reasoning AND the report, and `output_config.effort`
# to cap how deep the reasoning goes. A 16384 budget is not enough here: on a
# large PR the model spends all of it thinking and emits no report at all.
MAX_OUTPUT_TOKENS=32000
EFFORT="high"   # Security review earns the depth; drop to medium to cut cost.
# Streaming is required at this budget — a non-streaming request that could run
# past the server's duration limit is rejected outright.
STREAM="true"
MAX_FILES=60
FILE_PATTERN='\.(ts|tsx)$'
SCOPE_LABEL="TypeScript"

# Identity of this reviewer. These are what keep it from colliding with
# code-review.sh on the same pull request.
COMMENT_MARKER="AI Security Review by Claude"
CHECK_NAME="Claude Security Review"
ARTIFACT_PREFIX="security"

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
    --auth-threshold)
      AUTH_THRESHOLD="$2"
      shift 2
      ;;
    --data-threshold)
      DATA_THRESHOLD="$2"
      shift 2
      ;;
    --input-threshold)
      INPUT_THRESHOLD="$2"
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
    --no-stream)
      STREAM="false"
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
  echo "  Thresholds: Auth>=${AUTH_THRESHOLD}, Data>=${DATA_THRESHOLD}, Input>=${INPUT_THRESHOLD}"
  echo "  Critical findings allowed: 0"
  echo "  Max files: ${MAX_FILES}"
  echo "  Max output tokens: ${MAX_OUTPUT_TOKENS}"
  echo "  Max diff size: ${MAX_DIFF_SIZE} bytes per section"
  echo "  Effort: ${EFFORT}"
  echo "  Thinking: always on (Fable 5 cannot disable it)"
  echo "  Streaming: ${STREAM}"
  echo "  File pattern: ${FILE_PATTERN}"
  echo "  Scope label: ${SCOPE_LABEL}"
  echo "  Comment marker: ${COMMENT_MARKER}"
  echo "  Check run: ${CHECK_NAME}"
  echo "  Repository: ${REPOSITORY}"
  echo "  PR #${PR_NUMBER}: ${PR_TITLE}"
}

# =============================================================================
# Step 1: Get previous security reviews
# =============================================================================
get_previous_reviews() {
  echo ""
  echo "=== Step 1: Getting previous security reviews ==="

  # Filter by THIS reviewer's marker so the code-quality reviewer's comments
  # are never mistaken for a previous security review.
  gh api "repos/${REPOSITORY}/issues/${PR_NUMBER}/comments" \
    --jq ".[] | select(.body | contains(\"${COMMENT_MARKER}\"))" \
    > previous_security_reviews.json || true

  REVIEW_COUNT=$(jq -s 'length' previous_security_reviews.json)
  echo "Found ${REVIEW_COUNT} previous security review(s)"

  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    jq -s '.[-1]' previous_security_reviews.json > last_security_review.json

    LAST_REVIEW_DATE=$(jq -r '.created_at' last_security_review.json)
    REVIEW_BODY=$(jq -r '.body' last_security_review.json)

    LAST_AUTH=$(echo "${REVIEW_BODY}" | grep -oP 'Auth & Access Control \(Score: \K\d+(?=/10\))' | head -1 || echo "N/A")
    LAST_DATA=$(echo "${REVIEW_BODY}" | grep -oP 'Data Protection \(Score: \K\d+(?=/10\))' | head -1 || echo "N/A")
    LAST_INPUT=$(echo "${REVIEW_BODY}" | grep -oP 'Input Validation \(Score: \K\d+(?=/10\))' | head -1 || echo "N/A")

    # Fallback: the metrics <details> block rendered by post_review_comment
    if [[ "${LAST_AUTH}" = "N/A" ]]; then
      LAST_AUTH=$(echo "${REVIEW_BODY}" | grep -oP '\*\*Auth & Access Control\*\*:\s*\K\d+(?=/10)' | head -1 || echo "N/A")
    fi
    if [[ "${LAST_DATA}" = "N/A" ]]; then
      LAST_DATA=$(echo "${REVIEW_BODY}" | grep -oP '\*\*Data Protection\*\*:\s*\K\d+(?=/10)' | head -1 || echo "N/A")
    fi
    if [[ "${LAST_INPUT}" = "N/A" ]]; then
      LAST_INPUT=$(echo "${REVIEW_BODY}" | grep -oP '\*\*Input Validation\*\*:\s*\K\d+(?=/10)' | head -1 || echo "N/A")
    fi

    echo "Previous metrics: Auth=${LAST_AUTH}, Data=${LAST_DATA}, Input=${LAST_INPUT}"

    echo "${REVIEW_BODY}" > last_security_review_body.txt
  else
    echo "This is the first security review for this PR"
    LAST_REVIEW_DATE=""
    LAST_AUTH="N/A"
    LAST_DATA="N/A"
    LAST_INPUT="N/A"
  fi
}

# =============================================================================
# Step 1.5: Scope check (out-of-scope detection)
# =============================================================================
check_scope() {
  echo ""
  echo "=== Step 1.5: Checking PR scope ==="

  git diff --name-only "origin/${BASE_REF}...HEAD" > all_changed_files.txt || true

  git diff --name-only "origin/${BASE_REF}...HEAD" \
    | grep -E "${FILE_PATTERN}" \
    | tee changed_files.txt || true

  local FILE_COUNT
  FILE_COUNT=$(wc -l < changed_files.txt | tr -d ' ')

  if [[ "${FILE_COUNT}" -eq 0 ]]; then
    echo "No reviewable ${SCOPE_LABEL} files found in this PR."
    echo "Activating out-of-scope flow (skipping Claude API call)."

    local FILE_LIST=""
    while IFS= read -r file; do
      FILE_LIST="${FILE_LIST}- \`${file}\`
"
    done < all_changed_files.txt

    local OOS_COMMENT="## ${COMMENT_MARKER} (Out of Scope)

**Reviewer**: Claude (${MODEL})
**Review Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')

---

## Security Review - Out of Scope

**Decision: APPROVE**

None of the changed files match the reviewable ${SCOPE_LABEL} patterns, so there is
no application code for the security reviewer to analyze.

**Changed files:**
${FILE_LIST}
Approving to unblock the merge process.

---
*Automated review by the ${SCOPE_LABEL} Security Reviewer Agent*"

    gh issue comment "${PR_NUMBER}" --body "${OOS_COMMENT}"
    echo "Out-of-scope comment posted successfully."

    curl -s -X POST \
      -H "Authorization: token ${GH_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/${REPOSITORY}/check-runs" \
      -d "{
        \"name\": \"${CHECK_NAME}\",
        \"head_sha\": \"${HEAD_SHA}\",
        \"status\": \"completed\",
        \"conclusion\": \"success\",
        \"output\": {
          \"title\": \"Security Review - Out of Scope\",
          \"summary\": \"No reviewable ${SCOPE_LABEL} files found. PR approved to unblock merge.\",
          \"text\": \"Changed files are outside the security review scope.\"
        }
      }" > /dev/null

    echo "Check run created: success (out-of-scope)"

    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      cat >> "${GITHUB_STEP_SUMMARY}" <<EOF
# Claude Security Review Summary

## PR Information
- **PR #**: ${PR_NUMBER}
- **Title**: ${PR_TITLE}
- **Author**: @${PR_AUTHOR}

## Scope Check
**Result**: Out of Scope — No reviewable ${SCOPE_LABEL} files found.

## Decision
**APPROVE** (automated — no application code to review)

---

See PR comments for details.
EOF
    fi

    echo ""
    echo "=== Out-of-scope flow completed. Exiting successfully. ==="
    exit 0
  fi

  echo "Found ${FILE_COUNT} reviewable ${SCOPE_LABEL} file(s). Continuing with the security pipeline."
}

# =============================================================================
# Step 2: Get changed files and diffs
# =============================================================================
get_changes() {
  echo ""
  echo "=== Step 2: Getting changed files and diffs ==="

  CHANGED_COUNT=$(wc -l < changed_files.txt | tr -d ' ')

  if [[ ${CHANGED_COUNT} -gt ${MAX_FILES} ]]; then
    echo "::error::PR has ${CHANGED_COUNT} changed ${SCOPE_LABEL} files, exceeding the maximum of ${MAX_FILES}."
    echo ""
    echo "The security review cannot process more than ${MAX_FILES} files reliably."
    echo "Please split this PR into smaller, focused pull requests."
    exit 1
  fi

  LINES_ADDED=$(git diff --numstat "origin/${BASE_REF}...HEAD" | awk '{sum+=$1} END {print sum+0}')
  LINES_DELETED=$(git diff --numstat "origin/${BASE_REF}...HEAD" | awk '{sum+=$2} END {print sum+0}')

  echo "Changed files: ${CHANGED_COUNT}, +${LINES_ADDED} / -${LINES_DELETED}"

  mkdir -p diffs
  > diffs/all_diffs.txt
  > diffs/final_contents.txt

  while IFS= read -r file; do
    if [[ -f "${file}" ]]; then
      echo "=== DIFF FOR: ${file} ===" >> diffs/all_diffs.txt
      git diff "origin/${BASE_REF}...HEAD" -- "${file}" >> diffs/all_diffs.txt
      echo "" >> diffs/all_diffs.txt

      local ext="${file##*.}"
      echo "### ${file}" >> diffs/final_contents.txt
      echo "\`\`\`${ext}" >> diffs/final_contents.txt
      cat "${file}" >> diffs/final_contents.txt
      echo "" >> diffs/final_contents.txt
      echo "\`\`\`" >> diffs/final_contents.txt
      echo "" >> diffs/final_contents.txt
    fi
  done < changed_files.txt

  DIFF_SIZE=$(wc -c < diffs/all_diffs.txt | tr -d ' ')
  if [[ ${DIFF_SIZE} -gt ${MAX_DIFF_SIZE} ]]; then
    echo "::warning::Diffs truncated: ${DIFF_SIZE} bytes exceeds the ${MAX_DIFF_SIZE}-byte cap. Raise --max-diff-size or split the PR."
    head -c ${MAX_DIFF_SIZE} diffs/all_diffs.txt > diffs/all_diffs_truncated.txt
    printf "\n\n[... Diff truncated due to size ...]" >> diffs/all_diffs_truncated.txt
    mv diffs/all_diffs_truncated.txt diffs/all_diffs.txt
  fi

  CONTENT_SIZE=$(wc -c < diffs/final_contents.txt | tr -d ' ')
  if [[ ${CONTENT_SIZE} -gt ${MAX_DIFF_SIZE} ]]; then
    # The security reviewer reports "no findings" for code it was never shown,
    # and that reads identical to a clean review. Never let this be quiet.
    echo "::warning::Final file contents truncated: ${CONTENT_SIZE} bytes exceeds the ${MAX_DIFF_SIZE}-byte cap. Part of this PR was NOT security-reviewed. Raise --max-diff-size or split the PR."
    head -c ${MAX_DIFF_SIZE} diffs/final_contents.txt > diffs/final_contents_truncated.txt
    printf "\n\n[... Content truncated due to size ...]" >> diffs/final_contents_truncated.txt
    mv diffs/final_contents_truncated.txt diffs/final_contents.txt
  fi
}

# =============================================================================
# Step 2.5: Collect security context beyond the diff
# =============================================================================
# A security reviewer that only sees the diff cannot tell whether a new route
# handler is guarded, because the guard lives in a shared file the PR did not
# touch. This step ships a cheap, bounded inventory of the trust boundary.
collect_security_context() {
  echo ""
  echo "=== Step 2.5: Collecting security context ==="

  > security_context.txt

  echo "### API route inventory (path | exported methods | guard helper used)" >> security_context.txt
  echo "" >> security_context.txt
  if [[ -d src/app/api ]]; then
    while IFS= read -r route; do
      local methods guards
      methods=$(grep -oE '^export (async )?function (GET|POST|PUT|PATCH|DELETE)' "${route}" \
        | grep -oE '(GET|POST|PUT|PATCH|DELETE)' | tr '\n' ',' | sed 's/,$//')
      guards=$(grep -oE 'handleAsAdmin|requireAdmin|currentSession|startSession|endSession|serverAuthService|handle\(' "${route}" \
        | sort -u | tr '\n' ' ')
      echo "- \`${route}\` | ${methods:-none} | ${guards:-NO GUARD HELPER DETECTED}" >> security_context.txt
    done < <(find src/app/api -name 'route.ts' -o -name 'route.tsx' | sort)
  else
    echo "- (no src/app/api directory in this repository)" >> security_context.txt
  fi
  echo "" >> security_context.txt

  echo "### Environment variables referenced in the changed files" >> security_context.txt
  echo "" >> security_context.txt
  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    grep -oE 'process\.env\.[A-Z0-9_]+' "${file}" 2>/dev/null || true
  done < changed_files.txt | sort -u | sed 's/^/- `/; s/$/`/' >> security_context.txt
  echo "" >> security_context.txt

  echo "### Client components among the changed files ('use client')" >> security_context.txt
  echo "" >> security_context.txt
  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    if head -3 "${file}" | grep -q "use client"; then
      echo "- \`${file}\`" >> security_context.txt
    fi
  done < changed_files.txt
  echo "" >> security_context.txt

  echo "Security context collected ($(wc -l < security_context.txt | tr -d ' ') lines)"
}

# =============================================================================
# Step 3: Build prompt and call Claude API
# =============================================================================
call_claude_api() {
  echo ""
  echo "=== Step 3: Calling Claude API ==="

  local REVIEW_NUMBER=$((REVIEW_COUNT + 1))

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

  echo "Please perform a SECURITY review of this Pull Request:" > user_prompt.txt
  echo "" >> user_prompt.txt
  echo "## PR Information" >> user_prompt.txt
  cat review_context.json >> user_prompt.txt
  echo "" >> user_prompt.txt

  echo "## PR Description" >> user_prompt.txt
  echo "${PR_BODY:-No description provided}" >> user_prompt.txt
  echo "" >> user_prompt.txt

  echo "## Changed Files" >> user_prompt.txt
  cat changed_files.txt >> user_prompt.txt
  echo "" >> user_prompt.txt

  echo "## Repository Security Context (not part of the diff)" >> user_prompt.txt
  echo "" >> user_prompt.txt
  echo "This inventory is generated from the repository at HEAD. Use it to judge whether a" >> user_prompt.txt
  echo "changed route is guarded, since the guard helper itself may live in an unchanged file." >> user_prompt.txt
  echo "" >> user_prompt.txt
  cat security_context.txt >> user_prompt.txt
  echo "" >> user_prompt.txt

  echo "## Final File Contents (Current HEAD State)" >> user_prompt.txt
  echo "" >> user_prompt.txt
  echo "**SOURCE OF TRUTH**: The section below shows the ACTUAL CURRENT content of each changed file." >> user_prompt.txt
  echo "Base ALL your findings on this code. Do NOT report a vulnerability unless you can point" >> user_prompt.txt
  echo "at the exact line in the code below that exhibits it." >> user_prompt.txt
  echo "" >> user_prompt.txt
  cat diffs/final_contents.txt >> user_prompt.txt
  echo "" >> user_prompt.txt

  echo "## File Diffs (for reference)" >> user_prompt.txt
  echo "" >> user_prompt.txt
  echo "The diffs show what changed from the base branch. For multi-commit PRs they may include" >> user_prompt.txt
  echo "intermediate states. Always verify against the Final File Contents before reporting." >> user_prompt.txt
  echo "" >> user_prompt.txt
  echo '```diff' >> user_prompt.txt
  cat diffs/all_diffs.txt >> user_prompt.txt
  echo '```' >> user_prompt.txt
  echo "" >> user_prompt.txt

  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    cat >> user_prompt.txt <<EOF

## Previous Security Review Context

**This is an INCREMENTAL SECURITY REVIEW** - Review #${REVIEW_NUMBER}

- **Previous Review Date**: ${LAST_REVIEW_DATE}
- **Previous Metrics**: Auth & Access Control: ${LAST_AUTH}/10, Data Protection: ${LAST_DATA}/10, Input Validation: ${LAST_INPUT}/10

EOF

    if [[ -f last_security_review_body.txt ]]; then
      echo "**Findings from the previous security review:**" >> user_prompt.txt
      echo "" >> user_prompt.txt
      grep -A 4 'CRITICAL\|HIGH\|MEDIUM\|Remediation\|NOT ADDRESSED' last_security_review_body.txt \
        | head -120 >> user_prompt.txt || echo "No findings recorded." >> user_prompt.txt
      echo "" >> user_prompt.txt
    fi

    cat >> user_prompt.txt <<EOF

## CRITICAL INSTRUCTIONS FOR INCREMENTAL REVIEW

1. **Verify each previous finding against the Final File Contents**, never against the diffs.
   The diffs contain the full branch history and may show code that was later fixed.
2. Mark each previous finding as FIXED, PARTIALLY FIXED or NOT ADDRESSED.
3. Do NOT re-report a finding you cannot locate in the current code.
4. Update the three scores based on the CURRENT state of the code, and explain each change.
5. A previously reported CRITICAL or HIGH finding that is still present in the current code
   must be reported again and keeps the decision at REQUEST_CHANGES.

---

EOF
  fi

  cat >> user_prompt.txt <<EOF
Produce your security review report following exactly the output format defined in your
instructions. It MUST contain, verbatim and each on its own line:

- \`**Critical Findings**: N\` (N = number of CRITICAL severity findings; use 0 if none)
- A header \`### Auth & Access Control (Score: X/10)\`
- A header \`### Data Protection (Score: X/10)\`
- A header \`### Input Validation (Score: X/10)\`
- A final decision of APPROVE or REQUEST_CHANGES

Format your response in Markdown.
EOF

  # `thinking` is deliberately absent: Fable 5 rejects every explicit value
  # except {type: "adaptive"}, and omitting it selects adaptive anyway.
  local STREAM_JSON='{}'
  if [[ "${STREAM}" = "true" ]]; then
    STREAM_JSON='{"stream": true}'
  fi

  jq -n \
    --rawfile system "${AGENT_FILE}" \
    --rawfile prompt user_prompt.txt \
    --arg model "${MODEL}" \
    --arg effort "${EFFORT}" \
    --argjson max_tokens "${MAX_OUTPUT_TOKENS}" \
    --argjson streaming "${STREAM_JSON}" \
    '{
      "model": $model,
      "max_tokens": $max_tokens,
      "system": $system,
      "output_config": { "effort": $effort },
      "messages": [
        {
          "role": "user",
          "content": $prompt
        }
      ]
    } + $streaming' > api_request.json

  local STOP_REASON="" API_ERROR=""

  if [[ "${STREAM}" = "true" ]]; then
    curl -sS -N -X POST https://api.anthropic.com/v1/messages \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d @api_request.json > api_response_raw.txt

    # Text deltas only. Thinking arrives as its own block type and must never
    # reach the published review.
    REVIEW_CONTENT=$(grep '^data: ' api_response_raw.txt | sed 's/^data: //' \
      | jq -rj 'select(.type=="content_block_delta")
                | select(.delta.type=="text_delta")
                | .delta.text' 2>/dev/null || true)

    STOP_REASON=$(grep '^data: ' api_response_raw.txt | sed 's/^data: //' \
      | jq -r 'select(.type=="message_delta") | .delta.stop_reason // empty' 2>/dev/null \
      | tail -1 || true)

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

    REVIEW_CONTENT=$(jq -r '[.content[]? | select(.type=="text") | .text] | join("")' \
      api_response_raw.txt 2>/dev/null || true)
    STOP_REASON=$(jq -r '.stop_reason // empty' api_response_raw.txt 2>/dev/null || true)
    API_ERROR=$(jq -r 'select(.type=="error") | .error.message // empty' \
      api_response_raw.txt 2>/dev/null | head -1 || true)
  fi

  if [[ -n "${API_ERROR}" ]]; then
    echo "::error::Claude API rejected the request: ${API_ERROR}"
    echo "Request parameters: model=${MODEL} max_tokens=${MAX_OUTPUT_TOKENS} effort=${EFFORT} stream=${STREAM}"
    exit 1
  fi

  # A security gate that cannot read a review must not approve the PR. Every
  # path out of here is either a usable review or a non-zero exit.
  if [[ "${REVIEW_CONTENT}" == "null" ]] || [[ -z "${REVIEW_CONTENT}" ]]; then
    if [[ "${STOP_REASON}" = "max_tokens" ]]; then
      echo "::error::The model used the entire ${MAX_OUTPUT_TOKENS}-token output budget without emitting any review text."
      echo ""
      echo "Thinking is always on for Claude Fable 5 and its tokens count against max_tokens."
      echo "Raise --max-tokens, or lower --effort (currently ${EFFORT}). Thinking cannot be"
      echo "disabled on this model — that returns a 400."
    else
      echo "::error::Failed to get security review from Claude API (stop_reason=${STOP_REASON:-unknown})"
    fi
    echo ""
    echo "First 2000 bytes of the API response:"
    head -c 2000 api_response_raw.txt
    exit 1
  fi

  if [[ "${STOP_REASON}" = "max_tokens" ]]; then
    echo "::warning::Security review was truncated at the ${MAX_OUTPUT_TOKENS}-token limit; the scores or the critical-findings line may be missing, which the gate treats as a blocking failure. Consider raising --max-tokens."
  fi

  echo "${REVIEW_CONTENT}" > claude_security_review.md

  if echo "${REVIEW_CONTENT}" | grep -qE "REQUEST_CHANGES|REQUEST CHANGES"; then
    DECISION="REQUEST_CHANGES"
  elif echo "${REVIEW_CONTENT}" | grep -q "APPROVE"; then
    DECISION="APPROVE"
  else
    DECISION="COMMENT"
  fi

  # `grep | head` exits with head's status, so a `|| echo "N/A"` fallback never
  # fires on a miss — the variable just comes back empty. Normalize explicitly.
  AUTH_SCORE=$(echo "${REVIEW_CONTENT}" | grep -oP 'Auth & Access Control \(Score: \K\d+(?=/10\))' | head -1 || true)
  DATA_SCORE=$(echo "${REVIEW_CONTENT}" | grep -oP 'Data Protection \(Score: \K\d+(?=/10\))' | head -1 || true)
  INPUT_SCORE=$(echo "${REVIEW_CONTENT}" | grep -oP 'Input Validation \(Score: \K\d+(?=/10\))' | head -1 || true)

  [[ -z "${AUTH_SCORE}" ]] && AUTH_SCORE="N/A"
  [[ -z "${DATA_SCORE}" ]] && DATA_SCORE="N/A"
  [[ -z "${INPUT_SCORE}" ]] && INPUT_SCORE="N/A"

  # An absent critical count is treated as unparseable, not as zero. This gate
  # exists to stop critical findings; reading a formatting slip as "none found"
  # would make it fail open, which is the one way it must never fail.
  CRITICAL_COUNT=$(echo "${REVIEW_CONTENT}" | grep -oP '\*\*Critical Findings\*\*:\s*\K\d+' | head -1 || true)
  [[ -z "${CRITICAL_COUNT}" ]] && CRITICAL_COUNT="N/A"

  echo "Decision: ${DECISION}"
  echo "Scores: Auth=${AUTH_SCORE}, Data=${DATA_SCORE}, Input=${INPUT_SCORE}"
  echo "Critical findings: ${CRITICAL_COUNT}"
}

# =============================================================================
# Step 3.5: Enforce decision consistency with thresholds and critical findings
# =============================================================================
enforce_decision() {
  echo ""
  echo "=== Step 3.5: Enforcing decision ==="

  FAILING_METRICS=()

  if [[ "${AUTH_SCORE}" != "N/A" ]] && [[ "${AUTH_SCORE}" -lt "${AUTH_THRESHOLD}" ]]; then
    FAILING_METRICS+=("Auth & Access Control: ${AUTH_SCORE}/10 (required: >= ${AUTH_THRESHOLD}/10)")
  fi

  if [[ "${DATA_SCORE}" != "N/A" ]] && [[ "${DATA_SCORE}" -lt "${DATA_THRESHOLD}" ]]; then
    FAILING_METRICS+=("Data Protection: ${DATA_SCORE}/10 (required: >= ${DATA_THRESHOLD}/10)")
  fi

  if [[ "${INPUT_SCORE}" != "N/A" ]] && [[ "${INPUT_SCORE}" -lt "${INPUT_THRESHOLD}" ]]; then
    FAILING_METRICS+=("Input Validation: ${INPUT_SCORE}/10 (required: >= ${INPUT_THRESHOLD}/10)")
  fi

  if [[ "${CRITICAL_COUNT}" = "N/A" ]]; then
    FAILING_METRICS+=("Critical findings: could not be parsed from the review (the reviewer did not emit the '**Critical Findings**: N' line)")
  elif [[ "${CRITICAL_COUNT}" -gt 0 ]]; then
    FAILING_METRICS+=("Critical findings: ${CRITICAL_COUNT} (required: 0)")
  fi

  # An unscored dimension is not a pass. A security gate that cannot read its
  # own inputs must block, not wave the PR through.
  for pair in "Auth & Access Control:${AUTH_SCORE}" "Data Protection:${DATA_SCORE}" "Input Validation:${INPUT_SCORE}"; do
    if [[ "${pair##*:}" = "N/A" ]]; then
      FAILING_METRICS+=("${pair%%:*}: score could not be parsed from the review")
    fi
  done

  if [[ ${#FAILING_METRICS[@]} -gt 0 ]] && [[ "${DECISION}" != "REQUEST_CHANGES" ]]; then
    echo "Decision overridden: ${DECISION} -> REQUEST_CHANGES"
    for metric in "${FAILING_METRICS[@]}"; do
      echo "  - ${metric}"
    done
    DECISION="REQUEST_CHANGES"

    sed -i 's/\*\*Overall Assessment\*\*: \*\*APPROVE\*\*/\*\*Overall Assessment\*\*: \*\*REQUEST_CHANGES\*\*/g' claude_security_review.md
    sed -i 's/\*\*Overall Assessment\*\*: APPROVE/\*\*Overall Assessment\*\*: REQUEST_CHANGES/g' claude_security_review.md
    sed -i 's/\(#[#]* \)✅ Decision/\1⚠️ Decision/g' claude_security_review.md
    sed -i '/#[#]* ⚠️ Decision/,/^---$/{s/^\*\*APPROVE\*\*/\*\*REQUEST_CHANGES\*\*/; s/^APPROVE/\*\*REQUEST_CHANGES\*\*/;}' claude_security_review.md

    cat >> claude_security_review.md <<EOF

---

> **⚠️ Decision Override**: the reviewer's initial assessment was APPROVE, but the following
> security gates were not met:
$(printf '%s\n' "${FAILING_METRICS[@]}" | sed 's/^/> - /')
>
> The decision has been changed to **REQUEST_CHANGES**. Address the items above before merging.
EOF
  fi
}

# =============================================================================
# Step 4: Post review comment
# =============================================================================
post_review_comment() {
  echo ""
  echo "=== Step 4: Posting security review comment ==="

  local REVIEW_NUMBER=$((REVIEW_COUNT + 1))

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

  local AUTH_CHANGE DATA_CHANGE INPUT_CHANGE
  AUTH_CHANGE=$(get_change_indicator "${AUTH_SCORE}" "${LAST_AUTH}")
  DATA_CHANGE=$(get_change_indicator "${DATA_SCORE}" "${LAST_DATA}")
  INPUT_CHANGE=$(get_change_indicator "${INPUT_SCORE}" "${LAST_INPUT}")

  local METRICS_SECTION
  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    METRICS_SECTION="<details>
<summary>Security Metrics (Review #${REVIEW_NUMBER})</summary>

### Current Scores
- **Auth & Access Control**: ${AUTH_SCORE}/10${AUTH_CHANGE}
- **Data Protection**: ${DATA_SCORE}/10${DATA_CHANGE}
- **Input Validation**: ${INPUT_SCORE}/10${INPUT_CHANGE}
- **Critical Findings**: ${CRITICAL_COUNT}

### Previous Scores (Review #${REVIEW_COUNT})
- Auth & Access Control: ${LAST_AUTH}/10
- Data Protection: ${LAST_DATA}/10
- Input Validation: ${LAST_INPUT}/10

**Decision**: \`${DECISION}\`

</details>"
  else
    METRICS_SECTION="<details>
<summary>Security Metrics (Initial Review)</summary>

- **Auth & Access Control**: ${AUTH_SCORE}/10
- **Data Protection**: ${DATA_SCORE}/10
- **Input Validation**: ${INPUT_SCORE}/10
- **Critical Findings**: ${CRITICAL_COUNT}
- **Decision**: \`${DECISION}\`

</details>"
  fi

  local REVIEW_LABEL=""
  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    REVIEW_LABEL=" (Review #${REVIEW_NUMBER})"
  fi

  local PREV_LINE=""
  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    PREV_LINE="**Previous Review**: ${LAST_REVIEW_DATE}"
  fi

  local REVIEW_BODY
  REVIEW_BODY=$(cat claude_security_review.md)

  local REVIEW_WITH_HEADER="## ${COMMENT_MARKER}${REVIEW_LABEL}

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

*This security review was generated automatically by Claude AI. It complements, and does not
replace, human security judgment.*"

  gh issue comment "${PR_NUMBER}" --body "${REVIEW_WITH_HEADER}"
  echo "Security review comment posted successfully"
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
    TITLE="Security Review Passed"
    SUMMARY="No blocking security findings. All security criteria met."
  elif [[ "${DECISION}" = "REQUEST_CHANGES" ]]; then
    CONCLUSION="failure"
    TITLE="Security Review: Changes Requested"
    SUMMARY="Security issues were identified that must be addressed before merge."
  else
    CONCLUSION="neutral"
    TITLE="Security Review: Comments"
    SUMMARY="The security reviewer provided feedback for consideration."
  fi

  curl -s -X POST \
    -H "Authorization: token ${GH_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPOSITORY}/check-runs" \
    -d "{
      \"name\": \"${CHECK_NAME}\",
      \"head_sha\": \"${HEAD_SHA}\",
      \"status\": \"completed\",
      \"conclusion\": \"${CONCLUSION}\",
      \"output\": {
        \"title\": \"${TITLE}\",
        \"summary\": \"${SUMMARY}\",
        \"text\": \"See PR comments for the detailed security review.\"
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
# Claude Security Review Summary

## PR Information
- **PR #**: ${PR_NUMBER}
- **Title**: ${PR_TITLE}
- **Author**: @${PR_AUTHOR}

## Changes
- **Files Changed**: ${CHANGED_COUNT}
- **Lines Added**: ${LINES_ADDED}
- **Lines Deleted**: ${LINES_DELETED}

## Security Scores
- **Auth & Access Control**: ${AUTH_SCORE}/10
- **Data Protection**: ${DATA_SCORE}/10
- **Input Validation**: ${INPUT_SCORE}/10
- **Critical Findings**: ${CRITICAL_COUNT}

## Decision
**${DECISION}**

---

See PR comments for detailed feedback.
EOF
  fi
}

# =============================================================================
# Step 7: Security gate
# =============================================================================
security_gate() {
  echo ""
  echo "=== Step 7: Security gate ==="

  local BLOCKING_ISSUES=()

  if [[ "${AUTH_SCORE}" != "N/A" ]] && [[ "${AUTH_SCORE}" -lt "${AUTH_THRESHOLD}" ]]; then
    BLOCKING_ISSUES+=("Auth & Access Control: ${AUTH_SCORE}/10 (required: >= ${AUTH_THRESHOLD}/10)")
  fi

  if [[ "${DATA_SCORE}" != "N/A" ]] && [[ "${DATA_SCORE}" -lt "${DATA_THRESHOLD}" ]]; then
    BLOCKING_ISSUES+=("Data Protection: ${DATA_SCORE}/10 (required: >= ${DATA_THRESHOLD}/10)")
  fi

  if [[ "${INPUT_SCORE}" != "N/A" ]] && [[ "${INPUT_SCORE}" -lt "${INPUT_THRESHOLD}" ]]; then
    BLOCKING_ISSUES+=("Input Validation: ${INPUT_SCORE}/10 (required: >= ${INPUT_THRESHOLD}/10)")
  fi

  # A critical finding blocks the merge no matter how the scores came out, and
  # an unreadable count blocks too: this gate must never fail open.
  if [[ "${CRITICAL_COUNT}" = "N/A" ]]; then
    BLOCKING_ISSUES+=("Critical findings: could not be parsed from the review")
  elif [[ "${CRITICAL_COUNT}" -gt 0 ]]; then
    BLOCKING_ISSUES+=("Critical findings: ${CRITICAL_COUNT} (required: 0)")
  fi

  # Same for the scores: an unscored dimension was not reviewed as far as CI
  # can tell, so it does not count as passing.
  for pair in "Auth & Access Control:${AUTH_SCORE}" "Data Protection:${DATA_SCORE}" "Input Validation:${INPUT_SCORE}"; do
    if [[ "${pair##*:}" = "N/A" ]]; then
      BLOCKING_ISSUES+=("${pair%%:*}: score could not be parsed from the review")
    fi
  done

  if [[ "${DECISION}" = "REQUEST_CHANGES" ]]; then
    BLOCKING_ISSUES+=("Decision: REQUEST_CHANGES - Reviewer requested changes before merge")
  fi

  if [[ ${#BLOCKING_ISSUES[@]} -gt 0 ]]; then
    echo "::error::PR does not meet the security standards for merge"
    echo ""
    echo "Security Gate: FAILED"
    echo ""
    echo "Blocking Issues:"
    for issue in "${BLOCKING_ISSUES[@]}"; do
      echo "  - ${issue}"
    done
    echo ""
    echo "Current Metrics:"
    echo "  Auth & Access Control: ${AUTH_SCORE}/10"
    echo "  Data Protection: ${DATA_SCORE}/10"
    echo "  Input Validation: ${INPUT_SCORE}/10"
    echo "  Critical Findings: ${CRITICAL_COUNT}"
    echo "  Decision: ${DECISION}"
    echo ""
    echo "Required Metrics:"
    echo "  Auth & Access Control: >= ${AUTH_THRESHOLD}/10"
    echo "  Data Protection: >= ${DATA_THRESHOLD}/10"
    echo "  Input Validation: >= ${INPUT_THRESHOLD}/10"
    echo "  Critical Findings: 0"
    echo "  Decision: APPROVE"
    exit 1
  fi

  echo "Security Gate: PASSED"
  echo "  Auth & Access Control: ${AUTH_SCORE}/10 (required: >= ${AUTH_THRESHOLD}/10)"
  echo "  Data Protection: ${DATA_SCORE}/10 (required: >= ${DATA_THRESHOLD}/10)"
  echo "  Input Validation: ${INPUT_SCORE}/10 (required: >= ${INPUT_THRESHOLD}/10)"
  echo "  Critical Findings: ${CRITICAL_COUNT} (required: 0)"
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
  collect_security_context
  call_claude_api
  enforce_decision
  post_review_comment
  create_check_run
  generate_summary
  security_gate
}

main
