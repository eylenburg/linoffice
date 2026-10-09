#!/usr/bin/env bash
# LinOffice path authority. Source this file; do not execute it for normal use.
#
# PREFIX     read-only app files (directory that contains linoffice.sh)
# CONFIG_DIR writable compose.yaml, linoffice.conf, and working oem/
# DATA_DIR   writable logs, markers, and registry_override.conf
#
# Resolution (same order as lib/paths.py):
#   PREFIX:
#     1. LINOFFICE_PREFIX if it is a directory containing linoffice.sh
#     2. Walk up from the caller (then from this file) until linoffice.sh is found
#     3. Fail with an error
#   CONFIG_DIR:
#     1. LINOFFICE_CONFIG_DIR if set
#     2. ${XDG_CONFIG_HOME:-$HOME/.config}/linoffice if compose.yaml or linoffice.conf is there
#     3. $PREFIX/config if compose.yaml or linoffice.conf is there (legacy install)
#     4. ${XDG_CONFIG_HOME:-$HOME/.config}/linoffice
#   DATA_DIR:
#     1. LINOFFICE_DATA_DIR if set
#     2. ${XDG_DATA_HOME:-$HOME/.local/share}/linoffice if it looks like LinOffice state
#     3. $HOME/.local/share/linoffice if that directory exists
#     4. ${XDG_DATA_HOME:-$HOME/.local/share}/linoffice
#
# paths.env is a cache written by setup.sh and linoffice.sh. It is not read here.

_LINOFFICE_PATHS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
  _LINOFFICE_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
else
  _LINOFFICE_CALLER_DIR="$_LINOFFICE_PATHS_LIB_DIR"
fi

