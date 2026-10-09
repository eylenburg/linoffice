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

echo -e "This script will now delete the LinOffice podman container and all its data (i.e., the Windows virtual machine), using this command:\n 'podman rm -f LinOffice && podman volume rm linoffice_data'"

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
else
    echo "Operation aborted by user."
    exit 0
fi
