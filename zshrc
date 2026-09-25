
# ---- rails-devbox additions ----

# History
HISTFILE=${HISTFILE:-$HOME/.zsh_history}
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

setopt AUTO_CD INTERACTIVE_COMMENTS
bindkey -e

# rbenv
eval "$(rbenv init - zsh)"

# nvm
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# fzf: Ctrl-R history, Ctrl-T files, Alt-C cd
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && . /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ] && . /usr/share/doc/fzf/examples/completion.zsh

# Plugins (syntax highlighting must be sourced last)
[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && . /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && . /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Aliases
alias cc='claude --dangerously-skip-permissions'

# Reminder until the user has created an SSH key for this box
if [[ -z $(print -r -- $HOME/.ssh/id_*(N[1])) ]]; then
  echo "No SSH key yet. Create one with: ssh-keygen -t ed25519 -C \"you@example.com\"  (see README, Git and SSH)"
fi

# Prompt: the box name badge from .env (see /etc/devbox/starship.toml), unless you have your own starship.toml
if [[ -z $STARSHIP_CONFIG && ! -f ~/.config/starship.toml && -f /tmp/devbox-starship.toml ]]; then
  export STARSHIP_CONFIG=/tmp/devbox-starship.toml
fi
eval "$(starship init zsh)"
