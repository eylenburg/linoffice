#!/usr/bin/env bash

set -euo pipefail
APT_UPDATED=0

REPO_OWNER="eylenburg"
REPO_NAME="linoffice"
TARGET_DIR="$HOME/.local/bin/linoffice"
TMPDIR=$(mktemp -d)
GITHUB_API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"

LINOFFICE_SCRIPT="$TARGET_DIR/gui/linoffice.py"

APPDATA_DIR="$HOME/.local/share/linoffice"
INSTALLED_PM_PACKAGES=()
INSTALLED_FLATPAKS=()
INSTALLED_PIP_PACKAGES=()
FLATPAK_USER=0
PIP_VENV=0

# Virtual environment support
USE_VENV=0
VENV_PATH=""

# Immutable system support
USE_IMMUTABLE=0

##################################################
# PART 1: INSTALL DEPENDENCIES
##################################################

# Detect package manager and distro
detect_package_manager() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID=$ID
    DISTRO_LIKE=${ID_LIKE:-}
  else
    echo "Cannot determine OS version"
    exit 1
  fi

  # Check for immutable systems
  if command -v rpm-ostree >/dev/null 2>&1; then
    echo "Detected Fedora Atomic or another immutable system using rpm-ostree"
    check_immutable_dependencies "rpm-ostree"
    return
  elif command -v transactional-update >/dev/null 2>&1; then
    echo "Detected openSUSE MicroOS or another immutable system using transactional-update"
    check_immutable_dependencies "transactional-update"
    return
  fi

  # Other known immutable distros
  case "$DISTRO_ID" in
    steamos|kde-linux)
      echo "Immutable distribution without usable system package manager detected: $DISTRO_ID"
      # Set flag to use pip-based installation and set dummy package manager
      USE_IMMUTABLE=1
      PKG_MGR="unknown"
      return
      ;;
  esac

  # Reject other systems
  case "$DISTRO_ID" in
    nixos|guix|slackware|gentoo|alpine)
      echo "Unsupported system type: $DISTRO_ID"
      exit 1
      ;;
  esac

  for mgr in apt dnf yum zypper pacman xbps-install eopkg urpmi; do
    if command -v "$mgr" >/dev/null 2>&1; then
      PKG_MGR=$mgr
      return
    fi
  done

  echo "Unsupported package manager"
  exit 1
}

