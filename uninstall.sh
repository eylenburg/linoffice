#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
COMPOSE_PATH="$(realpath "${SCRIPT_DIR}/config/compose.yaml")"
CONTAINER_NAME="LinOffice"
echo "Executing uninstall script in $SCRIPT_DIR"

# Check if setup.sh exists and extract USER_APPLICATIONS_DIR and APPDATA_PATH
if [[ ! -f "$SCRIPT_DIR/setup.sh" ]]; then
  echo "Warning: setup.sh not found in the current directory."
else
  eval $(grep -E '^\s*USER_APPLICATIONS_DIR=' $SCRIPT_DIR/setup.sh)
  eval $(grep -E '^\s*APPDATA_PATH=' $SCRIPT_DIR/setup.sh)

  if [[ -z "$USER_APPLICATIONS_DIR" ]]; then
    echo "Warning: USER_APPLICATIONS_DIR not found in setup.sh."
  fi

  if [[ -z "$APPDATA_PATH" ]]; then
    echo "Warning: APPDATA_PATH not found in setup.sh."
  fi
fi


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

# Find .desktop files containing linoffice.sh in Exec= line
if [[ -n "$USER_APPLICATIONS_DIR" ]]; then
  DESKTOP_FILES=$(find "$USER_APPLICATIONS_DIR" -type f -name "*.desktop" -exec grep -l "Exec=.*linoffice.sh" {} \;)
  # Also include the GUI launcher if present
  if [[ -f "$USER_APPLICATIONS_DIR/linoffice.desktop" ]]; then
    if [[ -n "$DESKTOP_FILES" ]]; then
      DESKTOP_FILES="$DESKTOP_FILES
$USER_APPLICATIONS_DIR/linoffice.desktop"
    else
      DESKTOP_FILES="$USER_APPLICATIONS_DIR/linoffice.desktop"
    fi
  fi
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

# Resolve the installed_dependencies file path
INSTALLED_DEPS_FILE=""
DEFAULT_APPDATA_PATH="$HOME/.local/share/linoffice"
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

  # Clean up virtual environment if used
  if [[ "$PIP_VENV" == "1" ]]; then
    VENV_DIR="$HOME/.local/bin/linoffice/venv"
    if [[ -d "$VENV_DIR" ]]; then
      read -p "A Python virtual environment was used at $VENV_DIR. Delete it? (y/n): " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        rm -rf "$VENV_DIR"
        echo "Deleted virtual environment: $VENV_DIR"
      else
        echo "Virtual environment deletion skipped."
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
        # Check if sudo is available
        if ! check_sudo; then
          show_manual_uninstall "${SELECTED_PKGS[@]}"
        else 
          echo "Removing selected packages via $PM_KEY: ${SELECTED_PKGS[*]}"
          case "$PM_KEY" in
            apt)
              sudo apt-get purge -y "${SELECTED_PKGS[@]}" || true
              sudo apt-get autoremove -y || true
              ;;
            dnf)
              sudo dnf remove -y "${SELECTED_PKGS[@]}" || true
              ;;
            yum)
              sudo yum remove -y "${SELECTED_PKGS[@]}" || true
              ;;
            zypper)
              sudo zypper --non-interactive remove --clean-deps "${SELECTED_PKGS[@]}" || true
              ;;
            pacman)
              sudo pacman -Rs --noconfirm "${SELECTED_PKGS[@]}" || true
              ;;
            xbps-install)
              sudo xbps-remove -R "${SELECTED_PKGS[@]}" || true
              ;;
            eopkg)
              sudo eopkg remove -y "${SELECTED_PKGS[@]}" || true
              ;;
            urpmi)
              sudo urpme "${SELECTED_PKGS[@]}" || true
              ;;
            *)
              echo "Unknown package manager key: $PM_KEY"
              ;;
          esac
        fi
      else
        echo "No system packages selected for removal."
      fi
    fi
  fi
else
  echo "No installed_dependencies record found. Skipping dependency cleanup."
fi

# Ask to delete the Windows container and its data
# Detect container engine (Docker or Podman)
ENGINE_FILE="$SCRIPT_DIR/gui/engine.txt"
if [[ -f "$ENGINE_FILE" ]]; then
  ENGINE=$(cat "$ENGINE_FILE" | tr -d '[:space:]')
else
  ENGINE="podman"
fi

# Ask to delete the container and its data
read -p "Do you want to delete the Windows container and all its data as well? (y/n): " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
  if ! command -v "$ENGINE" &> /dev/null; then
    echo "Error: $ENGINE is not installed or not accessible."
  else
    CONTAINER_STATUS=$($ENGINE inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)

    if [[ "$CONTAINER_STATUS" == "paused" ]]; then
      echo "Container is paused, unpausing..."
      $ENGINE unpause "$CONTAINER_NAME" &>/dev/null
      sleep 2
    fi

    if [[ "$CONTAINER_STATUS" == "running" || "$CONTAINER_STATUS" == "paused" ]]; then
      echo "Stopping container..."
      $ENGINE stop "$CONTAINER_NAME" &>/dev/null
    else
      echo "Container is not running."
    fi

    echo "Removing container..."
    $ENGINE rm -f "$CONTAINER_NAME" &>/dev/null || echo "Error: Could not delete container."

    echo "Removing associated data..."
    if [[ "$ENGINE" == "podman" ]]; then
      $ENGINE volume rm linoffice_data &>/dev/null || true
    else
      $ENGINE volume prune -f &>/dev/null
      $ENGINE system prune -a -f &>/dev/null
    fi

    echo "Cleanup completed for $ENGINE."
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

# Find all files and folders in the same directory as uninstall.sh (excluding itself)

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

exit 0
