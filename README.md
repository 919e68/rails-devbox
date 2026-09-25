# rails-devbox

A Docker development environment for Rails and React/Next.js apps.

- Ubuntu 24.04 with Ruby 4.0.7 (YJIT, jemalloc) and Node 24, managed by rbenv and nvm
- Postgres, Redis and Mailpit (or MySQL), ports published on `127.0.0.1` only
- zsh with Starship, fzf, autosuggestions and a colored badge naming the box
- Claude Code, `gh` and `acli`, optionally logged in from tokens in `.env`
- Your home folder (`home/`) lives on this machine and survives rebuilds

## Quick start

Requires Docker (Docker Desktop on macOS or Windows).

```bash
bin/start --init      # create .env and docker-compose.override.yml
$EDITOR .env          # optional: name the box, add tokens (see Configuration)
bin/start             # build, start everything and open a shell
```

The first start compiles Ruby and takes 10 to 20 minutes. Then check the stack:

```bash
tests/verify.sh --skip-rails   # add no flag for the full run with a throwaway Rails app
```

**VS Code / Cursor:** open this folder and run *Dev Containers: Reopen in Container*.

## Daily use

```bash
bin/start           # start what is stopped, apply .env / override changes, open another shell
bin/start --build   # rebuild the image first (after changing the Dockerfile, UID or GID)
bin/start --no-shell
bin/stop            # stop the containers
bin/stop --down     # also remove containers and network
```

Stopping never touches `home/`, database data or installed Ruby/Node versions.

## Configuration

All settings live in `.env` (gitignored, never sent to the build). `.env.example` documents each one. Anyone who can run `docker inspect` on this machine can read the tokens, so treat `.env` like a password file.

| Variable | Default | Purpose | Apply with |
|---|---|---|---|
| `UID`, `GID` | `1000` | Container user IDs, so files in `home/` are yours. `bin/start --init` sets them on Linux; keep `1000` on macOS. | `bin/start --build` |
| `BOX_NAME` | `rails-devbox` | Prompt and status line badge, container name and hostname, network name, service container prefix | `bin/start`, new shell |
| `BOX_COLOR` | `blue` | Badge color: `black` `red` `green` `yellow` `blue` `purple` `cyan` `white`, `bright-*`, or `#rrggbb` | `bin/start`, new shell |
| `POSTGRES_VERSION` | `18` | Postgres major version. Each major keeps its own data folder. | `bin/start` |
| `REDIS_VERSION` | `8` | Redis version | `bin/start` |
| `MYSQL_VERSION` | `8.4` | MySQL version (MySQL override only) | `bin/start` |
| `CLAUDE_CODE_OAUTH_TOKEN` | – | Logs Claude Code in | `bin/start` |
| `GH_TOKEN` | – | Logs `gh` and `git` over HTTPS in to GitHub | `bin/start` |
| `ATLASSIAN_SITE`, `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN` | – | Jira/Confluence REST access; logs `acli` in | `bin/start` |

Leave unused tokens commented out: an empty value is still passed to the container.

### Getting the tokens

All tokens are optional. Without them, log in by hand inside the box.

**Claude Code** (needs a Claude subscription). Run `claude setup-token` on any machine with Claude Code, including inside the box, and copy the `sk-ant-oat01-...` token.

