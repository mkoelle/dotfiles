#!/usr/bin/env bash
#
# Bootstrap a macOS workstation from this dotfiles repository.
#
# Responsibilities:
#   - Install Homebrew when missing
#   - Load Homebrew into the current shell
#   - Install packages from brew/BrewFile
#   - Symlink dotfiles through GNU Stow
#   - Symlink repository scripts into ~/.local/bin
#   - Set Homebrew zsh as the default shell
#
# Usage:
#   ./scripts/mac_bootstrap.sh
#   ./scripts/mac_bootstrap.sh --dry-run
#   ./scripts/mac_bootstrap.sh --help
#
# The script is intended to be safe to run repeatedly.

set -euo pipefail


# -----------------------------------------------------------------------------
# Repository paths
# -----------------------------------------------------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly BREWFILE="${REPO_ROOT}/brew/BrewFile"
readonly BIN_DIR="${REPO_ROOT}/bin"
readonly LOCAL_BIN_DIR="${HOME}/.local/bin"

readonly HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"


# -----------------------------------------------------------------------------
# Runtime configuration
# -----------------------------------------------------------------------------

DRY_RUN=false
BREW_BIN=""


# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------

log_info() {
  printf 'ℹ️  %s\n' "$*"
}


log_success() {
  printf '✅ %s\n' "$*"
}


log_warning() {
  printf '⚠️  %s\n' "$*" >&2
}


log_error() {
  printf '❌ %s\n' "$*" >&2
}


print_command() {
  printf '+'

  printf ' %q' "$@"

  printf '\n'
}


# Print and run a command.
#
# In dry-run mode, print command without executing it.
run_cmd() {
  print_command "$@"

  if [[ "$DRY_RUN" == false ]]; then
    "$@"
  fi
}


# -----------------------------------------------------------------------------
# Command-line interface
# -----------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  --dry-run    Print planned commands without making changes
  -h, --help   Show this help

Repository:
  ${REPO_ROOT}
EOF
}


parse_arguments() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        ;;

      -h|--help)
        usage
        exit 0
        ;;

      *)
        log_error "Unknown option: $1"
        printf '\n' >&2
        usage >&2
        exit 2
        ;;
    esac

    shift
  done
}


# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    log_error "This bootstrap script supports macOS only."
    exit 1
  fi
}


validate_repository() {
  if [[ ! -f "$BREWFILE" ]]; then
    log_error "Brewfile not found: $BREWFILE"
    exit 1
  fi

  if [[ ! -d "$BIN_DIR" ]]; then
    log_warning "Local bin source directory not found: $BIN_DIR"
  fi
}


# -----------------------------------------------------------------------------
# Homebrew
# -----------------------------------------------------------------------------

# Locate Homebrew across supported macOS installation paths.
find_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    printf '%s\n' "/opt/homebrew/bin/brew"
    return 0
  fi

  if [[ -x /usr/local/bin/brew ]]; then
    printf '%s\n' "/usr/local/bin/brew"
    return 0
  fi

  return 1
}


install_homebrew() {
  if BREW_BIN="$(find_homebrew)"; then
    log_info "Homebrew already installed: $BREW_BIN"
    return
  fi

  log_info "Installing Homebrew..."

  if [[ "$DRY_RUN" == true ]]; then
    printf '+ /bin/bash Homebrew installer from %s\n' \
      "$HOMEBREW_INSTALL_URL"
    return
  fi

  /bin/bash -c "$(
    curl \
      --fail \
      --silent \
      --show-error \
      --location \
      "$HOMEBREW_INSTALL_URL"
  )"

  if ! BREW_BIN="$(find_homebrew)"; then
    log_error "Homebrew installation completed, but brew was not found."
    exit 1
  fi
}


# Load Homebrew paths and environment variables into this process.
load_homebrew_environment() {
  # A dry run on a machine without Homebrew cannot load shellenv.
  if [[ -z "$BREW_BIN" ]]; then
    if BREW_BIN="$(find_homebrew)"; then
      :
    elif [[ "$DRY_RUN" == true ]]; then
      log_info "Homebrew environment would be loaded after installation."
      return
    else
      log_error "Homebrew executable not found."
      exit 1
    fi
  fi

  eval "$("$BREW_BIN" shellenv)"

  log_info "Homebrew loaded: $(command -v brew)"
}


