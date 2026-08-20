# Code Review Agent - Deployment Guide

## Which workflow do I install?

| Project | Workflow(s) | Script | Reviewer |
|---|---|---|---|
| Python backend (FastAPI/Celery) | `python/code-review-backend-py.yml` | `code-review.sh` | `reviewer-backend-py` |
| Python library | `python/code-review-library-py.yml` | `code-review.sh` | `reviewer-library-py` |
| Airflow DAGs | `python/code-review-airflow-dags-py.yml` | `code-review.sh` | `reviewer-airflow-dags-py` |
| Flutter app | `flutter/code-review-flutter-app.yml` | `code-review.sh` | `reviewer-flutter-app` |
| Next.js, frontend only | `nextjs/code-review-frontend-nextjs.yml` | `code-review.sh` | `reviewer-frontend-nextjs` |
| **Next.js, fullstack** | `nextjs/code-review-fullstack-nextjs.yml` **and** `nextjs/code-review-security-nextjs.yml` | `code-review.sh` + `security-review.sh` | `reviewer-fullstack-nextjs` + `reviewer-security-nextjs` |

**One `code-review.sh` workflow per repository.** Every workflow driven by that script uses
the same PR-comment marker (`AI Code Review by Claude`) and the same check-run name
(`Claude Code Review`). Installing two of them in one repository makes each read the other's
comment as its own previous review and overwrite the other's check.

The security workflow is the exception, and that is the whole reason `security-review.sh`
exists as a separate script: it owns the marker `AI Security Review by Claude` and the
check-run name `Claude Security Review`, so it can run beside a `code-review.sh` workflow on
the same PR without either interfering with the other.

## Prerequisites

1. **Anthropic API Key**: You need an API key from Anthropic
   - Sign up at: https://console.anthropic.com/
   - Create an API key in the API Keys section
   - Recommended: Use a team/organization account for production

2. **GitHub Repository Access**: Admin access to configure repository secrets

## Step-by-Step Deployment

### 1. Add API Key to GitHub Secrets

```bash
# Navigate to your repository on GitHub
# Go to: Settings → Secrets and variables → Actions → New repository secret

Name: ANTHROPIC_API_KEY
Value: sk-ant-api03-...  # Your actual API key
```

### 2. Install Workflow File

The workflow template is available at `git-workflows/python/code-review-backend-py.yml`.

**Option A: Using sync script** (Recommended):

```bash
./scripts/sync-workflows.sh
# Select: code-review-backend-py
```

**Option B: Manual copy**:

```bash
cp git-workflows/python/code-review-backend-py.yml .github/workflows/
```

### 3. Configure Repository Permissions

Ensure the workflow has proper permissions:

```bash
# Go to: Settings → Actions → General → Workflow permissions
# Select: "Read and write permissions"
# Enable: "Allow GitHub Actions to create and approve pull requests"
```

### 4. Test the Integration

Create a test branch and PR:

```bash
# Create test branch
git checkout -b test/code-review-agent

# Make a simple change to a Python file
echo "# Test change for code review" >> agents/__init__.py

# Commit and push
git add agents/__init__.py
git commit -m "test: verify code review agent"
git push origin test/code-review-agent

# Create PR via GitHub CLI
gh pr create \
  --title "Test: Code Review Agent Integration" \
  --body "Testing automated code review functionality"
```

### 5. Monitor First Review

1. Go to the PR page
2. Click on "Actions" tab
3. Watch the "Claude Code Review" workflow execute
4. After completion (~1-2 minutes), check:
   - PR comments for the review
   - Checks tab for the status
   - Artifacts for review details

### 6. Verify Review Quality

The review should include:
- Overall assessment (APPROVE/REQUEST_CHANGES)
- Architecture score (X/10)
- Code quality score (X/10)
- Testing score (X/10)
- Specific actionable recommendations

## Configuration Options

### Customize Review Triggers

Edit `.github/workflows/code-review-backend-py.yml` to change when reviews run:

```yaml
# Current: Reviews only Python files
paths:
  - 'src/**/*.py'
  - 'tests/**/*.py'

# Option: Review all files
paths:
  - '**/*'

# Option: Exclude certain paths
paths-ignore:
  - 'docs/**'
  - 'scripts/**'
```

### Adjust Model Selection

Current model: `claude-sonnet-4-20250514`

To change the model, search for `"model": "claude-sonnet-4-20250514"` in `code-review-backend-py.yml`:

```yaml
"model": "claude-sonnet-4-20250514",  # Cost-effective, high quality
# OR
"model": "claude-opus-4-20241129",    # Maximum quality, higher cost
```

### Modify Review Criteria

Edit `plugins/python-development/agents/reviewer-backend-py.md` to adjust:
- Scoring weights
- Quality thresholds
- Specific checks
- Output format

> **Note**: If you installed via plugins, the agent file is in your Claude Code cache. To customize, fork the repository and create your own marketplace.

### Set Review Strictness

In `code-review-backend-py.yml`, search for the approval logic section (look for `if echo "$REVIEW_CONTENT" | grep -q "APPROVE"`) to modify:

```yaml
# Current: Requires explicit APPROVE keyword
if echo "$REVIEW_CONTENT" | grep -q "APPROVE"; then
  DECISION="APPROVE"

# Option: More strict (require specific score threshold)
ARCH_SCORE=$(extract score from review)
if [ $ARCH_SCORE -ge 8 ]; then
  DECISION="APPROVE"
```

## Cost Management

