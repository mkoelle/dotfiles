#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s [--dry-run] [--no-git] [--no-personal-git] [--no-vscode] [--no-rtk] [--help]\n' "$(basename "$0")"
}

DRY_RUN=false
NO_GIT=false
NO_PERSONAL_GIT=false
NO_VSCODE=false
NO_RTK=false

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --no-git) NO_GIT=true ;;
    --no-personal-git) NO_PERSONAL_GIT=true ;;
    --no-vscode) NO_VSCODE=true ;;
    --no-rtk) NO_RTK=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

run_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$DRY_RUN" == false ]]; then
    "$@"
  fi
}

confirm() {
  local prompt=$1
  local response

  if [[ "$DRY_RUN" == true ]]; then
    printf '+ prompt: %s [Y/n] (dry run: continuing)\n' "$prompt"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    return 0
  fi

  while true; do
    if ! read -r -p "$prompt [Y/n] " response; then
      printf '\nNo response received; skipping.\n'
      return 1
    fi
    case "$response" in
      ""|[yY]|[yY][eE][sS]) return 0 ;;
      [nN]|[nN][oO]) return 1 ;;
      *) printf 'Please answer yes or no.\n' ;;
    esac
  done
}

write_file() {
  local destination=$1
  local content=$2

  printf '+ create %q\n' "$destination"
  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    printf 'Refusing to overwrite existing file: %s\n' "$destination" >&2
    return 1
  fi

  if ! (umask 077; printf '%s\n' "$content" >"$destination"); then
    printf 'Could not create file: %s\n' "$destination" >&2
    return 1
  fi
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GIT_LOCAL_CONFIG="$HOME/.gitconfig.local"
GIT_IGNORE_GLOBAL="$HOME/.gitignore_global"
GIT_PERSONAL_CONFIG="$HOME/.gitconfig.personal"

if [[ "$NO_GIT" == false ]]; then
  if [[ -e "$GIT_LOCAL_CONFIG" || -L "$GIT_LOCAL_CONFIG" ]]; then
    printf 'Git identity already exists at %s; leaving it unchanged.\n' "$GIT_LOCAL_CONFIG"
  elif confirm "Configure your default Git name and email in $GIT_LOCAL_CONFIG?"; then
    if [[ "$DRY_RUN" == true ]]; then
      printf '+ prompt for Git name and email, then create %q\n' "$GIT_LOCAL_CONFIG"
    elif [[ ! -t 0 ]]; then
      printf 'Cannot configure Git identity without an interactive terminal.\n' >&2
      exit 1
    else
      read -r -p "Git user name: " git_name
      read -r -p "Git user email: " git_email
      if [[ -z "$git_name" || -z "$git_email" ]]; then
        printf 'Git name and email are required.\n' >&2
        exit 1
      fi
      write_file "$GIT_LOCAL_CONFIG" "[user]
  name = $git_name
  email = $git_email"
    fi
  else
    printf 'Skipping default Git identity setup.\n'
  fi

  if [[ -e "$GIT_IGNORE_GLOBAL" || -L "$GIT_IGNORE_GLOBAL" ]]; then
    printf 'Global Git ignore file already exists at %s; leaving it unchanged.\n' "$GIT_IGNORE_GLOBAL"
  elif confirm "Create global Git ignore rules in $GIT_IGNORE_GLOBAL?"; then
    write_file "$GIT_IGNORE_GLOBAL" '# Operating system
.DS_Store

# Editors
.idea/
.vscode/'
  else
    printf 'Skipping global Git ignore setup.\n'
  fi
fi

if [[ "$NO_PERSONAL_GIT" == true ]]; then
  printf 'Skipping personal GitHub settings (--no-personal-git).\n'
elif [[ -e "$GIT_PERSONAL_CONFIG" || -L "$GIT_PERSONAL_CONFIG" ]]; then
  printf 'Personal GitHub settings already exist at %s; leaving them unchanged.\n' "$GIT_PERSONAL_CONFIG"
elif [[ "$DRY_RUN" == false && ! -t 0 ]]; then
  printf 'Skipping optional personal GitHub settings; no interactive terminal is available.\n'
elif confirm "Set up personal GitHub email and SSH key in $GIT_PERSONAL_CONFIG?"; then
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ prompt for personal Git email and SSH key, then create %q\n' "$GIT_PERSONAL_CONFIG"
  else
    read -r -p "Personal Git email: " personal_email
    read -r -p "Personal Git SSH key [$HOME/.ssh/personal_github]: " personal_ssh_key
    personal_ssh_key=${personal_ssh_key:-"$HOME/.ssh/personal_github"}
    if [[ -z "$personal_email" ]]; then
      printf 'Personal Git email is required.\n' >&2
      exit 1
    fi
    printf -v ssh_command 'ssh -i %q' "$personal_ssh_key"
    write_file "$GIT_PERSONAL_CONFIG" "[user]
  email = $personal_email
[core]
  sshCommand = $ssh_command"
  fi
fi

if [[ "$NO_VSCODE" == false ]]; then
  if ! command -v code >/dev/null 2>&1; then
    printf 'VS Code CLI not found. Install VS Code or pass --no-vscode.\n' >&2
    exit 1
  fi

  vscode_user_dir="$HOME/Library/Application Support/Code/User"
  run_cmd mkdir -p "$vscode_user_dir"
  run_cmd ln -sf "$REPO_ROOT/vscode/settings.json" "$vscode_user_dir/settings.json"
  run_cmd ln -sf "$REPO_ROOT/vscode/extensions.json" "$vscode_user_dir/extensions.json"

  while IFS= read -r extension; do
    run_cmd code --install-extension "$extension"
  done < <(sed -E 's/[[:space:]]*\/\/.*$//' "$REPO_ROOT/vscode/extensions.json" |
    sed -nE 's/^[[:space:]]*"([^"]+)"[[:space:]]*,?[[:space:]]*$/\1/p')
fi

if [[ "$NO_RTK" == false ]]; then
  if ! command -v rtk >/dev/null 2>&1; then
    printf 'RTK is not installed. Run scripts/mac_bootstrap.sh or pass --no-rtk.\n' >&2
    exit 1
  fi

  rtk_args=(init -g --agent claude)
  if [[ "$DRY_RUN" == true ]]; then
    rtk_args+=(--dry-run)
    printf '+'
    printf ' %q' rtk "${rtk_args[@]}"
    printf '\n'
    rtk "${rtk_args[@]}"
  else
    run_cmd rtk "${rtk_args[@]}"
  fi
fi

printf 'macOS post-setup complete.\n'