install_brewfile_packages() {
  log_info "Installing packages from: $BREWFILE"

  if command -v brew >/dev/null 2>&1; then
    run_cmd brew bundle --file="$BREWFILE"
  elif [[ "$DRY_RUN" == true ]]; then
    print_command brew bundle --file="$BREWFILE"
  else
    log_error "Cannot install Brewfile packages because brew is unavailable."
    exit 1
  fi
}


# -----------------------------------------------------------------------------
# Dotfiles
# -----------------------------------------------------------------------------

stow_dotfiles() {
  local package

  if ! command -v stow >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == true ]]; then
      log_info "Stow would be available after Brewfile installation."
    else
      log_warning "GNU Stow not installed. Skipping dotfile symlinks."
      log_info "Install with: brew install stow"
    fi

    return
  fi

  log_info "Symlinking dotfiles with GNU Stow..."

  for package in zsh git mise; do
    if [[ ! -d "${REPO_ROOT}/${package}" ]]; then
      log_warning "Stow package not found: ${REPO_ROOT}/${package}"
      continue
    fi

    run_cmd stow \
      --dir="$REPO_ROOT" \
      --target="$HOME" \
      --restow \
      --verbose \
      "$package"
  done
}


symlink_vscode_settings() {
  local vscode_user_dir="${HOME}/Library/Application Support/Code/User"

  log_info "Symlinking VS Code settings..."

  run_cmd mkdir -p "$vscode_user_dir"
  run_cmd ln -sf "${REPO_ROOT}/vscode/settings.json" \
    "${vscode_user_dir}/settings.json"
  run_cmd ln -sf "${REPO_ROOT}/vscode/extensions.json" \
    "${vscode_user_dir}/extensions.json"
}


symlink_local_bin() {
  local source
  local destination

  if [[ ! -d "$BIN_DIR" ]]; then
    log_info "No local bin directory found. Skipping: $BIN_DIR"
    return
  fi

  log_info "Symlinking local commands into: $LOCAL_BIN_DIR"

  run_cmd mkdir -p "$LOCAL_BIN_DIR"

  for source in "$BIN_DIR"/*; do
    [[ -e "$source" || -L "$source" ]] || continue

    destination="${LOCAL_BIN_DIR}/$(basename "$source")"

    run_cmd ln -sfn "$source" "$destination"
  done
}


# -----------------------------------------------------------------------------
# Default shell
# -----------------------------------------------------------------------------

add_shell_to_etc_shells() {
  local shell_path="$1"

  if grep -Fxq "$shell_path" /etc/shells; then
    return
  fi

  log_info "Adding Homebrew zsh to /etc/shells..."

  if [[ "$DRY_RUN" == true ]]; then
    printf '+ printf %q\\\\n | sudo tee -a /etc/shells\n' "$shell_path"
  else
    printf '%s\n' "$shell_path" |
      sudo tee -a /etc/shells >/dev/null
  fi
}


set_default_shell() {
  local zsh_path

  if ! command -v brew >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == true ]]; then
      log_info "Default shell would be configured after Homebrew installation."
    else
      log_warning "Homebrew unavailable. Leaving default shell unchanged."
    fi

    return
  fi

  zsh_path="$(brew --prefix)/bin/zsh"

  if [[ ! -x "$zsh_path" ]]; then
    log_warning "Homebrew zsh not found: $zsh_path"
    log_info "Ensure 'zsh' exists in: $BREWFILE"
    return
  fi

  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    log_info "Default shell already set: $zsh_path"
    return
  fi

  add_shell_to_etc_shells "$zsh_path"

  log_info "Setting default shell to: $zsh_path"
  run_cmd chsh -s "$zsh_path"
}


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  parse_arguments "$@"
  require_macos
  validate_repository

  printf '🚀 Starting macOS bootstrap...\n'
  log_info "Repository: $REPO_ROOT"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry run enabled. No changes will be made."
  fi

  install_homebrew
  load_homebrew_environment
  install_brewfile_packages
  stow_dotfiles
  symlink_vscode_settings
  symlink_local_bin
  set_default_shell

  printf '\n'
  log_success "macOS bootstrap complete."
}


main "$@"
