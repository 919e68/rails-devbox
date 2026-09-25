# rails-devbox

Docker development environment for Rails and React/Next.js apps.

## First-time setup

Do these steps once on each machine, before the first start. The tokens are optional: without them you log in by hand inside the box (see [Claude Code](#claude-code), [Git and SSH](#git-and-ssh) and [Jira and Confluence](#jira-and-confluence)).

### 1. Create `.env`

```bash
cp .env.example .env
```

Docker Compose reads `.env` from this folder, including when VS Code starts the box. It is gitignored and never sent to the Docker build. Anyone who can run `docker inspect` on this machine can read the tokens in it, so keep it as private as a password file.

### 2. Set your user and group IDs

```bash
id -u   # your UID
id -g   # your GID
```

Put both numbers in `.env` as `UID=` and `GID=`. If both are 1000, the defaults already match. The container user gets these IDs, so files it writes into `home/` are owned by you.

### 3. Name the box (optional)

The box name is shown as a colored badge at the start of the shell prompt and in the Claude Code status line, so you can tell boxes apart. Set it and the badge color in `.env`:

```bash
BOX_NAME=gna-dev
BOX_COLOR=purple
```

`BOX_COLOR` takes a color name (`black`, `red`, `green`, `yellow`, `blue`, `purple`, `cyan`, `white`, or a `bright-` version such as `bright-red`) or a hex color such as `#d7005f`. The defaults are `rails-devbox` and `blue`. An invalid color falls back to blue with a warning in `docker compose logs dev`.

### 4. Claude Code token (optional)

With this token, `claude` is logged in when the box starts. It needs a Claude subscription. On a machine where Claude Code is installed, run:

```bash
claude setup-token
```

It takes you through logging in to your Claude account in the browser, then prints a token that starts with `sk-ant-oat01-`. Add it to `.env`:

```bash
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
```

If Claude Code is not installed on this machine, skip this step for now. After the first start, run `claude setup-token` inside the box, add the token to `.env` and run `docker compose up -d`.

If `claude` still shows a login screen after you set the token, see [Login screen shows even though the token is set](#login-screen-shows-even-though-the-token-is-set).

### 5. GitHub token (optional)

With this token, `gh` and `git` over HTTPS (`https://github.com/...` remotes) are logged in when the box starts. SSH remotes (`git@github.com:...`) still need an SSH key, see [Git and SSH](#git-and-ssh).

If `gh` is logged in on this machine, reuse that login:

```bash
echo "GH_TOKEN=$(gh auth token)" >> .env
```

Otherwise create a classic personal access token:

1. Open https://github.com/settings/tokens/new.
2. Give it a name such as `rails-devbox` and pick an expiration.
3. Tick the scopes `repo`, `read:org` and `workflow`.
4. Click "Generate token" and copy it. It starts with `ghp_` and is shown only once.

Add it to `.env`:

```bash
GH_TOKEN=ghp_...
```

A fine-grained token (https://github.com/settings/personal-access-tokens/new) also works if you want to limit access to chosen repositories, but some `gh` commands need extra permissions with it.

### 6. Jira and Confluence access (optional)

With these values, scripts and Claude Code in the box can call the Jira and Confluence REST APIs, and the `acli` command line is logged in to Jira when the box starts. Add your site and Atlassian account email to `.env`:

```bash
ATLASSIAN_SITE=yourcompany.atlassian.net
ATLASSIAN_EMAIL=you@example.com
```

Then create an API token:

1. Open https://id.atlassian.com/manage-profile/security/api-tokens.
2. Click "Create API token", give it a name such as `rails-devbox` and pick an expiration.
3. Copy the token. It is shown only once.

Add it to `.env`:

```bash
ATLASSIAN_API_TOKEN=ATATT...
```

### 7. Start the box

In VS Code or Cursor: open this folder and run "Dev Containers: Reopen in Container". The editor starts all four services and opens `/home/dev/apps`.

From a terminal:

```bash
docker compose up -d
docker compose exec dev zsh
```

The first start builds the image, which compiles Ruby and takes about 10 to 20 minutes, then installs Claude Code.

### 8. Check it

```bash
tests/verify.sh --skip-rails
```

The token checks run only for tokens set in `.env`. See [Checking the setup](#checking-the-setup) for the full run.

## Settings

All settings go in `.env`. `.env.example` lists them with comments.

| Variable | Required | What it does | How to get it | After changing it |
|---|---|---|---|---|
| `UID` | yes, unless yours is 1000 | User ID of the container user, so files in `home/` are owned by you. Default 1000. | `id -u` | `docker compose up -d --build` |
| `GID` | yes, unless yours is 1000 | Group ID of the container user. Default 1000. | `id -g` | `docker compose up -d --build` |
| `BOX_NAME` | no | Name in the prompt badge and the Claude Code status line. Default `rails-devbox`. | [Step 3](#3-name-the-box-optional) | `docker compose up -d`, then a new shell |
| `BOX_COLOR` | no | Badge background: a color name or `#rrggbb`. Default `blue`. | [Step 3](#3-name-the-box-optional) | `docker compose up -d`, then a new shell |
| `CLAUDE_CODE_OAUTH_TOKEN` | no | Logs Claude Code in when the box starts. | [Step 4](#4-claude-code-token-optional) | `docker compose up -d` |
| `GH_TOKEN` | no | Logs `gh` and `git` over HTTPS in to GitHub when the box starts. | [Step 5](#5-github-token-optional) | `docker compose up -d` |
| `ATLASSIAN_SITE` | no | Your Atlassian site, such as `yourcompany.atlassian.net`. | [Step 6](#6-jira-and-confluence-access-optional) | `docker compose up -d` |
| `ATLASSIAN_EMAIL` | no | Email of your Atlassian account. | [Step 6](#6-jira-and-confluence-access-optional) | `docker compose up -d` |
| `ATLASSIAN_API_TOKEN` | no | API token for the Jira and Confluence REST APIs. Also logs `acli` in to Jira. | [Step 6](#6-jira-and-confluence-access-optional) | `docker compose up -d` |

Leave a token commented out in `.env` when you have none. An empty value is still passed to the container.

## Layout

```
rails-devbox/
├── Dockerfile, entrypoint.sh, docker-compose.yml
├── .env.example           settings template; copy to .env (gitignored)
├── zshrc                  shared zsh setup, copied into the image
├── devbox/                prompt template and Claude Code status line for the box name badge
├── .devcontainer/devcontainer.json
├── tests/verify.sh        smoke test for the running stack
└── home/                  mounted as /home/dev in the container
    ├── apps/              your Rails / React / Next.js apps
    ├── .ssh/              SSH keys
    ├── .claude/           Claude Code settings and login
    └── .local/bin/claude  Claude Code (installed on first start; a symlink into .local/share/claude)
```

Everything under `home/` stays on this machine. Rebuilding or removing the container does not touch it.

## Shell

The default shell is zsh with the [Starship](https://starship.rs) prompt, autosuggestions, syntax highlighting and fzf key bindings (Ctrl-R history, Ctrl-T files, Alt-C directories). VS Code and Cursor terminals open zsh.

The shared setup lives in `/etc/zsh/zshrc` inside the image (source: `zshrc` in this repo). Your own settings go in `home/.zshrc`, which is created on first start and read after the shared file, so it can override anything. History is saved to `home/.zsh_history`.

The prompt starts with the box name badge from `BOX_NAME` and `BOX_COLOR` ([step 3](#3-name-the-box-optional)). Each start of the box writes the prompt config to `/tmp/devbox-starship.toml` from the template in `devbox/starship.toml`. To customize the prompt, create `home/.config/starship.toml`; it replaces the default, so copy the `[env_var.BOX_NAME]` block from `devbox/starship.toml` into it (with a fixed color) to keep the badge.

bash still works (`docker compose exec dev bash`) with rbenv and nvm set up.

## Services

| Service | From inside `dev` | From this machine |
|---|---|---|
| Postgres (`POSTGRES_VERSION`, default 18) | `postgres:5432` | `127.0.0.1:5433` |
| Redis (`REDIS_VERSION`, default 8) | `redis:6379` | not published |
| Mailpit | SMTP `mailpit:1025`, web `http://mailpit:8025` | `http://localhost:8025` |
| Your apps | - | ports 3000-3005 and 5173 |

Postgres login is `postgres` / `postgres`. The `dev` container sets `PGHOST`, `PGUSER`, `PGPASSWORD`, `REDIS_URL`, `SMTP_ADDRESS` and `SMTP_PORT`, so a new app created with `rails new myapp --database=postgresql` runs `bin/rails db:create` with no changes to `database.yml`.

All published ports listen on 127.0.0.1 only.

## Running dev servers

The container sets `BINDING=0.0.0.0`, which `bin/rails server` and `bin/dev` read, so they are reachable from the host with no flags. Vite does not read `BINDING`, so it still needs `--host`. Bind servers to all interfaces inside the container, otherwise the host cannot reach them:

```bash
bin/rails server
bin/dev
npx next dev -H 0.0.0.0
npx vite --host
```

## Sending mail to Mailpit from Rails

Add to `config/environments/development.rb`:

```ruby
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: ENV.fetch("SMTP_ADDRESS", "localhost"),
  port: ENV.fetch("SMTP_PORT", 1025).to_i
}
```

Sent mail shows up at http://localhost:8025.

## Ruby and Node versions

The image ships Ruby 4.0.7 (YJIT and jemalloc) and Node 24 as defaults, with bundler, rails, yarn and pnpm.

For an app that pins a version in `.ruby-version` or `.nvmrc`:

```bash
rbenv install      # reads .ruby-version
nvm install        # reads .nvmrc
```

Installed versions, gems and global npm packages are kept in the `rbenv-versions` and `nvm-versions` Docker volumes, so they survive rebuilds. The `rbenv global` and `nvm alias default` choices are stored in those same volumes, so they also survive rebuilds and container recreation.

To install a Ruby version newer than what's in the image, update the `ruby-build` definitions first: `git -C /opt/rbenv/plugins/ruby-build pull` before `rbenv install`. That pull itself resets on rebuild (it lives outside the volumes), but any Ruby you install with it stays in the volume.

`nvm use` in one shell also switches node for editor extensions and other non-interactive processes, since they pick up the `current` symlink it updates. A new shell returns to the default.

To change the image defaults, edit `RUBY_VERSION` / `NODE_VERSION` in the Dockerfile and rebuild. Existing volumes keep their old contents, so either install the new version by hand as above, or recreate the volumes (this deletes versions and gems you installed yourself):

```bash
docker compose down
docker volume rm rails-devbox_rbenv-versions rails-devbox_nvm-versions
docker compose up -d --build
```

## Claude Code

The container installs Claude Code into `home/.local/bin` on first start. The container is not ready until that install finishes, which can take a few minutes on a slow connection (it gives up after 5 minutes and retries on the next start); `docker compose logs dev` shows progress. Run `claude` inside the container and log in once. The login and settings are saved in `home/.claude`.

To skip that login, set `CLAUDE_CODE_OAUTH_TOKEN` in `.env` ([step 4 of the setup](#4-claude-code-token-optional)). The container then starts with `claude` logged in.

### Login screen shows even though the token is set

Claude Code shows its first-run setup, a theme picker and then "choose a login method", until `home/.claude.json` contains `"hasCompletedOnboarding": true`. The token alone does not set that value, so when `CLAUDE_CODE_OAUTH_TOKEN` is set the container adds it on start. If you added the token while the box was running, run `docker compose up -d` so the container picks up both.

If the login screen still shows, check the token by running this inside the box:

```bash
claude auth status
```

If it shows `"loggedIn": false`, the container does not have the token. Check that the `CLAUDE_CODE_OAUTH_TOKEN` line in `.env` is not commented out, then run `docker compose up -d`. A token that has expired or been revoked also fails; create a new one with `claude setup-token`.

The box sets Claude Code's status line to `/usr/local/bin/devbox-statusline` (source: `devbox/statusline`). It shows the same box name badge as the prompt, then the model, the directory, the git branch and how much of the context window is used. It is added to `home/.claude/settings.json` on start only when no status line is set, so your own `statusLine` setting is kept.

Both zsh and bash define `cc` as a shortcut for `claude --dangerously-skip-permissions`, which runs Claude Code without asking for permission before each tool call.

## Jira and Confluence

With the `ATLASSIAN_*` settings from [step 6](#6-jira-and-confluence-access-optional), the values are in the container environment. The REST APIs take them as Basic auth, so `curl`, your scripts and Claude Code can use them directly:

```bash
# Jira: your account, one issue, a JQL search
curl -su "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "https://$ATLASSIAN_SITE/rest/api/3/myself"
curl -su "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "https://$ATLASSIAN_SITE/rest/api/3/issue/ABC-123"
curl -su "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" -G "https://$ATLASSIAN_SITE/rest/api/3/search/jql" \
  --data-urlencode "jql=assignee = currentUser() AND statusCategory != Done" --data-urlencode "fields=summary,status"

# Confluence: a page by ID
curl -su "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "https://$ATLASSIAN_SITE/wiki/api/v2/pages/12345?body-format=storage"
```

API reference: [Jira](https://developer.atlassian.com/cloud/jira/platform/rest/v3/) and [Confluence](https://developer.atlassian.com/cloud/confluence/rest/v2/). To have Claude Code use Jira, ask it to, for example "read ABC-123 with the Jira REST API using the ATLASSIAN_* variables".

Each start of the box also logs `acli` in to Jira with the same values. A failed login prints a warning in `docker compose logs dev` and the box starts anyway.

```bash
acli jira workitem view ABC-123
acli jira workitem search --jql "assignee = currentUser()"
```

## Git and SSH

With `GH_TOKEN` set in `.env` ([step 5 of the setup](#5-github-token-optional)), `gh` and `git` over HTTPS work from the first start: `gh repo clone owner/repo` or `git clone https://github.com/owner/repo.git`. For SSH remotes, set up a key as below.

Each user sets up their own SSH key inside the box. Keys from this machine's `~/.ssh` are never mounted or used. GitHub's host key is already trusted, so the first clone does not prompt. Until a key exists, new zsh shells print a reminder.

Inside the container, create a key and add it to GitHub:

```bash
ssh-keygen -t ed25519 -C "you@example.com"
gh auth login        # choose SSH, then upload ~/.ssh/id_ed25519.pub when asked
ssh -T git@github.com
```

Or skip `gh` and paste the output of `cat ~/.ssh/id_ed25519.pub` into https://github.com/settings/keys.

Then set your identity:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

The key lives in `home/.ssh`, the git identity in `home/.gitconfig` and the `gh` login in `home/.config/gh`. All three stay on this machine across rebuilds and are excluded from git and the Docker build.

## Checking the setup

```bash
tests/verify.sh              # full check, including a throwaway Rails app
tests/verify.sh --skip-rails # faster
```