**GitHub.** Reuse an existing login with `echo "GH_TOKEN=$(gh auth token)" >> .env`, or create a [classic token](https://github.com/settings/tokens/new) with scopes `repo`, `read:org` and `workflow`. Fine-grained tokens work too, but some `gh` commands need extra permissions.

**Atlassian.** Set `ATLASSIAN_SITE` (`yourcompany.atlassian.net`) and `ATLASSIAN_EMAIL`, then create an [API token](https://id.atlassian.com/manage-profile/security/api-tokens).

## Services

`docker-compose.yml` defines only the dev container. Ports and services live in `docker-compose.override.yml`, which is gitignored and yours to edit; `bin/start` creates it from `docker-compose.override.example.yml`.

| Service | Inside `dev` | From this machine |
|---|---|---|
| Postgres (`postgres` / `postgres`) | `postgres:5432` | `127.0.0.1:5433` |
| Redis | `redis:6379` | – |
| Mailpit | SMTP `mailpit:1025` | http://localhost:8025 |
| Your apps | – | ports 3000–3005, 5173 |

`PGHOST`, `PGUSER`, `PGPASSWORD`, `REDIS_URL`, `SMTP_ADDRESS` and `SMTP_PORT` are set in `dev`, so `rails new myapp --database=postgresql && bin/rails db:create` works with no `database.yml` changes.

**Change services:** edit `docker-compose.override.yml`, then `bin/start`. Removed services' containers are dropped; their volumes are kept.

- **More ports:** add `"127.0.0.1:4000:4000"` under `dev: ports:`. Keep the `127.0.0.1:` prefix.
- **New service:** add it under `services:`, name its container `${BOX_NAME:-rails-devbox}-<service>`, put connection settings under `dev: environment:` and list it in `dev: depends_on:`.
- **MySQL instead of Postgres:**

  ```bash
  cp docker-compose.override.mysql.example.yml docker-compose.override.yml
  bin/start
  ```

  MySQL is at `mysql:3306` (host `127.0.0.1:3307`), user `root`, no password. `DB_HOST=mysql` is set for `rails new --database=mysql` (or `trilogy`). There is no `mysql` CLI in the box; use `docker compose exec mysql mysql`.

## Working with apps

Put apps in `home/apps` (`/home/dev/apps` in the box).

**Dev servers** must listen on all interfaces. `BINDING=0.0.0.0` is set, so Rails needs no flags:

```bash
bin/rails server    # or bin/dev
npx next dev -H 0.0.0.0
npx vite --host
```

**Mail:** point Action Mailer at Mailpit in `config/environments/development.rb`, then open http://localhost:8025.

```ruby
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: ENV.fetch("SMTP_ADDRESS", "localhost"),
  port: ENV.fetch("SMTP_PORT", 1025).to_i
}
```

**Ruby and Node versions.** The image ships Ruby 4.0.7 and Node 24 with bundler, rails, yarn and pnpm. For pinned versions:

```bash
rbenv install    # reads .ruby-version
nvm install      # reads .nvmrc
```

- Installed versions, gems, global npm packages, `rbenv global` and `nvm alias default` persist in the `rbenv-versions` and `nvm-versions` volumes.
- For a Ruby newer than the image knows: `git -C /opt/rbenv/plugins/ruby-build pull`, then `rbenv install`.
- `nvm use` also switches Node for editor extensions until a new shell starts.
- To change image defaults, edit `RUBY_VERSION` / `NODE_VERSION` in the Dockerfile. Existing volumes keep old contents; to reset them (deletes versions you installed):

  ```bash
  docker compose down
  docker volume rm rails-devbox_rbenv-versions rails-devbox_nvm-versions
  bin/start --build
  ```

## Tools

### Shell

zsh with [Starship](https://starship.rs), autosuggestions, syntax highlighting and fzf (Ctrl-R history, Ctrl-T files, Alt-C directories). bash also works: `docker compose exec dev bash`.

- Shared config: `zshrc` in this repo, installed as `/etc/zsh/zshrc`.
- Personal config: `home/.zshrc`, loaded last. History: `home/.zsh_history`.
- Custom prompt: create `home/.config/starship.toml`. It replaces the default, so copy the `[env_var.BOX_NAME]` block from `devbox/starship.toml` to keep the badge.

### Claude Code

Installed into `home/.local/bin` on first start (up to 5 minutes; progress in `docker compose logs dev`). Log in once with `claude`, or set `CLAUDE_CODE_OAUTH_TOKEN`. Login and settings persist in `home/.claude`.

- `cc` is an alias for `claude --dangerously-skip-permissions`.
- The status line (`devbox/statusline`) shows the box badge, model, directory, git branch and context usage. It is only added when `home/.claude/settings.json` has no `statusLine`.
- `claude/CLAUDE.md` holds sample global instructions; copy it to `home/.claude/` to use it.

### Git and SSH

With `GH_TOKEN`, `gh` and HTTPS remotes work immediately. For SSH remotes, create a key inside the box (host keys from this machine are never mounted):

```bash
ssh-keygen -t ed25519 -C "you@example.com"
gh auth login              # choose SSH and upload the key, or paste it at github.com/settings/keys
ssh -T git@github.com
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Keys, git identity and `gh` login live in `home/.ssh`, `home/.gitconfig` and `home/.config/gh`.

### Jira and Confluence

With the `ATLASSIAN_*` variables set, use the REST APIs with Basic auth, or `acli`:

```bash
curl -su "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "https://$ATLASSIAN_SITE/rest/api/3/issue/ABC-123"
curl -su "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" -G "https://$ATLASSIAN_SITE/rest/api/3/search/jql" \
  --data-urlencode "jql=assignee = currentUser() AND statusCategory != Done"
curl -su "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "https://$ATLASSIAN_SITE/wiki/api/v2/pages/12345?body-format=storage"

acli jira workitem view ABC-123
acli jira workitem search --jql "assignee = currentUser()"
```

API docs: [Jira](https://developer.atlassian.com/cloud/jira/platform/rest/v3/), [Confluence](https://developer.atlassian.com/cloud/confluence/rest/v2/). Ask Claude Code to use them the same way, for example "read ABC-123 with the Jira REST API using the ATLASSIAN_* variables".

## Troubleshooting

**Claude shows a login screen despite the token.** Run `bin/start` so the container picks up the token and marks onboarding complete. If `claude auth status` shows `"loggedIn": false`, check the `.env` line is uncommented, or create a new token.

**Container not ready.** `docker compose logs dev` shows the Claude Code install, `acli` login and badge color warnings.

**Files in `home/` owned by the wrong user.** Set `UID`/`GID` in `.env` to `id -u`/`id -g` and run `bin/start --build`.

## Layout

```
├── Dockerfile, entrypoint.sh
├── docker-compose.yml                          dev container
├── docker-compose.override.example.yml         ports + Postgres, Redis, Mailpit
├── docker-compose.override.mysql.example.yml   ports + MySQL, Redis, Mailpit
├── docker-compose.override.yml                 your copy (gitignored)
├── .env.example                                settings template for .env (gitignored)
├── bin/start, bin/stop
├── zshrc                                       shared zsh config
├── devbox/                                     prompt template and Claude Code status line
├── claude/CLAUDE.md                            sample Claude Code instructions
├── .devcontainer/devcontainer.json
├── tests/verify.sh                             smoke test
└── home/                                       /home/dev in the container (gitignored)
    ├── apps/                                   your apps
    ├── .ssh/, .gitconfig, .config/gh/          git credentials
    └── .claude/, .local/bin/claude             Claude Code
```