### Expected Costs

| PRs/Month | Avg Size | Cost/PR | Monthly Cost |
|-----------|----------|---------|--------------|
| 50        | Medium   | $0.30   | $15          |
| 100       | Medium   | $0.30   | $30          |
| 200       | Medium   | $0.30   | $60          |

### Cost Optimization Tips

1. **Limit file scope**: Only review critical paths
2. **Use size limits**: Current 150KB limit prevents runaway costs
3. **Avoid re-reviews**: Concurrency control prevents duplicate runs
4. **Use Sonnet**: More cost-effective than Opus for most reviews

> **Running both reviewers doubles the per-PR cost.** A fullstack repository with both the
> code-review and the security workflow installed pays for two full API calls per push, each
> sending the changed files twice (final contents plus diffs). If that matters, narrow the
> security workflow's trigger with a `paths:` filter so it only runs when the trust boundary
> can actually move — `src/app/api/**`, `src/core/auth/**`, `src/core/donations/**`,
> `src/lib/**`, `prisma/**`. The trade-off is real: a `paths:` filter means a PR that touches
> only UI files gets no security review at all, and "only UI" is exactly what a PR that leaks
> data through a server-to-client prop looks like from the outside.

### Monitor Usage

```bash
# Check Anthropic console for usage
# Go to: https://console.anthropic.com/settings/usage

# Set up billing alerts
# Go to: https://console.anthropic.com/settings/billing
```

## Troubleshooting

### Review Not Posting

**Symptom**: Workflow runs but no review appears

**Check**:
```bash
# 1. Verify API key is set
gh secret list | grep ANTHROPIC

# 2. Check workflow logs
gh run list --workflow=code-review-backend-py.yml
gh run view <run-id> --log

# 3. Verify permissions
# Settings → Actions → General → Workflow permissions
```

### API Rate Limits

**Symptom**: Error "rate_limit_error"

**Solution**:
- Anthropic has generous rate limits (50 requests/minute)
- If hitting limits, add retry logic or queue system
- Consider enterprise plan for higher limits

### Review Quality Issues

**Symptom**: Reviews are too strict/lenient

**Solution**:
1. Adjust criteria in `agents/reviewer-backend-py.md`
2. Modify scoring thresholds
3. Add context-specific instructions
4. Provide example reviews in the agent prompt

### Workflow Timing Out

**Symptom**: Workflow exceeds 15-minute timeout

**Solution**:
```yaml
# Increase timeout in code-review-backend-py.yml
timeout-minutes: 30  # Was 15

# OR reduce diff size
MAX_SIZE=100000  # Was 150000
```

## Best Practices

### 1. Gradual Rollout

```bash
# Phase 1: Comment-only mode (1 week)
# Don't block merges, just provide feedback
gh pr review --comment

# Phase 2: Soft enforcement (2 weeks)
# Block on critical issues only
DECISION="neutral"  # Don't fail checks

# Phase 3: Full enforcement
# Block on REQUEST_CHANGES
DECISION="failure"  # Current behavior
```

### 2. Team Communication

- Announce the new review system to the team
- Share documentation and examples
- Encourage feedback on review quality
- Iterate based on team needs

### 3. Continuous Improvement

- Review the reviews: Check accuracy periodically
- Collect metrics: Track approval rates, false positives
- Update criteria: Refine based on team standards
- Version the agent: Use git tags for agent versions

### 4. Security

- Rotate API keys quarterly
- Use organization secrets (not user secrets)
- Restrict workflow permissions to minimum needed
- Audit review logs regularly

## Integration with Existing Workflows

### With Branch Protection Rules

```bash
# Go to: Settings → Branches → Add rule
# Branch name pattern: main

# Enable:
☑ Require status checks to pass before merging
  ☑ Claude Code Review

# This prevents merge until review passes
```

### With CODEOWNERS

```bash
# .github/CODEOWNERS
# Require both human and AI review

src/**/*.py @team-backend @claude-code-review
tests/**/*.py @team-qa @claude-code-review
```

### With Other CI/CD

```yaml
# Ensure code review runs before expensive tests
jobs:
  code-review:
    # Runs first, fast feedback

  integration-tests:
    needs: code-review  # Only if review passes
    # Expensive tests run after approval
```

## Maintenance

### Weekly Tasks
- Check review quality
- Monitor API costs
- Review workflow logs

### Monthly Tasks
- Update agent criteria based on team feedback
- Review approval/rejection rates
- Optimize diff size limits
- Update model if new versions available

### Quarterly Tasks
- Rotate API keys
- Audit security settings
- Review cost vs value
- Update documentation

## Support

For issues or questions:
1. Check workflow logs: `gh run view <run-id> --log`
2. Review agent documentation: `plugins/python-development/agents/reviewer-backend-py.md`
3. Check architecture doc: `docs/CODE_REVIEW_AGENT_ARCHITECTURE.md`
4. Review quickstart guide: `docs/QUICKSTART_TO_USE_AGENTS.md`
5. Create issue in this repository

## Success Metrics

Track these to measure effectiveness:

- **Review accuracy**: % of reviews that team agrees with
- **Time saved**: Hours saved vs manual reviews
- **Quality improvement**: Reduction in production bugs
- **Team adoption**: % of PRs getting reviewed by agent
- **Cost per review**: Actual vs projected costs

Target metrics:
- Review accuracy: >85%
- Time saved: >15 hours/week
- Cost per review: <$0.50
- Adoption rate: >90% of PRs