_linoffice_find_prefix() {
  local start="$1"
  local dir
  dir="$(cd "$start" 2>/dev/null && pwd)" || return 1
  while [[ -n "$dir" ]]; do
    if [[ -f "$dir/linoffice.sh" ]]; then
      (cd "$dir" && pwd -P)
      return 0
    fi
    if [[ "$dir" == "/" ]]; then
      break
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

_linoffice_dir_has_state() {
  local dir="$1"
  [[ -f "$dir/success" || -f "$dir/setup_progress.log" || -f "$dir/linoffice.log" || -f "$dir/sleep_marker" || -f "$dir/installed_dependencies" ]]
}

linoffice_resolve_paths() {
  local user_prefix="${LINOFFICE_PREFIX:-}"
  local user_config="${LINOFFICE_CONFIG_DIR:-}"
  local user_data="${LINOFFICE_DATA_DIR:-}"
  local user_apps="${LINOFFICE_APPLICATIONS_DIR:-}"
  local found=""

  LINOFFICE_PREFIX=""
  if [[ -n "$user_prefix" ]]; then
    if [[ -d "$user_prefix" && -f "$user_prefix/linoffice.sh" ]]; then
      LINOFFICE_PREFIX="$(cd "$user_prefix" && pwd -P)"
    else
      echo "LinOffice: ignoring LINOFFICE_PREFIX='$user_prefix' (not a directory containing linoffice.sh)." >&2
    fi
  fi
  if [[ -z "$LINOFFICE_PREFIX" ]]; then
    found="$(_linoffice_find_prefix "$_LINOFFICE_CALLER_DIR" || true)"
    if [[ -z "$found" ]]; then
      found="$(_linoffice_find_prefix "$_LINOFFICE_PATHS_LIB_DIR" || true)"
    fi
    if [[ -z "$found" ]]; then
      echo "LinOffice: could not find LINOFFICE_PREFIX (no linoffice.sh in the caller directory or its parents)." >&2
      echo "Set LINOFFICE_PREFIX to the directory that contains linoffice.sh." >&2
      return 1
    fi
    LINOFFICE_PREFIX="$found"
  fi

  local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}/linoffice"
  LEGACY_CONFIG_DIR="$LINOFFICE_PREFIX/config"
  if [[ -n "$user_config" ]]; then
    LINOFFICE_CONFIG_DIR="$(realpath -m "$user_config")"
  elif [[ -f "$xdg_config/compose.yaml" || -f "$xdg_config/linoffice.conf" ]]; then
    LINOFFICE_CONFIG_DIR="$(realpath -m "$xdg_config")"
  elif [[ -f "$LEGACY_CONFIG_DIR/compose.yaml" || -f "$LEGACY_CONFIG_DIR/linoffice.conf" ]]; then
    LINOFFICE_CONFIG_DIR="$(realpath -m "$LEGACY_CONFIG_DIR")"
  else
    LINOFFICE_CONFIG_DIR="$(realpath -m "$xdg_config")"
  fi

  local xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}/linoffice"
  LEGACY_DATA_DIR="$(realpath -m "$HOME/.local/share/linoffice")"
  if [[ -n "$user_data" ]]; then
    LINOFFICE_DATA_DIR="$(realpath -m "$user_data")"
  elif [[ -d "$xdg_data" ]] && _linoffice_dir_has_state "$xdg_data"; then
    LINOFFICE_DATA_DIR="$(realpath -m "$xdg_data")"
  elif [[ -d "$HOME/.local/share/linoffice" ]]; then
    LINOFFICE_DATA_DIR="$LEGACY_DATA_DIR"
  else
    LINOFFICE_DATA_DIR="$(realpath -m "$xdg_data")"
  fi

  if [[ -n "$user_apps" ]]; then
    LINOFFICE_APPLICATIONS_DIR="$(realpath -m "$user_apps")"
  else
    LINOFFICE_APPLICATIONS_DIR="$(realpath -m "${XDG_DATA_HOME:-$HOME/.local/share}/applications")"
  fi

  LINOFFICE_COMPOSE_FILE="$LINOFFICE_CONFIG_DIR/compose.yaml"
  LINOFFICE_CONF_FILE="$LINOFFICE_CONFIG_DIR/linoffice.conf"
  LINOFFICE_OEM_DIR="$LINOFFICE_CONFIG_DIR/oem"
  LINOFFICE_OEM_TEMPLATES_DIR="$LINOFFICE_PREFIX/config/oem"
  LINOFFICE_COMPOSE_DEFAULT="$LINOFFICE_PREFIX/config/compose.yaml.default"
  LINOFFICE_CONF_DEFAULT="$LINOFFICE_PREFIX/config/linoffice.conf.default"
  LINOFFICE_LANGUAGES_CSV="$LINOFFICE_PREFIX/config/languages.csv"
  LINOFFICE_SCRIPT="$LINOFFICE_PREFIX/linoffice.sh"
  LINOFFICE_SETUP_SCRIPT="$LINOFFICE_PREFIX/setup.sh"
  LINOFFICE_UNINSTALL_SCRIPT="$LINOFFICE_PREFIX/uninstall.sh"
  LINOFFICE_VENV_DIR="$LINOFFICE_PREFIX/venv"
  LINOFFICE_LEGACY_VENV_DIR="$HOME/.local/bin/linoffice/venv"

  export LINOFFICE_PREFIX LINOFFICE_CONFIG_DIR LINOFFICE_DATA_DIR LINOFFICE_APPLICATIONS_DIR
  export LINOFFICE_COMPOSE_FILE LINOFFICE_CONF_FILE LINOFFICE_OEM_DIR LINOFFICE_OEM_TEMPLATES_DIR
  export LINOFFICE_COMPOSE_DEFAULT LINOFFICE_CONF_DEFAULT LINOFFICE_LANGUAGES_CSV
  export LINOFFICE_SCRIPT LINOFFICE_SETUP_SCRIPT LINOFFICE_UNINSTALL_SCRIPT
  export LINOFFICE_VENV_DIR LINOFFICE_LEGACY_VENV_DIR
  export LEGACY_DATA_DIR LEGACY_CONFIG_DIR
  return 0
}

linoffice_ensure_dirs() {
  mkdir -p "$LINOFFICE_CONFIG_DIR/oem/registry" "$LINOFFICE_DATA_DIR/instances"
}

