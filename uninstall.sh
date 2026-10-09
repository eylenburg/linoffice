#!/bin/bash
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEGACY_PREFIX="$HOME/.local/bin/linoffice"
if [[ -f "$SCRIPT_DIR/lib/paths.sh" ]]; then
  # shellcheck source=lib/paths.sh
  source "$SCRIPT_DIR/lib/paths.sh" || exit 1
else
  echo "Warning: lib/paths.sh not found next to uninstall.sh. Using legacy path discovery."
  LINOFFICE_PREFIX="$SCRIPT_DIR"
  LEGACY_DATA_DIR="$HOME/.local/share/linoffice"
  LINOFFICE_DATA_DIR="$LEGACY_DATA_DIR"
  if [[ -f "$LEGACY_DATA_DIR/paths.env" ]]; then
    # shellcheck disable=SC1090
    source "$LEGACY_DATA_DIR/paths.env"
  fi
  LINOFFICE_CONFIG_DIR="${LINOFFICE_CONFIG_DIR:-$LINOFFICE_PREFIX/config}"
  LINOFFICE_COMPOSE_FILE="${LINOFFICE_CONFIG_DIR}/compose.yaml"
  LINOFFICE_APPLICATIONS_DIR="${LINOFFICE_APPLICATIONS_DIR:-$HOME/.local/share/applications}"
  LINOFFICE_VENV_DIR="$LINOFFICE_PREFIX/venv"
  LINOFFICE_LEGACY_VENV_DIR="$LEGACY_PREFIX/venv"
  linoffice_is_system_prefix() { return 1; }
  linoffice_compose() {
    (cd "$LINOFFICE_CONFIG_DIR" && $COMPOSE_COMMAND -p linoffice --file "$LINOFFICE_COMPOSE_FILE" "$@")
  }
fi

# If resolution could not see a compose file, paths.env may still name the config directory.
if [[ ! -f "$LINOFFICE_COMPOSE_FILE" ]]; then
  for _envfile in "$LINOFFICE_DATA_DIR/paths.env" "${LEGACY_DATA_DIR:-}/paths.env"; do
    [[ -f "$_envfile" ]] || continue
    _cached_config="$(bash -c 'source "$1"; printf "%s" "$LINOFFICE_CONFIG_DIR"' bash "$_envfile" 2>/dev/null || true)"
    if [[ -n "$_cached_config" && -f "$_cached_config/compose.yaml" ]]; then
      LINOFFICE_CONFIG_DIR="$_cached_config"
      LINOFFICE_COMPOSE_FILE="$_cached_config/compose.yaml"
      break
    fi
  done
  unset _envfile _cached_config
fi

COMPOSE_PATH="$LINOFFICE_COMPOSE_FILE"
APPDATA_PATH="$LINOFFICE_DATA_DIR"
USER_APPLICATIONS_DIR="$LINOFFICE_APPLICATIONS_DIR"
CONTAINER_NAME="LinOffice"
echo "Executing uninstall script in $SCRIPT_DIR"
echo "Config: $LINOFFICE_CONFIG_DIR"
echo "Data: $LINOFFICE_DATA_DIR"


# Check if sudo is available
check_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# Function to show manual uninstall instructions
show_manual_uninstall() {
  local packages=("$@")
  echo -e "\033[1;31mIt seems that sudo is not available on your system. The script cannot remove these packages:\033[0m"
  echo -e "\033[1;31m${packages[*]}\033[0m"
  echo -e "\033[1;31mPlease uninstall them manually.\033[0m"
  echo ""
  echo "Please run as root (su) and remove the packages manually."
}

