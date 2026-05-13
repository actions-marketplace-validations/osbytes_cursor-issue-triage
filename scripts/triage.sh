#!/usr/bin/env bash
# Cursor issue triage: guard | trigger | add-label
set -euo pipefail

: "${ACTION_ROOT:?ACTION_ROOT must point to the action install directory}"

cmd="${1:?usage: triage.sh <guard|trigger|add-label>}"

guard() {
  : "${GH_TOKEN:?}"
  : "${TRIAGE_ENQUEUED_LABEL:?}"
  : "${ISSUE_NUMBER:?}"
  : "${GITHUB_REPOSITORY:?}"

  local owner="${GITHUB_REPOSITORY%/*}"
  local repo="${GITHUB_REPOSITORY#*/}"

  local issue_data
  issue_data="$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $issue: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $issue) {
          labels(first: 100) {
            nodes {
              name
            }
          }
          closedByPullRequestsReferences(first: 1, includeClosedPrs: true) {
            totalCount
          }
        }
      }
    }' -F owner="${owner}" -F repo="${repo}" -F issue="${ISSUE_NUMBER}")"

  local has_enqueued linked_pr_count
  has_enqueued="$(echo "${issue_data}" | jq -r --arg enq "${TRIAGE_ENQUEUED_LABEL}" '.data.repository.issue.labels.nodes | any(.name == $enq)')"
  linked_pr_count="$(echo "${issue_data}" | jq -r '.data.repository.issue.closedByPullRequestsReferences.totalCount')"

  if [ "${has_enqueued}" = "true" ]; then
    echo "should_run=false" >> "${GITHUB_OUTPUT}"
    echo "reason=Issue already has ${TRIAGE_ENQUEUED_LABEL} label." >> "${GITHUB_OUTPUT}"
    return 0
  fi

  if [ "${linked_pr_count}" != "0" ]; then
    echo "should_run=false" >> "${GITHUB_OUTPUT}"
    echo "reason=Issue already has an associated PR." >> "${GITHUB_OUTPUT}"
    return 0
  fi

  echo "should_run=true" >> "${GITHUB_OUTPUT}"
  echo "reason=No linked PR and no enqueued label (${TRIAGE_ENQUEUED_LABEL}) found." >> "${GITHUB_OUTPUT}"
}