# Rewrite the oem bind to ./oem when a compose file was just created from the template.
_linoffice_normalize_oem_volume() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if grep -qE '^[[:space:]]*-[[:space:]]+\./oem:/oem' "$file"; then
    return 0
  fi
  if grep -qE '^[[:space:]]*-[[:space:]].*:/oem' "$file"; then
    sed -i -E 's|^[[:space:]]*-[[:space:]].*:/oem.*|      - ./oem:/oem:Z|' "$file"
  fi
}

linoffice_sync_oem_templates() {
  local src="$LINOFFICE_OEM_TEMPLATES_DIR"
  local dst="$LINOFFICE_OEM_DIR"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst" || return 1
  local src_real dst_real
  src_real="$(cd "$src" && pwd -P)"
  dst_real="$(cd "$dst" && pwd -P)"
  # Legacy installs use PREFIX/config as CONFIG_DIR. Source and destination are the same tree.
  if [[ "$src_real" == "$dst_real" ]]; then
    return 0
  fi
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$src_real"/}"
    if [[ -e "$dst_real/$rel" ]]; then
      continue
    fi
    mkdir -p "$(dirname "$dst_real/$rel")" || return 1
    cp -a "$f" "$dst_real/$rel" || return 1
  done < <(find "$src_real" -type f -print0)
}

# Copy templates into CONFIG_DIR. Never overwrites an existing compose.yaml or linoffice.conf.
# Sets LINOFFICE_SEEDED_COMPOSE / LINOFFICE_SEEDED_CONF to 1 when that file was created.
linoffice_seed_config() {
  LINOFFICE_SEEDED_COMPOSE=0
  LINOFFICE_SEEDED_CONF=0
  linoffice_ensure_dirs || return 1
  if [[ ! -f "$LINOFFICE_COMPOSE_FILE" ]]; then
    if [[ ! -f "$LINOFFICE_COMPOSE_DEFAULT" ]]; then
      echo "LinOffice: missing compose template: $LINOFFICE_COMPOSE_DEFAULT" >&2
      return 1
    fi
    cp "$LINOFFICE_COMPOSE_DEFAULT" "$LINOFFICE_COMPOSE_FILE" || return 1
    _linoffice_normalize_oem_volume "$LINOFFICE_COMPOSE_FILE"
    LINOFFICE_SEEDED_COMPOSE=1
  fi
  if [[ ! -f "$LINOFFICE_CONF_FILE" ]]; then
    if [[ ! -f "$LINOFFICE_CONF_DEFAULT" ]]; then
      echo "LinOffice: missing config template: $LINOFFICE_CONF_DEFAULT" >&2
      return 1
    fi
    cp "$LINOFFICE_CONF_DEFAULT" "$LINOFFICE_CONF_FILE" || return 1
    LINOFFICE_SEEDED_CONF=1
  fi
  linoffice_sync_oem_templates || return 1
  return 0
}

