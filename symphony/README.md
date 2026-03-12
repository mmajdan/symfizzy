# Symphony for Fizzy

This repository includes a Ruby implementation of Symphony integrated with Rails and backed by Fizzy cards instead of Linear issues.

## What was implemented

- `Symphony::WorkflowLoader` to parse `WORKFLOW.md` front matter + prompt body.
- `Symphony::Config` typed config with defaults and validation for `tracker.kind: fizzy`.
- `Symphony::IssueTrackers::FizzyClient` that reads cards from Fizzy (`Account` + optional boards), normalizes them into Symphony issues, and can move completed cards into `Review`.
- `Symphony::WorkspaceManager` that creates deterministic workspaces by issue identifier.
- `Symphony::PromptRenderer` for `{{ issue.* }}` + run metadata interpolation.
- `Symphony::AgentRunner` that executes the configured codex command in each issue workspace.
- `Symphony::PullRequestCreator` that opens a GitHub pull request (via `gh`) after successful implementation.
- `Symphony::Orchestrator` poll tick that selects active issues, dispatches bounded work, creates a PR, and transitions cards to `Review`.
- `rake symphony:run` task for execution.

## Required tracker configuration (Fizzy)

Symphony in this repo uses Fizzy as the issue tracker adapter.

Required `WORKFLOW.md` front matter fields:

```yaml
tracker:
  kind: fizzy
  account_id: "$FIZZY_ACCOUNT_ID"
```

Optional Fizzy fields:

```yaml
tracker:
  board_ids:
    - "<board-uuid>"
    - "<board-uuid>"
  active_states: ["active"]
  terminal_states: ["closed", "not_now", "done"]
```

How card state is mapped:

- `active` → published/open cards not in `Review` or `Merging` columns.
- `review` → published/open cards in the `Review` column.
- `merging` → published/open cards in the `Merging` column.
- `done` → published/open cards in the `Done` column.
- `closed` → cards with a closure.
- `not_now` → postponed cards.

The default active state list is only `active`. `review` and `merging` are available state mappings, but they are not reprocessed unless explicitly configured in `WORKFLOW.md`.

## Pull request + Review transition behavior

When a Symphony run succeeds:

1. As soon as Symphony claims an active card, it moves the card into the board `In Progress` column.
2. Symphony creates or updates a branch in the workspace.
3. Symphony commits/pushes changes.
4. Symphony opens a GitHub PR using `gh pr create`.
5. Symphony adds the GitHub PR URL as a card comment.
6. Symphony moves the Fizzy card into the board `Review` column.

### Required configuration for PR creation and Review handoff

```yaml
github:
  repo: "$GITHUB_REPO"    # e.g. "org/repo"
  base: "main"
```

Environment variables:

- `GITHUB_REPO` (if referenced in `WORKFLOW.md`).
- GitHub auth for `gh` (`GH_TOKEN` / logged-in `gh auth login`).

If GitHub PR creation is not configured or does not return a PR URL, Symphony will not move the card to `Review`.

## Example WORKFLOW.md

Create `WORKFLOW.md` at repository root:

```md
---
tracker:
  kind: fizzy
  account_id: "$FIZZY_ACCOUNT_ID"
  active_states: ["active", "review", "merging"]
polling:
  interval_ms: 30000
workspace:
  root: tmp/symphony_workspaces
agent:
  max_concurrent_agents: 2
  max_turns: 5
codex:
  command: "codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -"
github:
  repo: "$GITHUB_REPO"
  base: "main"
---
You are working on a Fizzy issue.

Issue: {{ issue.identifier }}
Title: {{ issue.title }}
State: {{ issue.state }}
URL: {{ issue.url }}

Attempt {{ attempt }} turn {{ turn_number }} of {{ max_turns }}.
Implement the requested change and run relevant tests.
```

## Running

One tick:

```bash
FIZZY_ACCOUNT_ID=<external_account_id> GITHUB_REPO=<org/repo> bin/rails "symphony:run[WORKFLOW.md,true]"
```

Long-running daemon loop:

```bash
FIZZY_ACCOUNT_ID=<external_account_id> GITHUB_REPO=<org/repo> bin/rails "symphony:run[WORKFLOW.md,false]"
```

Or simply:

```bash
FIZZY_ACCOUNT_ID=<external_account_id> GITHUB_REPO=<org/repo> bin/rails symphony:run
```

## Notes

- Symphony executes `codex.command` for each selected issue workspace and passes issue metadata via env vars:
  - `SYMPHONY_ISSUE_ID`
  - `SYMPHONY_ISSUE_IDENTIFIER`
  - `SYMPHONY_ISSUE_TITLE`
  - `SYMPHONY_PROMPT`
- Workspaces are created under `workspace.root/<sanitized-identifier>` and are bootstrapped as Git checkouts cloned from the current repository's `origin` remote when possible.
- `codex.command` must be a task-executing command such as `codex exec ...`; `codex app-server` is not a valid unattended runner command for this implementation.
