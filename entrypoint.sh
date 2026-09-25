#!/bin/bash
set -e

# Docker creates bind-mount dirs as root:root when the host side is empty/missing;
# fix ownership non-recursively (never recursive: apps may be large) so dev can write.
for d in "$HOME" "$HOME/apps"; do
  mkdir -p "$d" 2>/dev/null || sudo mkdir -p "$d"
  [ -O "$d" ] || sudo chown "$(id -u):$(id -g)" "$d"
done

# Seed the mounted home with default dotfiles on first run
for f in .bashrc .profile .bash_logout .zshrc; do
  [ -e "$HOME/$f" ] || cp "/etc/skel/$f" "$HOME/$f"
done

# SSH keys are the user's own, created inside the box (see README); host keys are never mounted
mkdir -p "$HOME/.ssh"

# Trust GitHub's published host key (https://api.github.com/meta) so the first clone does not prompt
if ! ssh-keygen -F github.com -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1; then
  echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" >> "$HOME/.ssh/known_hosts"
fi

# ssh refuses keys with loose permissions
chmod 700 "$HOME/.ssh"
find "$HOME/.ssh" -type f ! -name '*.pub' ! -name 'known_hosts*' ! -name 'config' -exec chmod 600 {} +

# Claude Code installs into the mounted home so the binary, updates and login persist on the host
if [ ! -e "$HOME/.local/bin/claude" ]; then
  echo "Installing Claude Code..."
  installer=$(mktemp)
  if curl -fsSL --connect-timeout 20 --max-time 300 https://claude.ai/install.sh -o "$installer" && bash "$installer"; then :; else
    echo "WARNING: Claude Code install failed; it will be retried on next container start." >&2
  fi
  rm -f "$installer"
fi

# Prompt badge: fill BOX_COLOR into the Starship template (zshrc uses it unless ~/.config/starship.toml exists)
color=${BOX_COLOR:-blue}
if ! [[ $color =~ ^(bright-)?(black|red|green|yellow|blue|purple|cyan|white)$ || $color =~ ^#[0-9a-fA-F]{6}$ ]]; then
  echo "WARNING: BOX_COLOR '$color' is not a color name or #rrggbb; using blue" >&2
  color=blue
fi
sed "s/@BOX_COLOR@/$color/" /etc/devbox/starship.toml > /tmp/devbox-starship.toml

# Claude Code status line with the same badge, unless the user already set one
settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -s "$settings" ] || echo '{}' > "$settings"
if ! jq -e '.statusLine' "$settings" >/dev/null 2>&1; then
  tmp=$(mktemp)
  if jq '.statusLine = {"type": "command", "command": "/usr/local/bin/devbox-statusline"}' "$settings" > "$tmp"; then
    cat "$tmp" > "$settings"
  else
    echo "WARNING: could not add the status line to $settings" >&2
  fi
  rm -f "$tmp"
fi

# With a token from .env, skip Claude Code's first-run setup: it shows a theme picker and a login screen
# until ~/.claude.json has hasCompletedOnboarding, even though the token already logs claude in
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  state="$HOME/.claude.json"
  [ -s "$state" ] || echo '{}' > "$state"
  if ! jq -e '.hasCompletedOnboarding == true' "$state" >/dev/null 2>&1; then
    tmp=$(mktemp)
    if jq '.hasCompletedOnboarding = true' "$state" > "$tmp"; then
      cat "$tmp" > "$state"
    else
      echo "WARNING: could not mark Claude Code setup as done in $state" >&2
    fi
    rm -f "$tmp"
  fi
fi

# Atlassian access from .env: log acli in to Jira. A failure only warns, so a bad token never stops the box from starting.
if [ -n "${ATLASSIAN_SITE:-}" ] && [ -n "${ATLASSIAN_EMAIL:-}" ] && [ -n "${ATLASSIAN_API_TOKEN:-}" ]; then
  if ! printf '%s' "$ATLASSIAN_API_TOKEN" | acli jira auth login --site "$ATLASSIAN_SITE" --email "$ATLASSIAN_EMAIL" --token >/dev/null 2>&1; then
    echo "WARNING: acli could not log in to $ATLASSIAN_SITE; check ATLASSIAN_* in .env" >&2
  fi
fi

# Shims and the nvm "current" symlink live outside the volumes; rebuild them from what the volumes hold
rbenv rehash || true
if ! { . "$NVM_DIR/nvm.sh" --no-use && nvm use --silent default >/dev/null; }; then
  echo "WARNING: nvm default version is not installed; run 'nvm install'" >&2
fi

exec "$@"