# Write or touch RELATIVE under DATA_DIR, then copy it to ~/.local/share/linoffice when that path differs.
# Usage: linoffice_legacy_data_fallback_write RELATIVE [--touch|--copy|TEXT]
linoffice_legacy_data_fallback_write() {
  local rel="$1"
  local content="${2:---touch}"
  local primary="$LINOFFICE_DATA_DIR/$rel"
  local legacy="$LEGACY_DATA_DIR/$rel"
  mkdir -p "$(dirname "$primary")" || return 1
  case "$content" in
    --touch)
      touch "$primary" || return 1
      ;;
    --copy)
      [[ -e "$primary" ]] || return 0
      ;;
    *)
      printf '%s\n' "$content" > "$primary" || return 1
      ;;
  esac
  if [[ "$(realpath -m "$primary")" == "$(realpath -m "$legacy")" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$legacy")" || return 0
  cp -f "$primary" "$legacy" 2>/dev/null || true
}

linoffice_success_exists() {
  [[ -f "$LINOFFICE_DATA_DIR/success" || -f "$LEGACY_DATA_DIR/success" ]]
}

linoffice_clear_success() {
  rm -f "$LINOFFICE_DATA_DIR/success" "$LEGACY_DATA_DIR/success"
}

linoffice_read_data_path() {
  local rel="$1"
  if [[ -e "$LINOFFICE_DATA_DIR/$rel" ]]; then
    printf '%s\n' "$LINOFFICE_DATA_DIR/$rel"
  elif [[ -e "$LEGACY_DATA_DIR/$rel" ]]; then
    printf '%s\n' "$LEGACY_DATA_DIR/$rel"
  else
    printf '%s\n' "$LINOFFICE_DATA_DIR/$rel"
  fi
}

# Preferred venv is $PREFIX/venv. Legacy quickstart venv is the fallback.
linoffice_find_venv() {
  if [[ -f "$LINOFFICE_VENV_DIR/bin/activate" ]]; then
    printf '%s\n' "$LINOFFICE_VENV_DIR"
    return 0
  fi
  if [[ -f "$LINOFFICE_LEGACY_VENV_DIR/bin/activate" ]]; then
    printf '%s\n' "$LINOFFICE_LEGACY_VENV_DIR"
    return 0
  fi
  printf '%s\n' "$LINOFFICE_VENV_DIR"
  return 1
}

linoffice_is_system_prefix() {
  local prefix
  prefix="$(realpath -m "${1:-$LINOFFICE_PREFIX}")"
  case "$prefix" in
    /usr|/usr/*|/app|/app/*|/nix/store|/nix/store/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Run podman-compose against the resolved compose file.
# Project name stays "linoffice" so the existing linoffice_data volume is reused.
# podman-compose resolves ./oem from the compose file's directory. cd is extra safety.
# This podman-compose build has -p/--file and no --project-directory flag.
linoffice_compose() {
  if [[ -z "${COMPOSE_COMMAND:-}" ]]; then
    echo "LinOffice: COMPOSE_COMMAND is not set" >&2
    return 1
  fi
  if [[ ! -d "$LINOFFICE_CONFIG_DIR" ]]; then
    echo "LinOffice: config directory does not exist: $LINOFFICE_CONFIG_DIR" >&2
    return 1
  fi
  if [[ ! -f "$LINOFFICE_COMPOSE_FILE" ]]; then
    echo "LinOffice: compose file does not exist: $LINOFFICE_COMPOSE_FILE" >&2
    return 1
  fi
  (
    cd "$LINOFFICE_CONFIG_DIR" || exit 1
    export COMPOSE_PROJECT_NAME=linoffice
    export COMPOSE_PROJECT_DIR="$LINOFFICE_CONFIG_DIR"
    # shellcheck disable=SC2086
    $COMPOSE_COMMAND -p linoffice --file "$LINOFFICE_COMPOSE_FILE" "$@"
  )
}

linoffice_write_paths_env() {
  mkdir -p "$LINOFFICE_DATA_DIR" || return 1
  local tmp
  tmp="$(mktemp "$LINOFFICE_DATA_DIR/.paths.env.XXXXXX")" || return 1
  {
    printf 'LINOFFICE_PREFIX=%q\n' "$LINOFFICE_PREFIX"
    printf 'LINOFFICE_CONFIG_DIR=%q\n' "$LINOFFICE_CONFIG_DIR"
    printf 'LINOFFICE_DATA_DIR=%q\n' "$LINOFFICE_DATA_DIR"
  } > "$tmp"
  mv -f "$tmp" "$LINOFFICE_DATA_DIR/paths.env"
}

linoffice_resolve_paths || return 1 2>/dev/null || exit 1

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'LINOFFICE_PREFIX=%q\n' "$LINOFFICE_PREFIX"
  printf 'LINOFFICE_CONFIG_DIR=%q\n' "$LINOFFICE_CONFIG_DIR"
  printf 'LINOFFICE_DATA_DIR=%q\n' "$LINOFFICE_DATA_DIR"
fi
