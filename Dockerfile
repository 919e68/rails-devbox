FROM ubuntu:24.04

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
ARG RUBY_VERSION=4.0.7
ARG NODE_VERSION=24

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

# Extra apt repositories: GitHub CLI, and PostgreSQL so the client matches the Postgres 18 server
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /etc/apt/keyrings/pgdg.asc \
    && echo "deb [signed-by=/etc/apt/keyrings/pgdg.asc] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && rm -rf /var/lib/apt/lists/*

# Build tools plus the libraries Ruby, common gems (pg, mysql2, sqlite3, psych, image processing) and Node need
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential autoconf bison pkg-config rustc \
      wget git sudo openssh-client \
      vim nano less unzip zip tzdata locales \
      gh ripgrep jq fzf tmux htop redis-tools \
      zsh zsh-autosuggestions zsh-syntax-highlighting \
      libssl-dev libyaml-dev libreadline-dev zlib1g-dev libffi-dev \
      libgdbm-dev libncurses-dev libgmp-dev libdb-dev uuid-dev libjemalloc-dev \
      libpq-dev postgresql-client-18 \
      libsqlite3-dev sqlite3 \
      default-libmysqlclient-dev \
      libvips42 imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships an "ubuntu" user on UID 1000; remove it so our user can match the host UID
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /usr/bin/zsh ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# rbenv and nvm live in /opt because the home directory is bind-mounted from the host.
# PATH entries make ruby/node work in non-interactive processes (editor extensions, compose exec, Claude Code).
ENV RBENV_ROOT=/opt/rbenv \
    NVM_DIR=/opt/nvm \
    NVM_SYMLINK_CURRENT=true \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0
ENV PATH=/home/${USERNAME}/.local/bin:/opt/rbenv/shims:/opt/rbenv/bin:/opt/nvm/current/bin:${PATH}
RUN mkdir -p $RBENV_ROOT $NVM_DIR && chown ${USER_UID}:${USER_GID} $RBENV_ROOT $NVM_DIR

USER ${USERNAME}

# rbenv + ruby-build, then the default Ruby (YJIT needs rustc, jemalloc needs libjemalloc-dev)
RUN git clone --depth 1 https://github.com/rbenv/rbenv.git $RBENV_ROOT \
    && git clone --depth 1 https://github.com/rbenv/ruby-build.git $RBENV_ROOT/plugins/ruby-build
RUN RUBY_CONFIGURE_OPTS="--enable-yjit --with-jemalloc" rbenv install ${RUBY_VERSION} \
    && rbenv global ${RUBY_VERSION} \
    && gem install bundler rails --no-document \
    && rbenv rehash

# nvm (latest release tag), then the default Node with corepack for yarn/pnpm
RUN git clone https://github.com/nvm-sh/nvm.git $NVM_DIR \
    && cd $NVM_DIR \
    && git checkout "$(git describe --abbrev=0 --tags --match 'v[0-9]*' "$(git rev-list --tags --max-count=1)")"
RUN . $NVM_DIR/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm alias default ${NODE_VERSION} \
    && nvm use default \
    && corepack enable

# Global/default version choices live in the volumes (rbenv-versions, nvm-versions) so they survive container recreation
RUN mv $RBENV_ROOT/version $RBENV_ROOT/versions/.global \
    && ln -s versions/.global $RBENV_ROOT/version \
    && mv $NVM_DIR/alias $NVM_DIR/versions/.alias \
    && ln -s versions/.alias $NVM_DIR/alias

USER root

# Interactive shell setup lives system-wide so it works no matter what is in the mounted home
RUN { \
      echo ''; \
      echo '# rbenv'; \
      echo 'eval "$(rbenv init - bash)"'; \
      echo ''; \
      echo '# nvm'; \
      echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'; \
      echo '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"'; \
      echo ''; \
      echo '# Aliases'; \
      echo "alias cc='claude --dangerously-skip-permissions'"; \
    } >> /etc/bash.bashrc

# zsh (the default shell) with the Starship prompt, set up system-wide like bash above.
# ~/.zshrc is seeded from /etc/skel by the entrypoint and is read after this file, so it can override anything here.
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b /usr/local/bin
COPY zshrc /tmp/zshrc
RUN cat /tmp/zshrc >> /etc/zsh/zshrc && rm /tmp/zshrc \
    && printf '%s\n' '# Personal zsh settings. System defaults (history, plugins, rbenv, nvm, Starship) are in /etc/zsh/zshrc.' > /etc/skel/.zshrc

# git over HTTPS to GitHub authenticates through gh, which uses GH_TOKEN from .env or a `gh auth login`.
# System level so it survives any ~/.gitconfig; git falls through to later helpers when gh has no login.
RUN git config --system credential.https://github.com.helper '!/usr/bin/gh auth git-credential'

# Atlassian CLI (acli) for Jira, logged in on start from ATLASSIAN_* in .env (see entrypoint.sh).
# Its own layer so adding it does not rebuild Ruby.
RUN curl -fsSL https://acli.atlassian.com/gpg/public-key.asc | gpg --dearmor -o /etc/apt/keyrings/acli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/acli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/acli-archive-keyring.gpg] https://acli.atlassian.com/linux/deb stable main" > /etc/apt/sources.list.d/acli.list \
    && apt-get update && apt-get install -y --no-install-recommends acli \
    && rm -rf /var/lib/apt/lists/*

# Box name badge (BOX_NAME / BOX_COLOR in .env) for the Starship prompt and the Claude Code status line
COPY devbox/starship.toml /etc/devbox/starship.toml
COPY devbox/statusline /usr/local/bin/devbox-statusline
RUN chmod +x /usr/local/bin/devbox-statusline

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${USERNAME}
WORKDIR /home/${USERNAME}/apps

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