# Check dependencies for immutable systems
check_immutable_dependencies() {
  local immutable_tool="$1"
  local missing_pkgs=()
  local need_pip=false
  local need_flatpak=false
  
  echo "Checking required packages for immutable system..."
  
  # Check podman (always required)
  if ! command -v podman >/dev/null 2>&1; then
    missing_pkgs+=("podman")
  fi
  
  # Check Python (always required)
  if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
    missing_pkgs+=("python3")
  fi
  
  # Check if we need pip (only if podman-compose or PySide6 are not available)
  if ! pkg_exists podman-compose || ! python3 -c "import PySide6" 2>/dev/null; then
    need_pip=true
    if ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
      missing_pkgs+=("python3-pip")
    fi
  fi
  
  # Check if we need flatpak (only if FreeRDP is not available)
  if ! freerdp_version_ok; then
    need_flatpak=true
    if ! command -v flatpak >/dev/null 2>&1; then
      missing_pkgs+=("flatpak")
    fi
  fi
  
  if [ ${#missing_pkgs[@]} -gt 0 ]; then
    echo "❌ Missing required packages: ${missing_pkgs[*]}"
    echo ""
    echo "Please install them using:"
    if [ "$immutable_tool" = "rpm-ostree" ]; then
      echo "  sudo rpm-ostree install ${missing_pkgs[*]}"
      echo "  sudo systemctl reboot"
    elif [ "$immutable_tool" = "transactional-update" ]; then
      echo "  sudo transactional-update pkg install ${missing_pkgs[*]}"
      echo "  sudo transactional-update reboot"
    fi
    echo ""
    echo "After reboot, run this installer again."
    exit 1
  fi
  
  echo "✅ All required packages are available"
  if [ "$need_pip" = true ]; then
    echo "Will use pip for Python dependencies"
  fi
  if [ "$need_flatpak" = true ]; then
    echo "Will use flatpak for FreeRDP"
  fi
  if [ "$need_pip" = false ] && [ "$need_flatpak" = false ]; then
    echo "All dependencies already available via system packages"
  fi
  
  # Set flag to use pip-based installation and set dummy package manager
  USE_IMMUTABLE=1
  PKG_MGR="unknown"
  return 0
}

# Generic install function
install_pkg() {
  local pkg="$1"
  local rc=1

  # Check if sudo is available
  if ! check_sudo; then
    show_manual_install "$pkg"
  fi

  case "$PKG_MGR" in
    apt)
      if [ "$APT_UPDATED" -eq 0 ]; then
        sudo apt-get update
        APT_UPDATED=1
      fi
      sudo apt-get install -y "$pkg"
      rc=$?
      ;;
    dnf|yum)
      sudo "$PKG_MGR" install -y "$pkg"
      rc=$?
      ;;
    zypper)
      sudo zypper --non-interactive install "$pkg"
      rc=$?
      ;;
    pacman)
      sudo pacman -Syu --noconfirm "$pkg"
      rc=$?
      ;;
    xbps-install)
      sudo xbps-install -Sy "$pkg"
      rc=$?
      ;;
    eopkg)
      sudo eopkg install -y "$pkg"
      rc=$?
      ;;
    urpmi)
      sudo urpmi --auto "$pkg"
      rc=$?
      ;;
    *)
      echo "Unknown package manager: $PKG_MGR"
      return 1
      ;;
  esac
  if [ $rc -eq 0 ]; then
    INSTALLED_PM_PACKAGES+=("$pkg")
  fi
  return $rc
}

# Try list of possible package names
try_install_any() {
  for name in "$@"; do
    if install_pkg "$name"; then
      return 0
    fi
  done
  return 1
}

# Command check
pkg_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if sudo is available
check_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# Function to show manual installation instructions
show_manual_install() {
  local packages=("$@")
  echo -e "\033[1;31mIt seems that sudo is not available on your system. Please manually install these packages:\033[0m"
  echo -e "\033[1;31m${packages[*]}\033[0m"
  exit 1
}

ensure_pip() {
  if ! pkg_exists pip3 && ! pkg_exists pip; then
    try_install_any python3-pip python-pip python-pip3 || {
      echo "Failed to install pip"
      exit 1
    }
  fi
}

# Detect available pip command (prefer pip3)
get_pip_cmd() {
  if command -v pip3 >/dev/null 2>&1; then
    echo pip3
  elif command -v pip >/dev/null 2>&1; then
    echo pip
  else
    echo ""  # none
  fi
}

