# Fizzy

This is the source code of [Fizzy](https://fizzy.do/), the Kanban tracking tool for issues and ideas by [37signals](https://37signals.com).


## Running your own Fizzy instance

If you want to run your own Fizzy instance, but don't need to change its code, you can use our pre-built Docker image.
You'll need access to a server on which you can run Docker, and you'll need to configure some options to customize your installation.

You can find the details of how to do a Docker-based deployment in our [Docker deployment guide](docs/docker-deployment.md).

If you want more flexibility to customize your Fizzy installation by changing its code, and deploy those changes to your server, then we recommend you deploy Fizzy with Kamal. You can find a complete walkthrough of doing that in our [Kamal deployment guide](docs/kamal-deployment.md).

### Localhost build and deploy

This repository is also configured to deploy to localhost with Kamal.

Build and deploy the current working tree:

```sh
bin/kamal deploy
```

The app will be available at:

```text
https://localhost:3007
```

Useful localhost commands:

```sh
curl -k https://localhost:3007/up
bin/kamal logs
bin/kamal symphony_logs
```

The default localhost Kamal config also starts the `symphony` worker role. That role reads its
tracker, GitHub, model, and Fireworks API settings directly from [WORKFLOW.md](./WORKFLOW.md).
It resolves the workflow location from `SYMPHONY_WORKFLOW_PATH` first; if that env var points to a
directory, Symphony starts one worker per file inside it.

### Useful Kamal commands on `nexus.majdan.online`

The default deploy config in [`config/deploy.yml`](./config/deploy.yml) targets `nexus.majdan.online`.

Restart the deployed roles:

```sh
bin/kamal app boot -r web
bin/kamal app boot -r symphony
```

Redeploy only one role after config changes:

```sh
bin/kamal deploy -r web
bin/kamal deploy -r symphony
```

Watch logs:

```sh
bin/kamal logs
bin/kamal symphony_logs
bin/kamal app logs -r web --lines 200
bin/kamal app logs -r symphony --lines 200
```

Inspect containers and open remote shells:

```sh
bin/kamal app containers
bin/kamal app containers -r symphony
bin/kamal shell
bin/kamal symphony_shell
```

Verify the direct troubleshooting endpoints:

```sh
curl -i -H 'Host: autopilot.re' http://127.0.0.1:3000/up
curl -i -H 'Host: nexus.majdan.online' http://127.0.0.1:3000/session/new
curl -ik --resolve nexus.majdan.online:3443:127.0.0.1 https://nexus.majdan.online:3443/up
```

Query the production account id for an email address:

```sh
ssh nexus.majdan.online 'name=$(docker ps --format "{{.Names}}" | grep "^fizzy-web" | head -n 1); docker exec "$name" bin/rails runner "identity = Identity.find_by(email_address: %q{mmajdan@protonmail.com}); users = identity&.users&.includes(:account) || []; puts({identity: identity&.id, users: users.map { |u| { user_id: u.id, account_id: u.account&.id, account_external_account_id: u.account&.external_account_id, account_name: u.account&.name } } }.inspect)"'
```

Query the production board ids for that account:

```sh
ssh nexus.majdan.online 'name=$(docker ps --format "{{.Names}}" | grep "^fizzy-web" | head -n 1); docker exec "$name" bin/rails runner "identity = Identity.find_by(email_address: %q{mmajdan@protonmail.com}); account = identity&.users&.first&.account; boards = account ? account.boards.order(:name).map { |b| { id: b.id, name: b.name } } : []; puts({account_external_account_id: account&.external_account_id, boards: boards}.inspect)"'
```

Check that Symphony sees the mounted workflow directory:

```sh
ssh nexus.majdan.online 'name=$(docker ps --format "{{.Names}}" | grep "^fizzy-symphony" | head -n 1); docker exec "$name" env | grep SYMPHONY_WORKFLOW_PATH; docker exec "$name" ls -l /rails/symphony'
```

Create a test card on the `amelia` board in production:

```sh
ssh nexus.majdan.online 'name=$(docker ps --format "{{.Names}}" | grep "^fizzy-web" | head -n 1); docker exec "$name" bin/rails runner "identity = Identity.find_by!(email_address: %q{mmajdan@protonmail.com}); user = identity.users.first; account = user.account; board = account.boards.find_by!(name: %q{amelia}); card = nil; Current.set(account: account, user: user) { card = board.cards.create!(title: %q{Symphony test card}, description: %q{Created by Codex to verify Symphony polling on nexus.}, creator: user, status: %q{published}) }; puts({card_id: card.id, number: card.number, title: card.title, board_id: board.id, account_external_account_id: account.external_account_id}.inspect)"'
```

#### Common failure modes

`symphony` restarts immediately with `Couldn't find Account with [WHERE "accounts"."external_account_id" = ?]`:

- The `tracker.account_id` in `WORKFLOW.md` does not match any production `Account.external_account_id`.
- Query the correct value from production with the commands above, update `/home/mmajdan/workflows/WORKFLOW.md`, then run:

```sh
bin/kamal app boot -r symphony
```

`symphony` cannot see `WORKFLOW.md` on the server:

- `SYMPHONY_WORKFLOW_PATH` must point to the path inside the container, not the host path.
- On `nexus`, the host directory `/home/mmajdan/workflows` is mounted as `/rails/symphony`, so the deploy config should use:

```yaml
env:
  clear:
    SYMPHONY_WORKFLOW_PATH: /rails/symphony

volumes:
  - "/home/mmajdan/workflows:/rails/symphony:ro"
```

- Verify inside the running container:

```sh
ssh nexus.majdan.online 'name=$(docker ps --format "{{.Names}}" | grep "^fizzy-symphony" | head -n 1); docker exec "$name" env | grep SYMPHONY_WORKFLOW_PATH; docker exec "$name" ls -l /rails/symphony'
```

Kamal deploy fails health checks even though Rails boots:

- Do not set a custom Docker DNS override like `dns: 127.0.0.11` for `kamal-proxy`.
- That broke container name resolution on `nexus` and caused proxy health checks to fail before the app was actually reachable.
- Remove the custom DNS override and recreate the proxy with a fresh deploy.

Magic-link emails never arrive and `ActionMailer::MailDeliveryJob` times out:

- On `nexus`, outbound SMTP to Mailgun `465` timed out, while `587` and `2525` worked.
- Use Mailgun submission on `587` with STARTTLS instead of implicit TLS on `465`:

```yaml
SMTP_ADDRESS: smtp.eu.mailgun.org
SMTP_PORT: 587
SMTP_TLS: false
```

- Then redeploy and retry sign-in:

```sh
bin/kamal deploy
bin/kamal logs
```

Symphony creates a workspace but the card stays in `In Progress` and never moves to `Review`:

- On `nexus`, Symphony was reaching `creating PR` and then failing `git commit` because the container had no git author identity.
- Set these env vars for the `symphony` role:

```yaml
GIT_AUTHOR_NAME: Symphony
GIT_AUTHOR_EMAIL: symphony@nexus.majdan.online
GIT_COMMITTER_NAME: Symphony
GIT_COMMITTER_EMAIL: symphony@nexus.majdan.online
```

- Redeploy the `symphony` role and verify the card advances:

```sh
bin/kamal deploy -r symphony
bin/kamal symphony_logs
ssh nexus.majdan.online 'name=$(docker ps --format "{{.Names}}" | grep "^fizzy-web" | head -n 1); docker exec "$name" bin/rails runner "card = Card.find_by!(number: 11); puts({number: card.number, title: card.title, column: card.column&.name, updated_at: card.updated_at}.inspect)"'
```

`nexus.majdan.online` behind Caddy returns `502`, loops on redirects, or serves `404` instead of Fizzy:

- On `nexus`, Fizzy and `Nexus-Autopilot` share the same `kamal-proxy`, which listens on `127.0.0.1:3000` and `127.0.0.1:3443`.
- Caddy must route by hostname to that shared proxy, not to app-specific ports.
- Proxying Fizzy to `127.0.0.1:3000` causes a redirect loop because Kamal redirects HTTP to HTTPS for `nexus.majdan.online`.
- Proxying Fizzy to `127.0.0.1:3443` without overriding the upstream `Host` can return the wrong app or a `404`, depending on which hostname Kamal sees.
- The working Caddy config on `nexus` is:

```caddy
nexus.majdan.online {
        reverse_proxy https://127.0.0.1:3443 {
                header_up Host nexus.majdan.online:3443
                transport http {
                        tls_server_name nexus.majdan.online
                }
        }
}

autopilot.re {
        reverse_proxy http://127.0.0.1:3000
}
```

- Fizzy works directly through the shared Kamal proxy with:

```sh
curl -ik --resolve nexus.majdan.online:3443:127.0.0.1 https://nexus.majdan.online:3443/session/new -I
```

- `Nexus-Autopilot` works directly through the shared Kamal proxy with:

```sh
curl -i -H 'Host: autopilot.re' http://127.0.0.1:3000/up
```

- After changing `/etc/caddy/Caddyfile`, validate and reload:

```sh
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

- Verify the public login page and local Kamal backends:

```sh
curl -k -I https://nexus.majdan.online/session/new
curl -k -I https://autopilot.re
curl -i -H 'Host: autopilot.re' http://127.0.0.1:3000/up
curl -ik --resolve nexus.majdan.online:3443:127.0.0.1 https://nexus.majdan.online:3443/up
```


## Development

You are welcome -- and encouraged -- to modify Fizzy to your liking.
Please see our [Development guide](docs/development.md) for how to get Fizzy set up for local development.

## Running Fizzy in dev mode

Set up the app locally:

```sh
bin/setup
```

Start the development server:

```sh
bin/dev
```

The app will be available at:

```text
http://fizzy.localhost:3006
```

Sign in with `david@example.com`, then grab the verification code from the browser console.

## Running Symphony in dev mode

To run Symphony locally against your development environment, use the Rails task with
[WORKFLOW.md](./WORKFLOW.md):

Run one tick:

```sh
bin/rails "symphony:run[WORKFLOW.md,true]"
```

Run the long-lived worker loop:

```sh
bin/rails "symphony:run[WORKFLOW.md,false]"
```

The default form also works:

```sh
bin/rails symphony:run
```

To load the workflow from another directory:

```sh
SYMPHONY_WORKFLOW_PATH=/path/to/workflow-dir bin/rails symphony:run
```

### Symphony card state mapping

For the Fizzy tracker adapter, Symphony maps cards to logical states like this:

- `active`: card is published/open and its column name is `ToDo` or `In Progress` (case-insensitive)
- `done`: card is published/open and its column name is `Done`
- `review`: card is published/open and its column name is `Review`
- `merging`: card is published/open and its column name is `Merging`
- `not_now`: card is postponed, or any other published/open card outside the mapped active/review/merging/done columns
- `closed`: card is closed

Column-name mapping is case-insensitive for all mapped states, so values like `todo`, `ToDo`,
`TODO`, `in progress`, `IN PROGRESS`, `review`, `REVIEW`, `merging`, `MERGING`, and `done`,
`DONE` are treated the same.

For a typical workflow that should only pick cards from `ToDo` and `In Progress`, use:

```yaml
tracker:
  active_states:
    - active
  terminal_states:
    - closed
    - not_now
    - done
```

## Contributing

We welcome contributions! Please read our [style guide](STYLE.md) before submitting code.


## License

Fizzy is released under the [O'Saasy License](LICENSE.md).