print_system_pkg_manual_commands() {
  local pm_key="$1"
  shift
  local packages=("$@")

  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  echo ""
  echo "System package cleanup is disabled by default for safety."
  echo "Selected packages (review carefully): ${packages[*]}"
  echo "Suggested manual command (non-recursive):"
  case "$pm_key" in
    apt)
      echo "  sudo apt-get remove ${packages[*]}"
      ;;
    dnf)
      echo "  sudo dnf remove ${packages[*]}"
      ;;
    yum)
      echo "  sudo yum remove ${packages[*]}"
      ;;
    zypper)
      echo "  sudo zypper remove ${packages[*]}"
      ;;
    pacman)
      echo "  sudo pacman -R ${packages[*]}"
      ;;
    xbps-install)
      echo "  sudo xbps-remove ${packages[*]}"
      ;;
    eopkg)
      echo "  sudo eopkg remove ${packages[*]}"
      ;;
    urpmi)
      echo "  sudo urpme ${packages[*]}"
      ;;
    *)
      echo "  Unknown package manager: $pm_key"
      ;;
  esac
  echo "Tip: run a dry-run first where supported (for apt: sudo apt-get -s remove ...)."
}

# Find .desktop files containing linoffice.sh in Exec= line.
# Scan the resolved applications directory and the legacy ~/.local/share/applications path.
DESKTOP_SCAN_DIRS=()
for _desktop_dir in "$USER_APPLICATIONS_DIR" "${XDG_DATA_HOME:-$HOME/.local/share}/applications" "$HOME/.local/share/applications"; do
  [[ -d "$_desktop_dir" ]] || continue
  _desktop_real="$(cd "$_desktop_dir" && pwd -P)"
  _already=0
  for _seen in "${DESKTOP_SCAN_DIRS[@]}"; do
    if [[ "$_seen" == "$_desktop_real" ]]; then
      _already=1
      break
    fi
  done
  if [[ "$_already" -eq 0 ]]; then
    DESKTOP_SCAN_DIRS+=("$_desktop_real")
  fi
done
unset _desktop_dir _desktop_real _already _seen

