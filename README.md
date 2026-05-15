# cursor-issue-triage

Composite GitHub Action that starts a [Cursor Cloud Agent](https://cursor.com/docs/cloud-agent/api/v0) when an issue is labeled. The agent receives the issue text (and optional embedded HTTPS images), works in a dedicated branch, and can open a pull request that closes the issue.

## Requirements

- Standard GitHub-hosted runners (`ubuntu-latest`)
- No additional setup required
- No Python or external dependencies

## Quick Start

1. Add `CURSOR_API_KEY` secret to your repository (from [Cursor Dashboard](https://cursor.com/dashboard/integrations))
2. Copy `examples/consumer-workflow.yml` to `.github/workflows/cursor-triage.yml` in your repository (the example pins [`osbytes/cursor-issue-triage@v1`](https://github.com/osbytes/cursor-issue-triage)).
3. Label an issue with `ai-triage` to trigger the agent

If you maintain your own fork of this action, change the `uses:` line to your fork’s `owner/repo` and tag.

## Configuration

### Inputs

| Name | Default | Description |
|------|---------|-------------|
| `triage-enqueued-label` | `ai-triage-enqueued` | Label added after successful enqueue (idempotency) |
| `triage-branch-prefix` | `ai-triage/fix-issue` | Branch name format: `{prefix}-{issue_number}` |
| `triage-contributing-doc` | `CONTRIBUTING.md` | Documentation file referenced in agent prompt |
| `cursor-agents-url` | `https://api.cursor.com/v0/agents` | Cursor API endpoint |
| `triage-base-ref` | *(empty)* | Git ref sent as `source.ref` to Cursor API (branch, tag, or commit) |

### Secrets

| Name | Required | Description |
|------|----------|-------------|
| `cursor_api_key` | Yes | Cursor API key from dashboard or service account |

### Outputs

| Name | Description |
|------|-------------|
| `should-run` | Guard result (`true` if trigger was allowed) |
| `agent-id` | Cursor agent ID (when API returns one) |
| `agent-url` | Cursor agent URL (when API returns one) |
| `agent-status` | Cursor agent status string |

## Usage Example

```yaml
name: AI Triage - Cursor Agent

on:
  issues:
    types:
      - labeled

permissions:
  contents: read
  issues: write
  pull-requests: read

jobs:
  trigger-cursor-agent:
    if: github.event.label.name == 'ai-triage'
    runs-on: ubuntu-latest
    concurrency:
      group: cursor-issue-triage-${{ github.repository }}-${{ github.event.issue.number }}
      cancel-in-progress: false
    steps:
      - uses: osbytes/cursor-issue-triage@v1
        with:
          triage-enqueued-label: ai-triage-enqueued
          triage-branch-prefix: ai-triage/fix-issue
        secrets:
          cursor_api_key: ${{ secrets.CURSOR_API_KEY }}
```

## How It Works

1. **Guard step** - Checks if issue already has enqueued label or linked PR (skips if yes)
2. **Trigger step** - Sends issue content to Cursor Cloud Agents API with:
   - Issue title, body, labels, and state
   - Up to 5 embedded HTTPS images (base64 encoded)
   - Branch name and repository information
   - Custom prompt with instructions to close the issue
3. **Label step** - Adds enqueued label to prevent duplicate runs

## Image Support

The action automatically extracts up to 5 HTTPS images from the issue body:
- Markdown images: `![alt](https://...)`
- HTML images: `<img src="https://...">`

Images are fetched, base64-encoded, and sent to the Cursor API as multimodal inputs. Failed image fetches are silently skipped.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Action fails with "CURSOR_API_KEY not set" | Add `CURSOR_API_KEY` secret to repository settings |
| Agent not triggered on label | Verify label name matches workflow `if` condition |
| "Failed to trigger Cursor agent" | Check API key validity in Cursor Dashboard |
| Images not appearing in agent context | Verify images are HTTPS URLs (HTTP not supported) |
| Action runs but skips immediately | Issue already has `ai-triage-enqueued` label or linked PR |

## Security

- `GITHUB_TOKEN` never leaves GitHub Actions infrastructure
- Only issue content (title, body, labels) is sent to Cursor API
- API key is stored as encrypted GitHub secret
- No credentials are logged or exposed in action output

## Repository Variables (Optional)

Configure these in repository settings to customize behavior:

| Variable | Default | Purpose |
|----------|---------|---------|
| `TRIAGE_TRIGGER_LABEL` | `ai-triage` | Label that triggers triage (configured in workflow) |
| `TRIAGE_ENQUEUED_LABEL` | `ai-triage-enqueued` | Label added after enqueue |
| `TRIAGE_BRANCH_PREFIX` | `ai-triage/fix-issue` | Branch name prefix |
| `TRIAGE_CONTRIBUTING_DOC` | `CONTRIBUTING.md` | Contributing guidelines file |
| `CURSOR_AGENTS_URL` | `https://api.cursor.com/v0/agents` | Cursor API endpoint |
| `TRIAGE_BASE_REF` | *(empty)* | Source git ref for Cursor API |

## Publishing to GitHub Marketplace

This action is published to GitHub Marketplace. To use it:

1. Pin to a specific version tag (e.g., `@v1` or `@v1.0.0`)
2. Floating `v1` branch tracks the latest v1.x release

To publish updates:
1. Create a new release with SemVer tag (e.g., `v1.1.0`)
2. Update `v1` branch to point to new release
3. Marketplace automatically picks up the new version

## License

MIT - see [LICENSE](./LICENSE)