# Check if python-dotenv is installed in the current environment
is_python_dotenv_installed() {
  local pip_cmd
  pip_cmd=$(get_pip_cmd)
  if [ -n "$pip_cmd" ] && "$pip_cmd" show python-dotenv >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

freerdp_version_ok() {
  if command -v xfreerdp >/dev/null 2>&1; then
    ver=$(xfreerdp --version | grep -oP '\d+\.\d+\.\d+' | head -n1)
    major=$(echo "$ver" | cut -d. -f1)
    [ "$major" -ge 3 ]
  else
    return 1
  fi
}

# Flatpak fallback
install_freerdp_flatpak() {
  if ! pkg_exists flatpak; then
    try_install_any flatpak || { echo "Failed to install flatpak"; exit 1; }
  fi

# make sure to specifically detect flathub user, not flathub system
  if ! flatpak remote-list | grep -q 'flathub.*user'; then
    flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi

  flatpak install -y --user flathub com.freerdp.FreeRDP
  INSTALLED_FLATPAKS+=("com.freerdp.FreeRDP")
  FLATPAK_USER=1
}

# Virtual environment setup function
use_venv() {
  local python_cmd=""
  local venv_dir="$TARGET_DIR/venv"
  
  # Find Python command
  if command -v python3 >/dev/null 2>&1; then
    python_cmd="python3"
  elif command -v python >/dev/null 2>&1; then
    python_cmd="python"
  else
    echo "Python not found, cannot create venv"
    return 1
  fi
  
  # Check if venv module is available
  if ! "$python_cmd" -c "import venv" 2>/dev/null; then
    echo "venv module not available, falling back to system Python"
    return 1
  fi
  
  echo "Creating virtual environment..."
  if "$python_cmd" -m venv --system-site-packages "$venv_dir"; then
    VENV_PATH="$venv_dir"
    USE_VENV=1
    echo "Virtual environment created successfully"
    return 0
  else
    echo "Failed to create virtual environment, falling back to system Python"
    return 1
  fi
}

# Main script for installing dependencies
dependencies_main() {
  detect_package_manager

  if [ "$USE_IMMUTABLE" -eq 1 ]; then
    echo "Detected distro: $DISTRO_ID (immutable system)"
  else
    echo "Detected distro: $DISTRO_ID, package manager: $PKG_MGR"
  fi

  echo "Checking podman..."
  if ! pkg_exists podman; then
    try_install_any podman || { echo "Failed to install podman"; exit 1; }
  fi

  echo "Checking Python 3..."
  if ! pkg_exists python3 && ! pkg_exists python; then
    try_install_any python3 python || { echo "Failed to install Python 3"; exit 1; }
  fi

  echo "Checking FreeRDP (version >= 3)..."
  if freerdp_version_ok; then
    echo "FreeRDP is already version >= 3"
    if [ "$USE_IMMUTABLE" -eq 1 ]; then
      echo "FreeRDP already available via system package manager"
    fi
  else
    if [ "$USE_IMMUTABLE" -eq 1 ]; then
      echo "Installing FreeRDP via flatpak for immutable system..."
      install_freerdp_flatpak
    else
      try_install_any freerdp3 freerdp3-x11 freerdp || true
      if ! freerdp_version_ok; then
        echo "Falling back to Flatpak for FreeRDP"
        install_freerdp_flatpak
      fi
    fi
  fi

  # Check if podman-compose needs to be installed via pip
  NEED_PODMAN_COMPOSE_PIP=false
  if ! pkg_exists podman-compose; then
    if [ "$USE_IMMUTABLE" -eq 1 ]; then
      echo "podman-compose not available, will install via pip for immutable system"
      NEED_PODMAN_COMPOSE_PIP=true
    else
      try_install_any podman-compose || true
      if ! pkg_exists podman-compose; then
        echo "podman-compose not available via package manager, will install via pip"
        NEED_PODMAN_COMPOSE_PIP=true
      fi
    fi
  else
    if [ "$USE_IMMUTABLE" -eq 1 ]; then
      echo "podman-compose already available via system package manager"
    fi
  fi

  # Check if PySide6 needs to be installed via pip
  NEED_PYSIDE6_PIP=false
  if ! python3 -c "import PySide6" 2>/dev/null; then
    if [ "$USE_IMMUTABLE" -eq 1 ]; then
      echo "PySide6 not available, will install via pip for immutable system"
      NEED_PYSIDE6_PIP=true
    else
      try_install_any python3-pyside6 python-pyside6 python3-pyside6.qtcore python3-pyside6.qtwidgets python-pyside6.qtuitools || true
      if ! python3 -c "import PySide6" 2>/dev/null; then
        echo "PySide6 not available via package manager, will install via pip"
        NEED_PYSIDE6_PIP=true
      fi
    fi
  else
    if [ "$USE_IMMUTABLE" -eq 1 ]; then
      echo "PySide6 already available via system package manager"
    fi
  fi

  # Install Python dependencies via pip if needed
  if [ "$NEED_PODMAN_COMPOSE_PIP" = true ] || [ "$NEED_PYSIDE6_PIP" = true ]; then
    echo "Setting up Python environment for pip installations..."
    
    if use_venv; then
      echo "Using virtual environment for Python dependencies"
      source "$VENV_PATH/bin/activate"
      
      if [ "$NEED_PODMAN_COMPOSE_PIP" = true ]; then
        echo "Installing podman-compose via pip in virtual environment"
        pre_has_dotenv=0
        if is_python_dotenv_installed; then pre_has_dotenv=1; fi
        "$VENV_PATH/bin/pip" install podman-compose
        INSTALLED_PIP_PACKAGES+=("podman-compose")
        PIP_VENV=1
        if [ $pre_has_dotenv -eq 0 ] && is_python_dotenv_installed; then
          INSTALLED_PIP_PACKAGES+=("python-dotenv")
        fi
      fi
      
      if [ "$NEED_PYSIDE6_PIP" = true ]; then
        echo "Installing PySide6 via pip in virtual environment"
        "$VENV_PATH/bin/pip" install PySide6
        INSTALLED_PIP_PACKAGES+=("PySide6")
        PIP_VENV=1
      fi
      
      deactivate
    else
      echo "Using system Python"
      
      if [ "$NEED_PODMAN_COMPOSE_PIP" = true ]; then
        echo "Installing podman-compose via pip with --break-system-packages"
        ensure_pip
        pre_has_dotenv=0
        if is_python_dotenv_installed; then pre_has_dotenv=1; fi
        pip3 install --user --break-system-packages podman-compose || pip install --user --break-system-packages podman-compose
        INSTALLED_PIP_PACKAGES+=("podman-compose")
        export PATH="$HOME/.local/bin:$PATH"
        if [ $pre_has_dotenv -eq 0 ] && is_python_dotenv_installed; then
          INSTALLED_PIP_PACKAGES+=("python-dotenv")
        fi
      fi
      
      if [ "$NEED_PYSIDE6_PIP" = true ]; then
        echo "Installing PySide6 via pip with --break-system-packages"
        ensure_pip
        pip3 install --user --break-system-packages PySide6 || pip install --user --break-system-packages PySide6
        INSTALLED_PIP_PACKAGES+=("PySide6")
        
        # Verify PySide6 installation
        if ! python3 -c "import PySide6" 2>/dev/null; then
          echo "Failed to install PySide6"
          exit 1
        fi
      fi
    fi
  else
    if [ "$USE_IMMUTABLE" -eq 1 ]; then
      echo "All Python dependencies already available via system package manager"
    fi
  fi

# Debian/Ubuntu/Mint: detect if the error "qt.qpa.plugin: Could not load the Qt platform plugin "xcb" in "" even though it was found." occurs when runnin PySide6 program. Then install packages via apt to make it work (these packages are not yet recorded in installed_dependencies).
# List of required dependencies: https://stackoverflow.com/questions/68036484/qt-qpa-plugin-could-not-load-the-qt-platform-plugin-xcb-in-even-though-it/76191114#76191114
if [ "$PKG_MGR" = "apt" ]; then
    if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ] || [ "$DISTRO_ID" = "linuxmint" ] || echo "$DISTRO_LIKE" | grep -qiE '(debian|ubuntu)'; then
        if python3 -c "import PySide6" >/dev/null 2>&1; then
            __qt_check_output=$(python3 - <<'PY' 2>&1
from PySide6.QtWidgets import QApplication
try:
    app = QApplication([])
    print("OK")
except Exception:
    import traceback
    traceback.print_exc()
PY
)
            if echo "${__qt_check_output}" | grep -qiE '(qt\.qpa\.plugin|xcb)'; then
                echo "Detected Qt xcb plugin issue. Installing missing development libraries via apt..."
                sudo apt-get update
                sudo apt-get install -y '^libxcb.*-dev' libx11-xcb-dev libglu1-mesa-dev libxrender-dev libxi-dev libxkbcommon-dev libxkbcommon-x11-dev
            fi
            unset __qt_check_output
        fi
    fi
fi

  echo "✅ All dependencies installed successfully!"

  # Write installed dependencies summary
  mkdir -p "$APPDATA_DIR"
  SUMMARY_FILE="$APPDATA_DIR/installed_dependencies"
  PM_KEY="$PKG_MGR"

  pm_list="${INSTALLED_PM_PACKAGES[*]:-}"
  flatpak_list="${INSTALLED_FLATPAKS[*]:-}"
  pip_list="${INSTALLED_PIP_PACKAGES[*]:-}"

  # Merge with existing summary if present
  existing_pm_key=""
  existing_pm_vals=""
  existing_flatpak_vals=""
  existing_pip_vals=""
  existing_flatpak_user=0
  existing_pip_venv=0

  if [ -f "$SUMMARY_FILE" ]; then
    existing_pm_key=$(grep -E '^(apt|dnf|yum|zypper|pacman|xbps-install|eopkg|urpmi)=' "$SUMMARY_FILE" | head -n1 | cut -d= -f1 || true)
    if [ -n "${existing_pm_key}" ]; then
      existing_pm_vals=$(grep -E "^${existing_pm_key}=" "$SUMMARY_FILE" | sed -E 's/^[^=]+=//; s/^"//; s/"$//' || true)
    fi
    existing_flatpak_vals=$(grep -E '^flatpak=' "$SUMMARY_FILE" | sed -E 's/^flatpak=//; s/^"//; s/"$//' || true)
    existing_pip_vals=$(grep -E '^pip=' "$SUMMARY_FILE" | sed -E 's/^pip=//; s/^"//; s/"$//' || true)
    existing_flatpak_user=$(grep -E '^flatpak_user=' "$SUMMARY_FILE" | tail -n1 | cut -d= -f2 || echo 0)
    existing_pip_venv=$(grep -E '^pip_venv=' "$SUMMARY_FILE" | tail -n1 | cut -d= -f2 || echo 0)
  fi

  # Determine the key to use for package-manager line
  pm_key_to_write="${existing_pm_key:-$PM_KEY}"

  # Build unique merged lists
  combined_pm=""
  combined_flatpak=""
  combined_pip=""

  declare -A __seen_pm __seen_flatpak __seen_pip

  for item in $existing_pm_vals $pm_list; do
    [ -n "$item" ] || continue
    if [ -z "${__seen_pm[$item]+x}" ]; then
      combined_pm+="${combined_pm:+ }$item"
      __seen_pm[$item]=1
    fi
  done

  for item in $existing_flatpak_vals $flatpak_list; do
    [ -n "$item" ] || continue
    if [ -z "${__seen_flatpak[$item]+x}" ]; then
      combined_flatpak+="${combined_flatpak:+ }$item"
      __seen_flatpak[$item]=1
    fi
  done

  for item in $existing_pip_vals $pip_list; do
    [ -n "$item" ] || continue
    if [ -z "${__seen_pip[$item]+x}" ]; then
      combined_pip+="${combined_pip:+ }$item"
      __seen_pip[$item]=1
    fi
  done

  # Flags accumulate across runs (logical OR)
  final_flatpak_user=0
  if [ "${existing_flatpak_user}" = "1" ] || [ "${FLATPAK_USER}" = "1" ]; then
    final_flatpak_user=1
  fi
  final_pip_venv=0
  if [ "${existing_pip_venv}" = "1" ] || [ "${PIP_VENV}" = "1" ]; then
    final_pip_venv=1
  fi

  {
    echo "Dependencies installed by quickstart.sh:"
    echo "${pm_key_to_write}=\"${combined_pm}\""
    echo "flatpak=\"${combined_flatpak}\""
    echo "pip=\"${combined_pip}\""
    echo "flatpak_user=${final_flatpak_user}"
    echo "pip_venv=${final_pip_venv}"
  } > "$SUMMARY_FILE"
}


