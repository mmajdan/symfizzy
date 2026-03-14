# Symphony for Fizzy

This repository includes a Ruby implementation of Symphony integrated with Rails and backed by Fizzy cards instead of Linear issues.

## What was implemented

- `Symphony::WorkflowLoader` to parse `WORKFLOW.md` front matter + prompt body.
- `Symphony::Config` typed config with defaults and validation for `tracker.kind: fizzy`.
- `Symphony::IssueTrackers::FizzyClient` that reads cards from Fizzy (`Account` + optional boards), normalizes them into Symphony issues, and can move completed cards into `Review`.
- `Symphony::WorkspaceManager` that creates deterministic workspaces by issue identifier.
- `Symphony::PromptRenderer` for `{{ issue.* }}` + run metadata interpolation.
- `Symphony::AgentRunner` that executes the configured runner command in each issue workspace.
- `Symphony::PullRequestCreator` that opens a GitHub pull request (via `gh`) after successful implementation.
- `Symphony::Orchestrator` poll tick that selects active issues, dispatches bounded work, creates a PR, and transitions cards to `Review`.
- `rake symphony:run` task for execution.

## Required tracker configuration (Fizzy)

Symphony in this repo uses Fizzy as the issue tracker adapter.

Required `WORKFLOW.md` front matter fields:

```yaml
tracker:
  kind: fizzy
  account_id: "338000007"
```

Optional Fizzy fields:

```yaml
tracker:
  board_ids:
    - "<board-uuid>"
    - "<board-uuid>"
  active_states: ["active"]
  active_column_names: ["To do", "In Progress"]
  terminal_states: ["closed", "not_now", "done"]
```

Optional runner override:

```yaml
runner:
  command: "opencode run --format json"
  auth_strategy: "api_key_only"
  model: "fireworks-ai/accounts/fireworks/models/kimi-k2p5"
  api_key: "<fireworks-api-key>"
  api_key_env: "FIREWORKS_API_KEY"
  wire_api: "responses"
  model_provider: "symphony_openai_compatible"
```

If `runner.base_url` is set, Symphony injects a compatible `model_provider` override at runtime so
the agent talks to that OpenAI-compatible endpoint instead of the default OpenAI server.
If `runner.model` is set, Symphony adds `-m <model>` to the run command.
Legacy `codex.*` keys are still accepted for backward compatibility, but new configs should prefer
`runner.*`.

How card state is mapped:

- `active` → published/open cards in `ToDo` or `In Progress` columns.
- `review` → published/open cards in the `Review` column.
- `merging` → published/open cards in the `Merging` column.
- `done` → published/open cards in the `Done` column.
- `closed` → cards with a closure.
- `not_now` → postponed cards, and any other published/open cards outside the mapped active/review/merging/done columns.

The default active state list is only `active`. `review` and `merging` are available state mappings, but they are not reprocessed unless explicitly configured in `WORKFLOW.md`.
If you want Symphony to pick only cards from specific board columns while they are still logically
`active`, set `tracker.active_column_names`.

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
  repo: "mmajdan/amelia"
  base: "main"
```

Environment variables:

- GitHub auth for `gh` (`GH_TOKEN` / logged-in `gh auth login`).
- the API key env var referenced by `runner.api_key_env` if your selected runner uses API-key authentication and you do not set `runner.api_key` directly.

If GitHub PR creation is not configured or does not return a PR URL, Symphony will not move the card to `Review`.

## Example WORKFLOW.md

Create `WORKFLOW.md` at repository root:

```md
---
tracker:
  kind: fizzy
  account_id: "338000007"
  board_ids:
    - "03fqxewg4or354b6nhqq8inpb"
  active_states: ["active"]
  terminal_states: ["closed", "not_now", "done"]
polling:
  interval_ms: 30000
workspace:
  root: tmp/symphony_workspaces
agent:
  max_concurrent_agents: 2
  max_turns: 8
runner:
  command: "opencode run --format json"
  auth_strategy: "api_key_only"
  model: "fireworks-ai/accounts/fireworks/models/kimi-k2p5"
  api_key: "<fireworks-api-key>"
  api_key_env: "FIREWORKS_API_KEY"
github:
  repo: "mmajdan/amelia"
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
bin/rails "symphony:run[WORKFLOW.md,true]"
```

Long-running daemon loop:

```bash
bin/rails "symphony:run[WORKFLOW.md,false]"
```

Or simply:

```bash
bin/rails symphony:run
```

You can also set `SYMPHONY_WORKFLOW_PATH` instead of passing an explicit workflow argument. If the
env var points to a directory, Symphony starts one worker per file in that directory and passes
that file as the workflow definition for its worker.

## Notes

- Symphony executes `runner.command` for each selected issue workspace and passes issue metadata via env vars:
  - `SYMPHONY_ISSUE_ID`
  - `SYMPHONY_ISSUE_IDENTIFIER`
  - `SYMPHONY_ISSUE_TITLE`
  - `SYMPHONY_PROMPT`
- Workspaces are created under `workspace.root/<sanitized-identifier>` and are bootstrapped as Git checkouts cloned from `github.repo`.
- `runner.command` must be a task-executing command such as `codex exec ...`; `codex app-server` is not a valid unattended runner command for this implementation.
