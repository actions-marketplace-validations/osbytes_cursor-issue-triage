# github-issue-ai-triage

Composite [GitHub Action](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action) that starts a [Cursor Cloud Agent](https://cursor.com/docs/cloud-agent/api/v0) when an issue is labeled. The agent receives the issue text (and optional embedded HTTPS images), works in a dedicated branch, and can open a pull request that closes the issue.

## Use this action in your repository

1. Add a repository secret **`CURSOR_API_KEY`** ([Cursor Dashboard → Integrations](https://cursor.com/dashboard/integrations)).
2. Create labels that match your configuration (defaults below).
3. Copy `examples/consumer-workflow.yml` into **your** repo as `.github/workflows/<something>.yml`, replace `YOUR_GITHUB_LOGIN`, pin a version tag (for example `@v1`), and adjust variables as needed.

The consumer workflow owns **`permissions`**, **`concurrency`**, and the **`if`** that decides which label starts triage. The action owns the guard, Cursor API call, and enqueued label.

### Default labels

- **Trigger** (handled in *your* workflow `if`): `ai-triage` unless you set repository variable `TRIAGE_TRIGGER_LABEL`.
- **Enqueued** (handled inside the action): `ai-triage-enqueued` unless you pass input `triage-enqueued-label` (often from `vars.TRIAGE_ENQUEUED_LABEL`).

### Action inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `triage-enqueued-label` | `ai-triage-enqueued` | Label added after a successful enqueue (idempotency). |
| `triage-branch-prefix` | `ai-triage/fix-issue` | Branch name is `{prefix}-{issue_number}`. |
| `triage-contributing-doc` | `CONTRIBUTING.md` | Referenced in the agent prompt. |
| `cursor-agents-url` | `https://api.cursor.com/v0/agents` | Cursor API endpoint. |
| `triage-base-ref` | *(empty)* | If set, sent as `source.ref` on the Cursor API. |

### Required secret (passed into the action)

| Secret | Purpose |
| --- | --- |
| `cursor_api_key` | Map from your repo secret, e.g. `cursor_api_key: ${{ secrets.CURSOR_API_KEY }}`. |

### Action outputs

| Output | Meaning |
| --- | --- |
| `should-run` | Guard result from the action (`true` means the trigger step was allowed to run). |
| `agent-id`, `agent-url`, `agent-status` | Populated when the Cursor API returns an agent id. |

## Publishing to GitHub Marketplace

Official requirements include: public repository, a **single** `action.yml` at the **repository root**, a **unique** `name` in `action.yml`, and (per current GitHub documentation) **no workflow files** in that same repository ([Publishing actions in GitHub Marketplace](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/publish-in-github-marketplace)).

That is why this repo ships an **example** workflow under `examples/` instead of `.github/workflows/`. To publish:

1. Accept the **GitHub Marketplace Developer Agreement** (linked from the release UI when you publish).
2. Ensure `action.yml` passes validation (banner on the file in the GitHub UI).
3. **Draft a release**, choose a SemVer tag (for example `v1.0.0`), check **Publish this Action to the GitHub Marketplace**, pick categories, publish with 2FA enabled.
4. Consumers pin `uses: your-login/github-issue-ai-triage@v1` (moving `v1` via branch or tag is optional; many actions use a floating `v1` branch updated to the latest `v1.x` commit).

If you need **CI workflows** (lint, integration tests) in the same GitHub repo, GitHub’s Marketplace rule conflicts with that layout; common patterns are a **separate private or internal repo** for CI, or a **fork** that adds `.github/workflows/` only for development and never publishes that fork to the Marketplace.

## Images in issues

`scripts/encode-cursor-issue-images.sh` extracts up to five HTTPS image URLs from the issue body (Markdown `![...](https://...)` first, then HTML `<img src="https://...">`), fetches them, base64-encodes them, and passes them to the v0 API as `prompt.images`.

## License

MIT — see [LICENSE](./LICENSE).