##################################################
# PART 2: DOWNLOAD LATEST LINOFFICE
##################################################

download_latest() {
  echo "Fetching latest LinOffice version from GitHub..."

  LATEST_VERSION=$(curl -sSL "$GITHUB_API_URL" | \
    grep -E '"tag_name":\s*"v[0-9]+\.[0-9]+\.[0-9]+"' | \
    grep -v '"prerelease": true' | \
    grep -v '"draft": true' | \
    head -n1 | \
    sed -E 's/.*"v([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')

  if [[ -z "$LATEST_VERSION" ]]; then
    echo "Error: Could not determine latest version."
    exit 1
  fi

  ZIP_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/tags/v${LATEST_VERSION}.zip"
  ZIP_FILE="$TMPDIR/linoffice.zip"

  echo "Downloading Linoffice v${LATEST_VERSION} from:"
  echo "$ZIP_URL"

  # Modified: Add -L to follow redirects during status check
  HTTP_STATUS=$(curl -s -L -o /dev/null -w "%{http_code}" "$ZIP_URL")

  if [[ "$HTTP_STATUS" != "200" ]]; then
    echo "Error: File not found at $ZIP_URL (HTTP $HTTP_STATUS)"
    exit 1
  fi

  curl -L -o "$ZIP_FILE" "$ZIP_URL"

  # Check it’s really a zip
  if ! file "$ZIP_FILE" | grep -q "Zip archive data"; then
    echo "Error: Downloaded file is not a valid zip archive."
    file "$ZIP_FILE"
    exit 1
  fi

  echo "Unzipping..."
  unzip -q "$ZIP_FILE" -d "$TMPDIR"

  # Expected folder name: linoffice-${LATEST_VERSION}
  EXTRACTED_DIR="$TMPDIR/linoffice-${LATEST_VERSION}"

  if [[ ! -d "$EXTRACTED_DIR" ]]; then
    echo "Error: Expected folder 'linoffice-${LATEST_VERSION}' not found in zip."
    exit 1
  fi

  # Determine source directory to install (prefer src/ if present)
  SOURCE_DIR="$EXTRACTED_DIR"
  if [[ -d "$EXTRACTED_DIR/src" ]]; then
    echo "Detected 'src' directory inside archive; using its contents for installation."
    SOURCE_DIR="$EXTRACTED_DIR/src"
  fi

  echo "Installing to $TARGET_DIR..."

  # Check if TARGET_DIR exists and contains linoffice.sh
  if [[ -d "$TARGET_DIR" && -f "$TARGET_DIR/linoffice.sh" ]]; then
    echo "Existing installation found. Updating files..."
    cp -a "$SOURCE_DIR"/. "$TARGET_DIR"/
  else
    # If TARGET_DIR doesn't exist or doesn't contain linoffice.sh, replace it with contents of SOURCE_DIR
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    cp -a "$SOURCE_DIR"/. "$TARGET_DIR"/
  fi

  # Make everything executable
  find "$TARGET_DIR" -type f \( -name "*.py" -o -name "*.sh" \) -exec chmod +x {} \;

  rm -rf "$TMPDIR"

  echo "✅ Linoffice v${LATEST_VERSION} installed at $TARGET_DIR"
}