trigger() {
  : "${CURSOR_API_KEY:?}"
  : "${GITHUB_EVENT_PATH:?}"
  : "${ISSUE_NUMBER:?}"
  : "${GITHUB_REPOSITORY:?}"
  : "${TRIAGE_BRANCH_PREFIX:?}"
  : "${TRIAGE_CONTRIBUTING_DOC:?}"
  : "${CURSOR_AGENTS_URL:?}"

  local repository="${GITHUB_REPOSITORY}"
  local repository_url="https://github.com/${repository}"
  local branch_name="${TRIAGE_BRANCH_PREFIX}-${ISSUE_NUMBER}"

  local issue_json issue_title issue_body issue_url issue_state issue_labels issue_body_raw
  issue_json="$(jq '.issue | {title, body, state, url: .html_url, labels: ((.labels // []) | map({name}))}' "${GITHUB_EVENT_PATH}")"
  issue_title="$(echo "${issue_json}" | jq -r '.title')"
  issue_body="$(echo "${issue_json}" | jq -r '.body // "(no body provided)"')"
  issue_url="$(echo "${issue_json}" | jq -r '.url')"
  issue_state="$(echo "${issue_json}" | jq -r '.state')"
  issue_labels="$(echo "${issue_json}" | jq -r '[.labels[].name] | join(", ")')"
  issue_body_raw="$(echo "${issue_json}" | jq -r '.body // ""')"

  local issue_body_for_prompt="${issue_body}"
  local body_tmp request_tmp=""
  body_tmp="$(mktemp)"
  trap 'rm -f "${body_tmp}" "${request_tmp}"' EXIT
  printf '%s' "${issue_body_raw}" > "${body_tmp}"
  if printf '%s' "${issue_body_raw}" | grep -qP '!\[[^\]]*\]\(https://[^)]+\)|<img[^>]+src=["'\'']?https://'; then
    issue_body_for_prompt="${issue_body}$(printf '\n\n## Issue images (multimodal)\n\nUp to five images from this issue are attached to this agent task in API order: first every markdown ![...](https://...) URL in body order, then every HTML <img src="https://..."> URL in body order, deduplicated. Prefer those image inputs when they are relevant to the task.\n')"
  fi

  local prompt_text
  prompt_text="$(jq -nr \
    --arg num "${ISSUE_NUMBER}" \
    --arg repo "${repository}" \
    --arg title "${issue_title}" \
    --arg body "${issue_body_for_prompt}" \
    --arg url "${issue_url}" \
    --arg state "${issue_state}" \
    --arg labels "${issue_labels}" \
    --arg doc "${TRIAGE_CONTRIBUTING_DOC}" \
    '[
      "# GitHub Issue #\($num)",
      "",
      "## Authoritative identifiers for this agent task",
      "",
      "The GitHub **issue** you are implementing is **#\($num)** only: \($url)",
      "",
      "GitHub applies closing keywords (Closes, Fixes, Resolves, and similar) to whatever numeric reference follows them in the same repository. If that number is a pull request, merging your PR will close that pull request instead of an issue. Issue and pull request numbers share one sequence, so a number in the Description section is not proof it is an issue.",
      "",
      "**You must never place a closing keyword before any # reference except #\($num).** Numbers and URLs in the Description below are background only; they may name unrelated pull requests or issues. Do not copy those numbers into Closes, Fixes, or Resolves lines.",
      "",
      "**Repository:** \($repo)",
      "**URL:** \($url)",
      "**State:** \($state)",
      "**Labels:** \($labels)",
      "",
      "## Title",
      "",
      $title,
      "",
      "## Description",
      "",
      $body,
      "",
      "---",
      "",
      "## Required pull request description line",
      "",
      "Put the following line verbatim on its own line in the pull request description so GitHub links and closes **this** issue when the PR merges:",
      "",
      "Closes #\($num)",
      "",
      "Do not write placeholders instead of digits. Do not add other Closes, Fixes, or Resolves lines for different numbers.",
      "",
      "## Required commit message reference",
      "",
      "Reference **#\($num)** in at least one commit message (for example in the subject suffix or body). Prefer the form (#\($num)) without a closing keyword in commits so only the PR description owns the closure line.",
      "",
      "## Implementation instructions",
      "",
      ("Analyze the issue above and implement the fix. Review relevant files in this repository and create a solution. When done, create a pull request with your changes. Follow " + $doc + " for branch naming, PR title, and description conventions (if that file exists in the repository).")
    ] | join("\n")')"

  local images_json
  images_json="$(bash "${ACTION_ROOT}/scripts/encode-cursor-issue-images.sh" "${body_tmp}")"
  request_tmp="$(mktemp)"

  local request_body
  if [ "$(echo "${images_json}" | jq 'length')" -gt 0 ]; then
    request_body="$(jq -n \
      --arg text "${prompt_text}" \
      --arg repo "${repository_url}" \
      --arg branch "${branch_name}" \
      --argjson images "${images_json}" \
      '{prompt:{text:$text,images:$images},source:{repository:$repo},target:{autoCreatePr:true,branchName:$branch}}')"
  else
    request_body="$(jq -n \
      --arg text "${prompt_text}" \
      --arg repo "${repository_url}" \
      --arg branch "${branch_name}" \
      '{prompt:{text:$text},source:{repository:$repo},target:{autoCreatePr:true,branchName:$branch}}')"
  fi

  if [ -n "${TRIAGE_BASE_REF:-}" ]; then
    request_body="$(echo "${request_body}" | jq --arg ref "${TRIAGE_BASE_REF}" '.source.ref = $ref')"
  fi

  printf '%s' "${request_body}" > "${request_tmp}"

  local response agent_id agent_status agent_url
  response="$(curl -sS -X POST \
    --url "${CURSOR_AGENTS_URL}" \
    -u "${CURSOR_API_KEY}:" \
    -H "Content-Type: application/json" \
    --data-binary "@${request_tmp}")"

  echo "${response}" | jq '.'

  agent_id="$(echo "${response}" | jq -r '.id // empty')"
  agent_status="$(echo "${response}" | jq -r '.status // empty')"
  agent_url="$(echo "${response}" | jq -r '.target.url // empty')"

  if [ -z "${agent_id}" ] || [ "${agent_id}" = "null" ]; then
    echo "Cursor Cloud Agents API did not return an agent id."
    return 1
  fi

  echo "cursor_agent_id=${agent_id}" >> "${GITHUB_OUTPUT}"
  echo "cursor_agent_url=${agent_url}" >> "${GITHUB_OUTPUT}"
  echo "cursor_agent_status=${agent_status}" >> "${GITHUB_OUTPUT}"

  echo ""
  echo "Cursor cloud agent id: ${agent_id}"
  echo "Cursor cloud agent status: ${agent_status}"
  echo "Cursor cloud agent URL: ${agent_url}"
  echo ""
}

add_label() {
  : "${GH_TOKEN:?}"
  : "${TRIAGE_ENQUEUED_LABEL:?}"
  : "${ISSUE_NUMBER:?}"
  : "${GITHUB_REPOSITORY:?}"

  gh api \
    --method POST \
    "/repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}/labels" \
    -f "labels[]=${TRIAGE_ENQUEUED_LABEL}"
}

case "${cmd}" in
  guard) guard ;;
  trigger) trigger ;;
  add-label) add_label ;;
  *)
    echo "unknown command: ${cmd}" >&2
    exit 2
    ;;
esac
