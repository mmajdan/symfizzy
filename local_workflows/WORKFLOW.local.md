---
tracker:
  kind: fizzy
  account_id: "338000007"
  board_ids:
    - "03fsfyojf2wdh7l7peehqce3x"
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
  repo: "mmajdan/amelia"
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
- PR URL: {{ issue.pr_url }}
- Labels: {{ issue.labels }}
- Card comments: {{ issue.comments }}
- Attempt: {{ attempt }}
- Turn: {{ turn_number }} of {{ max_turns }}

Card description:
{{ issue.description }}

Rework instructions:
- If `State` is `rework`, read the PR comments using `gh pr view {{ issue.pr_url }} --comments`.
- Use both the PR comments and the card comments above to summarize the requested changes before implementing them.
- Apply all requested changes on the existing branch and leave the PR ready to update in place.

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
- At the end of a successful implementation, print a structured summary block to stdout using exactly these markers:

  SYMPHONY_SUMMARY_START
  {"summary":"Short high-signal summary of the change.","files_changed":["path/one.rb","path/two.rb"],"tests_run":["bin/rails test test/path_test.rb"],"notes":["Any important caveats or follow-up notes."]}
  SYMPHONY_SUMMARY_END

  Rules:
  - Print the block exactly once, at the end.
  - The content between the markers must be valid single JSON object syntax.
  - Required: `summary` (or `overview`).
  - Optional: `files_changed`, `tests_run`, `notes`.
  - Keep `summary` brief and specific.
  - Keep `files_changed`, `tests_run`, and `notes` as arrays of strings.
  - Do not wrap the block in Markdown fences.
  - Do not add commentary inside the markers outside the JSON object.
  - This summary will be added as a comment to the Fizzy card.


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

Completion bar:
1. Re-check the card title and description against the final diff.
2. Run the most relevant tests or validation you can from the workspace and fix failures caused by your changes.
3. Inspect `git diff --stat` and `git status --short` before finishing.
4. If you are blocked, end with a concise final report that states the exact blocker, what you tried, and what remains unresolved.
5. If you are not blocked, end with a concise final report that states:
   - what changed;
   - what validation you ran;
   - any remaining risk or follow-up that could not be completed in this run.