##################################################
# PART 3: Run LinOffice
##################################################

start_linoffice() {
  # Run the linoffice installer
  echo "Starting Linoffice..."

  # Check for virtual environment first, then fall back to system Python
  if [[ "$USE_VENV" == "1" && -f "$VENV_PATH/bin/python3" ]]; then
    PYTHON_CMD="$VENV_PATH/bin/python3"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
  else
    echo "Error: Python not found. Please install Python."
    exit 1
  fi

  # Check if the linoffice.py script exists
  if [[ ! -f "$LINOFFICE_SCRIPT" ]]; then
    echo "Error: $LINOFFICE_SCRIPT not found. Please check the installation."
    exit 1
  fi

  echo "Running $LINOFFICE_SCRIPT with $PYTHON_CMD..."
  nohup "$PYTHON_CMD" "$LINOFFICE_SCRIPT" > /dev/null 2>&1 &
}

##################################################
# Main logic
##################################################

read -p "Welcome to the LinOffice installer. We will check and install dependencies, download the latest LinOffice release, and then run the main setup, which will install a Windows container with Microsoft Office. Are you sure you want to continue? (y/n): " confirmation
if [[ "$confirmation" == "y" || "$confirmation" == "Y" ]]; then
  dependencies_main "$@"
  download_latest
  start_linoffice
else
  echo "Cancelled."
  exit 1
fi
