#!/usr/bin/env bash
# Smoke test for the rails-devbox stack. Run from anywhere after `docker compose up -d`.
# Usage: tests/verify.sh [--skip-rails]
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
check() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then echo "PASS  $name"; return 0; else echo "FAIL  $name"; fail=1; return 1; fi
}
# Non-interactive shell on purpose: tools must work without .bashrc
in_dev() { docker compose exec -T dev bash -c "$1"; }

echo "== runtimes"
check "ruby 4.0.7 with YJIT"        in_dev 'ruby --yjit -v | grep -q "ruby 4.0.7.*+YJIT"'
check "ruby linked with jemalloc"   in_dev 'ruby -e "exit RbConfig::CONFIG[%q(MAINLIBS)].include?(%q(jemalloc))"'
check "rails gem installed"         in_dev 'rails -v'
check "node 24"                     in_dev 'node -v | grep -q "^v24\."'
check "yarn via corepack"           in_dev 'cd /tmp && yarn -v'
check "pnpm via corepack"           in_dev 'cd /tmp && pnpm -v'
check "nvm function in interactive shell" docker compose exec -T dev bash -ic 'nvm --version'
check "zsh is the login shell"      in_dev '[ "$(getent passwd dev | cut -d: -f7)" = /usr/bin/zsh ]'
check "starship installed"          in_dev 'starship --version'
check "zsh loads starship"          docker compose exec -T dev zsh -ic '[ -n "$STARSHIP_SHELL" ]'
check "zsh loads rbenv and nvm"     docker compose exec -T dev zsh -ic 'rbenv version && nvm --version'
check "prompt shows box name"       docker compose exec -T dev zsh -ic 'starship prompt | grep -qF -- " $BOX_NAME "'
check "claude status line set"      in_dev 'jq -e ".statusLine.command == \"/usr/local/bin/devbox-statusline\"" ~/.claude/settings.json'
check "status line shows box name"  in_dev 'echo "{}" | devbox-statusline | grep -qF -- " $BOX_NAME "'
check "zsh loads plugins"           docker compose exec -T dev zsh -ic '(( $+functions[_zsh_autosuggest_start] )) && (( $+functions[_zsh_highlight] ))'
check "zsh defines cc alias"        docker compose exec -T dev zsh -ic '[[ $(alias cc) == *dangerously-skip-permissions* ]]'
check "bash defines cc alias"       docker compose exec -T dev bash -ic 'alias cc | grep -q dangerously-skip-permissions'
check "gh cli"                      in_dev 'gh --version'
check "git uses gh for github https" in_dev 'git config --get-urlmatch credential.helper https://github.com | grep -q "gh auth git-credential"'
check "acli installed"               in_dev 'acli --version'
check "pg_dump is version 18"       in_dev 'pg_dump --version | grep -q " 18\."'
check "BINDING set for bin/dev"     in_dev '[ "$BINDING" = 0.0.0.0 ]'
check "dev uid/gid match host user" bash -c '[ "$(docker compose exec -T dev id -u):$(docker compose exec -T dev id -g)" = "$(id -u):$(id -g)" ]'
# Token checks run only when .env sets the token
if grep -q "^CLAUDE_CODE_OAUTH_TOKEN=." .env 2>/dev/null; then
  check "claude token passed to dev"  in_dev '[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]'
  # Without this flag claude shows its theme picker and login screen even though the token works
  check "claude first-run setup skipped" in_dev 'jq -e ".hasCompletedOnboarding == true" ~/.claude.json'
  # `claude auth status` reports logged in even with a bad token, so make one tiny request
  check "claude token accepted"       in_dev 'timeout 60 claude -p "Reply with OK"'
fi
if grep -q "^GH_TOKEN=." .env 2>/dev/null; then
  check "gh logged in with GH_TOKEN"  in_dev 'gh auth status'
fi
if grep -q "^ATLASSIAN_API_TOKEN=." .env 2>/dev/null; then
  check "acli logged in to jira"      in_dev 'acli jira auth status'
  check "jira api accepts token"      in_dev 'curl -fs -o /dev/null -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "https://$ATLASSIAN_SITE/rest/api/3/myself"'
  check "confluence api accepts token" in_dev 'curl -fs -o /dev/null -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "https://$ATLASSIAN_SITE/wiki/rest/api/user/current"'
fi

echo "== services"
check "postgres reachable"          in_dev 'pg_isready'
pg_want=$(docker compose config --images | sed -n 's/^postgres://p'); pg_want=${pg_want%%[.-]*}
check "postgres server is $pg_want"  in_dev "psql -tAc 'show server_version' | grep -q '^$pg_want\\.'"
check "redis ping"                  in_dev 'redis-cli -u "$REDIS_URL" ping | grep -q PONG'
check "mailpit ui from dev"         in_dev 'curl -fs http://mailpit:8025 -o /dev/null'
check "mailpit ui from host"        curl -fs http://127.0.0.1:8025 -o /dev/null
check "postgres on host 5433"       bash -c 'docker compose port postgres 5432 | grep -q "^127.0.0.1:5433$"'
check "dev ports bound to 127.0.0.1 only" bash -c 'out=$(docker compose port dev 3000) && [ -n "$out" ] && ! grep -qv "^127.0.0.1:" <<<"$out"'

echo "== home"
check "home dotfiles seeded"        test -f home/.bashrc
check "zshrc seeded"                test -f home/.zshrc
check ".ssh is 700"                 bash -c '[ "$(stat -c %a home/.ssh)" = 700 ]'
# Proves the host key is trusted; "Permission denied" just means the key is not on GitHub yet
check "github host key trusted"     in_dev 'ssh -o BatchMode=yes -T git@github.com 2>&1 | grep -qE "successfully authenticated|Permission denied \(publickey\)"'
check "claude cli runs"             in_dev 'claude --version'
# The installer makes a symlink to a /home/dev path, which only resolves inside the container
check "claude binary in host home"  bash -c '[ -L home/.local/bin/claude ] || [ -e home/.local/bin/claude ]'

echo "== devcontainer"
check "devcontainer.json is valid"  jq -e '.service == "dev"' .devcontainer/devcontainer.json

if [ "${1:-}" != "--skip-rails" ]; then
  echo "== rails app end to end"
  # Cleanup function for rails test
  cleanup() {
    in_dev 'f=/tmp/smoke/tmp/pids/server.pid; if [ -f $f ]; then kill $(cat $f); for i in $(seq 20); do [ -f $f ] || break; sleep 0.5; done; fi; cd /tmp/smoke 2>/dev/null && bin/rails db:drop; rm -rf /tmp/smoke' >/dev/null 2>&1
  }
  trap cleanup EXIT INT TERM

  # Fail if port 3000 is already in use
  if curl -fs http://localhost:3000/ -o /dev/null 2>&1; then
    echo "FAIL  port 3000 free before rails test"
    fail=1
  else
    # Create new rails app and chain subsequent steps on success
    if check "rails new app" in_dev 'rm -rf /tmp/smoke && cd /tmp && rails new smoke --database=postgresql --minimal --skip-git -q'; then
      if check "rails db:create" in_dev 'cd /tmp/smoke && bin/rails db:create'; then
        docker compose exec -d dev bash -c 'cd /tmp/smoke && bin/rails server -b 0.0.0.0 -p 3000'
        check "rails answers on host :3000" bash -c 'for i in $(seq 60); do curl -fs http://localhost:3000/ -o /dev/null && exit 0; sleep 1; done; exit 1'
      fi
    fi
  fi
fi

echo
if [ $fail -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit $fail