if [[ ${#DESKTOP_SCAN_DIRS[@]} -gt 0 ]]; then
  DESKTOP_FILES=""
  for _desktop_dir in "${DESKTOP_SCAN_DIRS[@]}"; do
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      DESKTOP_FILES="${DESKTOP_FILES:+$DESKTOP_FILES
}$file"
    done < <(find "$_desktop_dir" -type f -name "*.desktop" -exec grep -l "Exec=.*linoffice.sh" {} \; 2>/dev/null)
    if [[ -f "$_desktop_dir/linoffice.desktop" && "$DESKTOP_FILES" != *"$_desktop_dir/linoffice.desktop"* ]]; then
      DESKTOP_FILES="${DESKTOP_FILES:+$DESKTOP_FILES
}$_desktop_dir/linoffice.desktop"
    fi
  done
  unset _desktop_dir
  if [[ -n "$DESKTOP_FILES" ]]; then
    echo "The following .desktop files will be deleted:"
    echo "$DESKTOP_FILES"
    read -p "Do you want to proceed with deletion? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      while IFS= read -r file; do
        rm -f "$file" && echo "Deleted: $file"
      done <<< "$DESKTOP_FILES"
    else
      echo "Deletion of .desktop files aborted."
    fi
  else
    echo "No .desktop files containing linoffice.sh found."
  fi
fi

# Dependency cleanup based on installed_dependencies recorded by quickstart.sh
# This will attempt to remove venv, pip-installed packages, Flatpak apps, and
# system packages installed by the quickstart script, with confirmations.

# Resolve the installed_dependencies file path (data dir, then legacy ~/.local/share/linoffice)
INSTALLED_DEPS_FILE=""
DEFAULT_APPDATA_PATH="$LEGACY_DATA_DIR"
if [[ -n "$APPDATA_PATH" && -f "$APPDATA_PATH/installed_dependencies" ]]; then
  INSTALLED_DEPS_FILE="$APPDATA_PATH/installed_dependencies"
elif [[ -f "$DEFAULT_APPDATA_PATH/installed_dependencies" ]]; then
  INSTALLED_DEPS_FILE="$DEFAULT_APPDATA_PATH/installed_dependencies"
fi

if [[ -n "$INSTALLED_DEPS_FILE" ]]; then
  echo "Checking which packages were installed by the LinOffice Quickstart script..."

  # Extract key values
  PM_LINE=$(grep -E '^(apt|dnf|yum|zypper|pacman|xbps-install|eopkg|urpmi)=' "$INSTALLED_DEPS_FILE" || true)
  FLATPAK_LINE=$(grep -E '^flatpak=' "$INSTALLED_DEPS_FILE" | sed -E 's/^flatpak=//; s/^"//; s/"$//' || true)
  PIP_LINE=$(grep -E '^pip=' "$INSTALLED_DEPS_FILE" | sed -E 's/^pip=//; s/^"//; s/"$//' || true)
  FLATPAK_USER=$(grep -E '^flatpak_user=' "$INSTALLED_DEPS_FILE" | tail -n1 | cut -d= -f2 2>/dev/null || echo 0)
  PIP_VENV=$(grep -E '^pip_venv=' "$INSTALLED_DEPS_FILE" | tail -n1 | cut -d= -f2 2>/dev/null || echo 0)

  # Offer exporting recorded system dependency package list to a file in home dir
  if [[ -n "$PM_LINE" ]]; then
    PM_KEY=${PM_LINE%%=*}
    PM_PKGS_RAW=$(echo "$PM_LINE" | sed -E 's/^[^=]+=//; s/^"//; s/"$//')
    if [[ -n "$PM_PKGS_RAW" ]]; then
      read -p "Do you want to export a list of packages that were installed by the LinOffice Quickstart script to a text file in your home directory? This will allow you to uninstall them manually if you wish to. (y/n): " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        OUTPUT_FILE="$HOME/linoffice-installed-dependencies-$(date +%Y%m%d-%H%M%S).txt"
        {
          echo "Generated: $(date -Is)"
          echo ""
          for pkg in $PM_PKGS_RAW; do
            echo "$pkg"
          done
        } > "$OUTPUT_FILE"
        echo "Saved list of installed dependencies to: $OUTPUT_FILE"
      else
        echo "Skipping."
      fi
    fi
  fi

  # Uninstall pip packages installed by quickstart (user-site packages)
  if [[ -n "$PIP_LINE" ]]; then
    echo "The following Python packages were installed by the LinOffice Quickstart script:"
    echo "$PIP_LINE"
    echo "They will be uninstalled using pip. Other applications might depend on them."
    read -p "Proceed to uninstall these pip packages? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      # Prefer pip3 if available
      if command -v pip3 >/dev/null 2>&1; then
        pip3 uninstall --break-system-packages -y $PIP_LINE || true
      elif command -v pip >/dev/null 2>&1; then
        pip uninstall --break-system-packages -y $PIP_LINE || true
      else
        echo "Warning: pip is not available; cannot uninstall pip packages."
      fi
    else
      echo "pip package uninstallation skipped."
    fi
  fi

  # Uninstall Flatpak apps (e.g., FreeRDP) and their unused dependencies
  if [[ -n "$FLATPAK_LINE" ]]; then
    if command -v flatpak >/dev/null 2>&1; then
      echo "The following Flatpak packages were installed by the LinOffice Quickstart script:"
      echo "$FLATPAK_LINE"
      USER_FLAG=""
      if [[ "$FLATPAK_USER" == "1" ]]; then
        USER_FLAG="--user"
      fi
      read -p "Proceed to uninstall these Flatpak packages ($USER_FLAG)? (y/n): " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for ref in $FLATPAK_LINE; do
          flatpak uninstall -y $USER_FLAG "$ref" || true
        done
        # Also remove unused runtimes pulled in as dependencies
        flatpak uninstall -y $USER_FLAG --unused || true
      else
        echo "Flatpak uninstallation skipped."
      fi
    else
      echo "Warning: flatpak command not found; skipping Flatpak cleanup."
    fi
  fi

  # Remove system packages installed by quickstart via the detected package manager
  if [[ -n "$PM_LINE" ]]; then
    PM_KEY=${PM_LINE%%=*}
    PM_PKGS_RAW=$(echo "$PM_LINE" | sed -E 's/^[^=]+=//; s/^"//; s/"$//')

    if [[ -n "$PM_PKGS_RAW" ]]; then
      echo "The following system packages were installed by the LinOffice Quickstart script:"
      echo "$PM_PKGS_RAW"
      echo "Removing them may affect other applications that depend on them."

      # Ask per-package confirmation, accumulate selections
      SELECTED_PKGS=()
      for pkg in $PM_PKGS_RAW; do
        read -p "Remove system package '$pkg'? (y/n): " ans
        if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
          SELECTED_PKGS+=("$pkg")
        fi
      done

      if [[ ${#SELECTED_PKGS[@]} -gt 0 ]]; then
        echo ""
        echo "WARNING: Automatic system package removal is disabled to prevent accidental desktop/system breakage."
        echo "No system packages were removed."
        if ! check_sudo; then
          show_manual_uninstall "${SELECTED_PKGS[@]}"
        fi
        print_system_pkg_manual_commands "$PM_KEY" "${SELECTED_PKGS[@]}"
      else
        echo "No system packages selected for removal."
      fi
    fi
  fi
else
  echo "No installed_dependencies record found. Skipping dependency cleanup."
fi

# Offer venv removal even when installed_dependencies was never written.
# PREFIX/venv is preferred; ~/.local/bin/linoffice/venv is the legacy fallback.
VENV_CANDIDATES=()
for _venv in "$LINOFFICE_VENV_DIR" "$LINOFFICE_LEGACY_VENV_DIR"; do
  [[ -d "$_venv" ]] || continue
  _venv_real="$(cd "$_venv" && pwd -P)"
  _already=0
  for _seen in "${VENV_CANDIDATES[@]}"; do
    if [[ "$_seen" == "$_venv_real" ]]; then
      _already=1
      break
    fi
  done
  if [[ "$_already" -eq 0 ]]; then
    VENV_CANDIDATES+=("$_venv_real")
  fi
done
unset _venv _venv_real _already _seen
for VENV_DIR in "${VENV_CANDIDATES[@]}"; do
  read -p "A Python virtual environment was found at $VENV_DIR. Delete it? (y/n): " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -rf "$VENV_DIR"
    echo "Deleted virtual environment: $VENV_DIR"
  else
    echo "Virtual environment deletion skipped."
  fi
done

# Ask to delete the Windows container and its data
read -p "Do you want to delete the Windows container and all its data as well? (y/n): " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
  if ! command -v podman &> /dev/null; then
    echo "Error: Podman is not installed or not accessible."
  else
    # Stop and remove the LinOffice container
    # Check the current status of the container
    CONTAINER_STATUS=$(podman inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)

    # Ensure COMPOSE_COMMAND is set to a working value
    # First try the system podman-compose if it exists and is executable
    if [[ -x "/usr/bin/podman-compose" ]]; then
        COMPOSE_COMMAND="/usr/bin/podman-compose"
    elif command -v podman-compose &>/dev/null; then
        COMPOSE_COMMAND="podman-compose"
    else
        echo "ERROR: No working podman-compose found"
    fi

    # If the container is paused, it must be un-paused first to shut down cleanly
    if [[ "$CONTAINER_STATUS" == "paused" ]]; then
        echo "Container is paused, unpausing to allow clean shutdown..."
        if [[ -n "$COMPOSE_COMMAND" && -f "$COMPOSE_PATH" ]]; then
          linoffice_compose unpause &>/dev/null
        else
          echo "Skipping podman-compose unpause: no podman-compose or compose file available."
        fi
        sleep 2 # Give it a moment to wake up before stopping
    fi

    # Now, if the container is running (or was just un-paused), stop it
    if [[ "$CONTAINER_STATUS" == "running" || "$CONTAINER_STATUS" == "paused" ]]; then
        echo "Sending stop command... (this may take up to 2 minutes)"
        podman stop "$CONTAINER_NAME" &>/dev/null
    else
        echo "Container is not running."
    fi

    echo "Cleaning up all resources..."
    # Finally, run 'down' to ensure the stopped container is fully removed.
    if [[ -n "$COMPOSE_COMMAND" && -f "$COMPOSE_PATH" ]]; then
      linoffice_compose down --remove-orphans &>/dev/null
    else
      echo "Skipping podman-compose down: no podman-compose or compose file available."
    fi

    # Finally, delete the container
    if ! podman rm -f "$CONTAINER_NAME" &> /dev/null; then
      echo "Error: Could not delete the Podman container."
    else
      echo "Deleted "$CONTAINER_NAME" container."
    fi

    # Remove the linoffice_data volume
    if ! podman volume rm linoffice_data &> /dev/null; then
      echo "Error: Could not delete the linoffice_data volume."
    else
      echo "Deleted linoffice_data volume."
    fi
  fi
else
  echo "Windows container and data deletion aborted."
fi

# Check if APPDATA_PATH exists and delete if it does
if [[ -d "$APPDATA_PATH" ]]; then
  read -p "Do you want to delete the app data in $APPDATA_PATH? (y/n): " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -r "$APPDATA_PATH"
    echo "Deleted directory: $APPDATA_PATH"
  else
    echo "Deletion of $APPDATA_PATH aborted."
  fi
else
  echo "Warning: Directory $APPDATA_PATH does not exist."
fi

# Legacy data directory, when resolution picked a different DATA_DIR.
if [[ -d "$LEGACY_DATA_DIR" && "$(realpath -m "$LEGACY_DATA_DIR")" != "$(realpath -m "$APPDATA_PATH")" ]]; then
  read -p "Legacy app data also exists at $LEGACY_DATA_DIR. Delete it too? (y/n): " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -r "$LEGACY_DATA_DIR"
    echo "Deleted directory: $LEGACY_DATA_DIR"
  else
    echo "Deletion of $LEGACY_DATA_DIR aborted."
  fi
fi

# Generated config outside PREFIX (new XDG layout). Legacy $PREFIX/config is removed with PREFIX.
if [[ -d "$LINOFFICE_CONFIG_DIR" ]]; then
  _config_real="$(realpath -m "$LINOFFICE_CONFIG_DIR")"
  _prefix_real="$(realpath -m "$LINOFFICE_PREFIX")"
  case "$_config_real" in
    "$_prefix_real"|"$_prefix_real"/*) ;;
    *)
      read -p "Do you want to delete the LinOffice config directory $_config_real? (y/n): " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        rm -r "$_config_real"
        echo "Deleted directory: $_config_real"
      else
        echo "Deletion of $_config_real aborted."
      fi
      ;;
  esac
  unset _config_real _prefix_real
fi

# Find all files and folders in the same directory as uninstall.sh (excluding itself).
# Skip this for a system prefix (/usr, /app, /nix/store): only user config, data, and desktop files are removed.
if linoffice_is_system_prefix "$LINOFFICE_PREFIX"; then
  echo "Install prefix $LINOFFICE_PREFIX looks like a system directory. Skipping deletion of the application files."
else
  FILES_TO_DELETE=$(find "$SCRIPT_DIR" -maxdepth 1 -not -name "$SCRIPT_NAME")
  if [[ -n "$FILES_TO_DELETE" ]]; then
    echo "The following files and folders will be deleted recursively:"
    echo "$FILES_TO_DELETE"
    read -p "Do you want to proceed with deletion? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      find "$SCRIPT_DIR" -maxdepth 1 -not -name "$SCRIPT_NAME" -exec rm -rf {} \;
      if [[ -f "$SCRIPT_DIR/setup.sh" ]]; then
        rm -f "$SCRIPT_DIR/setup.sh"
      fi
      echo "Files and folders deleted."
      # Delete the uninstall.sh script itself
      echo "Deleting the uninstall script itself."
      rm -f "$0"
      echo "Uninstall script deleted."
    else
      echo "Deletion of files and folders aborted."
    fi
  else
    echo "No files or folders to delete in $SCRIPT_DIR."
  fi

  # Quickstart used to live only at ~/.local/bin/linoffice. Offer that tree when this script is somewhere else.
  if [[ -d "$LEGACY_PREFIX" && -f "$LEGACY_PREFIX/linoffice.sh" && "$(realpath -m "$LEGACY_PREFIX")" != "$(realpath -m "$SCRIPT_DIR")" ]]; then
    read -p "A legacy install also exists at $LEGACY_PREFIX. Delete it? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      rm -rf "$LEGACY_PREFIX"
      echo "Deleted directory: $LEGACY_PREFIX"
    else
      echo "Deletion of $LEGACY_PREFIX aborted."
    fi
  fi
fi

exit 0
