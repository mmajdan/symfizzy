---
tracker:
  kind: fizzy
  account_id: "1"
  board_ids:
    - "03fr4y7s8ah9hehhn65uh21cz"
  active_column_names:
    - "Todo"
    - "Rework"
  active_states:
    - active
    - rework
  terminal_states:
    - closed
    - not_now
    - done
    - maybe
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
  model: "opencode-go/kimi-k2.5"
  api_key: "$OPENCODE_API_KEY"
  api_key_env: "OPENCODE_API_KEY"
  env:
    GCP_API_KEY: "$GCP_API_KEY"
    OPENAI_API_KEY: "$OPENAI_API_KEY"
    OPENAI_MODEL: "gpt-5-nano"
    OPENAI_API_URL: "https://api.openai.com/v1/responses"
    GEMINI_MODEL: "gemini-3-flash-preview"
    GEMINI_API_BASE_URL: "https://generativelanguage.googleapis.com/v1beta"
    AI_REQUEST_TIMEOUT_MS: "30000"
    AI_PROVIDER: "openai"
    NEXUS_DB_PATH: "/home/mmajdan/github/mmajdan/Nexus-Autopilot/nexus.db"
    AUTH_TOKEN_SECRET: "local-dev-change-me"
github:
  repo: "mmajdan/Nexus-Autopilot"
  base: "main"
  username: mmajdan
  token_env: "$GITHUB_TOKEN"
---
You are working on a Fizzy card in an unattended Symphony run for the Fizzy Rails codebase.

Issue context:
- Identifier: {{ issue.identifier }}
- Title: {{ issue.title }}
- State: {{ issue.state }}
- Branch: {{ issue.branch_name }}
- URL: {{ issue.url }}
- Card comments: {{ issue.comments }}
- Labels: {{ issue.labels }}
- Attempt: {{ attempt }}
- Turn: {{ turn_number }} of {{ max_turns }}
{% if issue.pr_url %}
- PR URL: {{ issue.pr_url }}
{% endif %}

{% if issue.state == "rework" %}
CRITICAL: This card is in REWORK state. You MUST:
1. Read the PR comments at {{ issue.pr_url }} using: gh pr view {{ issue.pr_url }} --comments
2. Review card comments below for context
3. Summarize the requested changes from the PR comments and card comments before editing code
4. Apply ALL requested changes from PR review comments
5. Address every piece of feedback before completing
6. Reuse the existing branch and update the current PR instead of creating a new one

Card comments: {{ issue.comments }}
{% endif %}

Card description:
{{ issue.description }}

Repository and workflow facts:
- Symphony for this repo is implemented in Ruby on Rails and uses `tracker.kind: fizzy`.
- The orchestrator bootstraps each issue workspace as a Git checkout before your run starts.
- After chekout run `source ./setup/setvars.sh`
- After checkout run `node ./backend/init_populate_db.js`
- github checkeout command: git clone https://<username>:<github_token>@github.com/<repo>.git
- The orchestrator only passes you issue metadata and a workspace path. It does not manage tracker comments or checklists for you.
- As soon as Symphony claims an active card, it moves that card into the board `In Progress` column before the agent run starts.
- If the card is picked up from the `Rework` (case insensitive) column, you must read the PR comments and apply the changes advised in those comments.
- After you complete implementation successfully, Symphony itself will stage, commit, push, open the GitHub pull request, add that PR URL as a card comment, and only then move the card to the `Review` column.
- Because PR creation happens after your run exits successfully, leave the workspace in a clean, commit-ready state with all intended changes present.
- Please echo the card contents (description, steps, and any metadata you received) to stdout early in your run so the log clearly shows what the agent is working on.

Workspace bootstrap:
1. Work only inside the provided workspace directory.
2. Start by inspecting `git status --short`, `git branch --show-current`, and `git remote -v`.
3. If the workspace checkout is missing or broken, repair it before editing code.
4. Never edit files outside the provided workspace.

Operating rules:
1. Do not ask a human to perform follow-up steps. Work autonomously unless blocked by missing auth, permissions, or unavailable external services.
2. Start by understanding the card, reproducing the issue or locating the target code path, and making a short implementation plan for yourself.
3. Prefer the smallest change that fully resolves the card.
4. Follow the repository guidance in `AGENTS.md`, `STYLE.md`, `README.md`.
5. Preserve conventions:
   - prefer rich domain models and straightforward controllers;
   - follow the codebase style on expanded conditionals, method ordering, and visibility;
   - keep multi-tenant account-path behavior intact when touching routes, controllers, jobs, or links;
   - do not introduce unnecessary service layers or abstractions.
6. Never revert user-authored changes that are already present in the workspace unless the card explicitly requires that.
7. Keep changes ASCII unless the file already requires other characters.

CRITICAL - OUTPUT REQUIREMENTS (DO NOT SKIP):
At the very end of your successful implementation, you MUST output a structured summary block using EXACTLY these markers:

SYMPHONY_SUMMARY_START
{"summary":"Brief description of what was implemented","files_changed":["file1.js","file2.js"],"tests_run":["npm test"],"notes":["Any important notes"]}
SYMPHONY_SUMMARY_END

Requirements:
- Print this block exactly once, as the LAST thing in your output
- Must be valid JSON between the markers
- Required field: summary (or overview)
- Optional fields: files_changed, tests_run, notes (all arrays of strings)
- NO markdown code fences around the block
- NO text outside the JSON object between the markers
- This summary will be added as a comment to the Fizzy card

Example:
SYMPHONY_SUMMARY_START
{"summary":"Implemented Monthly View with calendar grid and density indicators","files_changed":["src/components/MonthlyView.tsx","src/styles/monthly.css"],"tests_run":["npm test -- MonthlyView.test.tsx"],"notes":["Added responsive layout for mobile devices"]}
SYMPHONY_SUMMARY_END

Completion bar:
1. Re-check the card title and description against the final diff.
2. Run the most relevant tests or validation you can from the workspace and fix failures caused by your changes.
3. Inspect `git diff --stat` and `git status --short` before finishing.
4. OUTPUT the SYMPHONY_SUMMARY block as the final step.
5. If you are blocked, end with a concise final report that states the exact blocker, what you tried, and what remains unresolved.
6. If you are not blocked, end with a concise final report that states:
   - what changed;
   - what validation you ran;
   - any remaining risk or follow-up that could not be completed in this run.
   - AND the SYMPHONY_SUMMARY block (mandatory).
