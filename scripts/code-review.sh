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
#     --test-threshold <0-10>
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
MODEL="claude-opus-4-20250514"
ARCH_THRESHOLD=7
QUALITY_THRESHOLD=7
TEST_THRESHOLD=8
MAX_DIFF_SIZE=300000  # ~75K tokens per section (diffs + file contents each)
MAX_OUTPUT_TOKENS=16384  # Allow thorough reasoning over large PRs
MAX_FILES=50  # Maximum number of changed files allowed for review

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
# Step 2: Get changed files and diffs
# =============================================================================
get_changes() {
  echo ""
  echo "=== Step 2: Getting changed files and diffs ==="

  git diff --name-only "origin/${BASE_REF}...HEAD" \
    | grep '\.py$' \
    | tee changed_files.txt || true

  CHANGED_COUNT=$(wc -l < changed_files.txt | tr -d ' ')

  # Validate max files limit
  if [[ ${CHANGED_COUNT} -gt ${MAX_FILES} ]]; then
    echo "::error::PR has ${CHANGED_COUNT} changed Python files, exceeding the maximum of ${MAX_FILES}."
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

  # Truncate diffs if too large
  DIFF_SIZE=$(wc -c < diffs/all_diffs.txt | tr -d ' ')
  if [[ ${DIFF_SIZE} -gt ${MAX_DIFF_SIZE} ]]; then
    echo "Diff too large (${DIFF_SIZE} bytes), truncating..."
    head -c ${MAX_DIFF_SIZE} diffs/all_diffs.txt > diffs/all_diffs_truncated.txt
    printf "\n\n[... Diff truncated due to size ...]" >> diffs/all_diffs_truncated.txt
    mv diffs/all_diffs_truncated.txt diffs/all_diffs.txt
  fi

  # Truncate final contents if too large (use same limit)
  CONTENT_SIZE=$(wc -c < diffs/final_contents.txt | tr -d ' ')
  if [[ ${CONTENT_SIZE} -gt ${MAX_DIFF_SIZE} ]]; then
    echo "Final contents too large (${CONTENT_SIZE} bytes), truncating..."
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

  # Previous review context LAST (scores only, no action items to avoid bias)
  if [[ "${REVIEW_COUNT}" -gt 0 ]]; then
    cat >> user_prompt.txt <<EOF

## Previous Review Context

**This is an INCREMENTAL REVIEW** - Review #${REVIEW_NUMBER}

- **Previous Review Date**: ${LAST_REVIEW_DATE}
- **Previous Metrics**: Architecture: ${LAST_ARCH}/10, Code Quality: ${LAST_QUALITY}/10, Testing: ${LAST_TEST}/10

**IMPORTANT**: Evaluate the code FRESH based on the Final File Contents above. Do not assume issues from previous reviews still exist. Only report issues you can verify in the current code.

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
  jq -n \
    --rawfile system "${AGENT_FILE}" \
    --rawfile prompt user_prompt.txt \
    --arg model "${MODEL}" \
    --argjson max_tokens "${MAX_OUTPUT_TOKENS}" \
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
    }' > api_request.json

  # Call Claude API
  RESPONSE=$(curl -s -X POST https://api.anthropic.com/v1/messages \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d @api_request.json)

  # Extract review content
  REVIEW_CONTENT=$(echo "${RESPONSE}" | jq -r '.content[0].text')

  if [[ "${REVIEW_CONTENT}" == "null" ]] || [[ -z "${REVIEW_CONTENT}" ]]; then
    echo "::error::Failed to get review from Claude API"
    echo "API Response: ${RESPONSE}"
    exit 1
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
  get_changes
  call_claude_api
  enforce_decision
  post_review_comment
  create_check_run
  generate_summary
  quality_gate
}

main