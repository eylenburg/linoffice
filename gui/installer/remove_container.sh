#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE=""
CONFIG_DIR=""
if [[ -f "$SCRIPT_DIR/../../lib/paths.sh" ]]; then
  # shellcheck source=../../lib/paths.sh
  if source "$SCRIPT_DIR/../../lib/paths.sh"; then
    COMPOSE_FILE="${LINOFFICE_COMPOSE_FILE:-}"
    CONFIG_DIR="${LINOFFICE_CONFIG_DIR:-}"
  else
    echo "Warning: could not resolve LinOffice paths. Removing the container by name."
  fi
fi

_linoffice_path_is_protected() {
  local real
  real="$(realpath -m "$1" 2>/dev/null || printf '%s' "$1")"
  case "$real" in
    /|/usr|/usr/*|/app|/app/*|/nix/store|/nix/store/*)
      return 0
      ;;
  esac
  return 1
}

# After the container and volume are gone, drop generated setup files so the
# next run is seeded again. Templates under the install prefix are kept.
linoffice_remove_generated_setup() {
  local config="${LINOFFICE_CONFIG_DIR:-}"
  local removed=0
  local data_dir marker rotated oem_real tmpl_real
  local -a data_dirs=()

  if [[ -n "$config" ]]; then
    if _linoffice_path_is_protected "$config"; then
      echo "Leaving configuration in place because it is inside a read-only location: $config"
    else
      if [[ -f "$config/compose.yaml" ]]; then
        rm -f "$config/compose.yaml"
        echo "Removed $config/compose.yaml"
        removed=1
      fi
      if [[ -f "$config/linoffice.conf" ]]; then
        rm -f "$config/linoffice.conf"
        echo "Removed $config/linoffice.conf"
        removed=1
      fi
      if [[ -d "$config/oem" && -d "${LINOFFICE_OEM_TEMPLATES_DIR:-}" ]]; then
        oem_real="$(cd "$config/oem" && pwd -P)"
        tmpl_real="$(cd "$LINOFFICE_OEM_TEMPLATES_DIR" && pwd -P)"
        if [[ "$oem_real" != "$tmpl_real" ]]; then
          rm -rf "$config/oem"
          echo "Removed working OEM files at $config/oem"
          removed=1
        fi
      fi
    fi
  fi

  [[ -n "${LINOFFICE_DATA_DIR:-}" ]] && data_dirs+=("$LINOFFICE_DATA_DIR")
  if [[ -n "${LEGACY_DATA_DIR:-}" && "${LEGACY_DATA_DIR}" != "${LINOFFICE_DATA_DIR:-}" ]]; then
    data_dirs+=("$LEGACY_DATA_DIR")
  fi
  for data_dir in "${data_dirs[@]}"; do
    [[ -d "$data_dir" ]] || continue
    if _linoffice_path_is_protected "$data_dir"; then
      echo "Leaving data in place because it is inside a read-only location: $data_dir"
      continue
    fi
    for marker in setup_progress.log success sleep_marker windows_install.log paths.env setup_output.log; do
      if [[ -e "$data_dir/$marker" ]]; then
        rm -f "$data_dir/$marker"
        echo "Removed $data_dir/$marker"
        removed=1
      fi
    done
    for rotated in "$data_dir"/windows_install_*.log; do
      [[ -f "$rotated" ]] || continue
      rm -f "$rotated"
      echo "Removed $rotated"
      removed=1
    done
  done

  if [[ "$removed" -eq 0 ]]; then
    echo "No generated setup files were found to remove."
  else
    echo "Generated setup files were removed. The next setup starts from scratch."
  fi
}

echo -e "This will delete the LinOffice container and the Windows virtual machine (volume linoffice_data).\nIt will also remove generated setup files such as compose.yaml, linoffice.conf, and the setup progress, so the next setup starts from scratch.\nThe LinOffice program itself is not removed."

read -p "Are you sure you want to proceed? (y/N): " response
response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

if [[ "$response" == "y" || "$response" == "yes" ]]; then
    echo "Deleting LinOffice container and data..."
    if [[ -n "$COMPOSE_FILE" && -f "$COMPOSE_FILE" ]]; then
        (cd "$CONFIG_DIR" && podman-compose -p linoffice --file "$COMPOSE_FILE" down) >/dev/null 2>&1 || true
    fi
    # Podman runs on the host. /app is not a host path, so leave the installer directory.
    cd "${HOME:-/}"
    # Name and volume stay LinOffice / linoffice_data so an existing VM is the one removed.
    # A missing container or volume counts as success.
    podman rm -f LinOffice >/dev/null 2>&1 || true
    podman volume rm linoffice_data >/dev/null 2>&1 || true
    if podman inspect LinOffice >/dev/null 2>&1; then
        echo "Error: Failed to delete LinOffice container."
        exit 1
    fi
    if podman volume inspect linoffice_data >/dev/null 2>&1; then
        echo "Error: Failed to delete LinOffice data volume."
        exit 1
    fi
    echo "Successfully deleted LinOffice container and data."
    linoffice_remove_generated_setup
else
    echo "Operation aborted by user."
    exit 0
fi
