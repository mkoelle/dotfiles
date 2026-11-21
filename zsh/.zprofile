# ~/.zprofile
# Loads for login shells only, after ~/.zshenv and before ~/.zshrc.
# Put once-per-session setup here: Homebrew shellenv, runtime managers.
# No prompts, aliases, or keybindings (those go in ~/.zshrc).

# Homebrew environment (expensive → login shell only)
eval "$(/opt/homebrew/bin/brew shellenv)"

# Initialize mise (unified runtime manager)
eval "$("$HOME/.local/bin/mise" activate zsh)"
