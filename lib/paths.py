"""LinOffice path authority for Python. Mirrors lib/paths.sh.

PREFIX     read-only app files (directory that contains linoffice.sh)
CONFIG_DIR writable compose.yaml, linoffice.conf, and working oem/
DATA_DIR   writable logs, markers, and registry_override.conf

Resolution:
  PREFIX:
    1. LINOFFICE_PREFIX if it is a directory containing linoffice.sh
    2. Walk up from this file until linoffice.sh is found
    3. Raise FileNotFoundError
  CONFIG_DIR:
    1. LINOFFICE_CONFIG_DIR if set
    2. ${XDG_CONFIG_HOME:-~/.config}/linoffice if compose.yaml or linoffice.conf is there
    3. $PREFIX/config if compose.yaml or linoffice.conf is there (legacy install)
    4. ${XDG_CONFIG_HOME:-~/.config}/linoffice
  DATA_DIR:
    1. LINOFFICE_DATA_DIR if set
    2. ${XDG_DATA_HOME:-~/.local/share}/linoffice if it looks like LinOffice state
    3. ~/.local/share/linoffice if that directory exists
    4. ${XDG_DATA_HOME:-~/.local/share}/linoffice

paths.env is not read. Resolution above is the source of truth.
"""

import os
import shutil
import sys
from pathlib import Path

_STATE_MARKERS = (
    "success",
    "setup_progress.log",
    "linoffice.log",
    "sleep_marker",
    "installed_dependencies",
)


def _env(name):
    value = os.environ.get(name)
    if value is None or value == "":
        return None
    return value


def _find_prefix_from(start):
    cur = Path(start).resolve()
    if cur.is_file():
        cur = cur.parent
    for candidate in [cur, *cur.parents]:
        if (candidate / "linoffice.sh").is_file():
            return candidate
    return None


def _has_state(directory):
    return any((directory / name).is_file() for name in _STATE_MARKERS)


def _resolve():
    user_prefix = _env("LINOFFICE_PREFIX")
    prefix = None
    if user_prefix:
        candidate = Path(user_prefix)
        if candidate.is_dir() and (candidate / "linoffice.sh").is_file():
            prefix = candidate.resolve()
        else:
            print(
                "LinOffice: ignoring LINOFFICE_PREFIX=%r "
                "(not a directory containing linoffice.sh)." % user_prefix,
                file=sys.stderr,
            )
    if prefix is None:
        prefix = _find_prefix_from(Path(__file__))
    if prefix is None:
        raise FileNotFoundError(
            "Could not find LINOFFICE_PREFIX (no linoffice.sh above lib/paths.py). "
            "Set LINOFFICE_PREFIX to the directory that contains linoffice.sh."
        )

    home = Path.home()
    xdg_config_root = Path(_env("XDG_CONFIG_HOME") or (home / ".config"))
    xdg_config = xdg_config_root / "linoffice"
    legacy_config = prefix / "config"
    user_config = _env("LINOFFICE_CONFIG_DIR")
    if user_config:
        config_dir = Path(user_config)
    elif (xdg_config / "compose.yaml").is_file() or (xdg_config / "linoffice.conf").is_file():
        config_dir = xdg_config
    elif (legacy_config / "compose.yaml").is_file() or (legacy_config / "linoffice.conf").is_file():
        config_dir = legacy_config
    else:
        config_dir = xdg_config

    xdg_data_root = Path(_env("XDG_DATA_HOME") or (home / ".local" / "share"))
    xdg_data = xdg_data_root / "linoffice"
    legacy_data = home / ".local" / "share" / "linoffice"
    user_data = _env("LINOFFICE_DATA_DIR")
    if user_data:
        data_dir = Path(user_data)
    elif xdg_data.is_dir() and _has_state(xdg_data):
        data_dir = xdg_data
    elif legacy_data.is_dir():
        data_dir = legacy_data
    else:
        data_dir = xdg_data

    user_apps = _env("LINOFFICE_APPLICATIONS_DIR")
    if user_apps:
        applications_dir = Path(user_apps)
    else:
        applications_dir = xdg_data_root / "applications"

    return {
        "PREFIX": prefix,
        "CONFIG_DIR": config_dir,
        "DATA_DIR": data_dir,
        "APPLICATIONS_DIR": applications_dir,
        "LEGACY_DATA_DIR": legacy_data,
        "LEGACY_CONFIG_DIR": legacy_config,
    }


_resolved = _resolve()

PREFIX = _resolved["PREFIX"]
CONFIG_DIR = _resolved["CONFIG_DIR"]
DATA_DIR = _resolved["DATA_DIR"]
APPLICATIONS_DIR = _resolved["APPLICATIONS_DIR"]
LEGACY_DATA_DIR = _resolved["LEGACY_DATA_DIR"]
LEGACY_CONFIG_DIR = _resolved["LEGACY_CONFIG_DIR"]

COMPOSE_FILE = CONFIG_DIR / "compose.yaml"
CONF_FILE = CONFIG_DIR / "linoffice.conf"
OEM_DIR = CONFIG_DIR / "oem"
OEM_TEMPLATES_DIR = PREFIX / "config" / "oem"
COMPOSE_DEFAULT = PREFIX / "config" / "compose.yaml.default"
CONF_DEFAULT = PREFIX / "config" / "linoffice.conf.default"
LANGUAGES_CSV = PREFIX / "config" / "languages.csv"
LINOFFICE_SCRIPT = PREFIX / "linoffice.sh"
SETUP_SCRIPT = PREFIX / "setup.sh"
UNINSTALL_SCRIPT = PREFIX / "uninstall.sh"
VENV_DIR = PREFIX / "venv"
LEGACY_VENV_DIR = Path.home() / ".local" / "bin" / "linoffice" / "venv"


def _same_path(left, right):
    return os.path.realpath(str(left)) == os.path.realpath(str(right))


def ensure_dirs():
    (CONFIG_DIR / "oem" / "registry").mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "instances").mkdir(parents=True, exist_ok=True)


def _normalize_oem_volume(compose_file):
    """Point a freshly copied compose file at ./oem next to itself."""
    try:
        text = compose_file.read_text(encoding="utf-8")
    except OSError:
        return
    lines = text.splitlines()
    changed = False
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith("- ") and ":/oem" in stripped and "./oem:/oem" not in stripped:
            lines[index] = "      - ./oem:/oem:Z"
            changed = True
    if changed:
        compose_file.write_text("\n".join(lines) + ("\n" if text.endswith("\n") else ""), encoding="utf-8")


def sync_oem_templates():
    """Copy missing OEM templates into the working oem directory. Never overwrite."""
    src = OEM_TEMPLATES_DIR
    dst = OEM_DIR
    if not src.is_dir():
        return
    dst.mkdir(parents=True, exist_ok=True)
    if _same_path(src, dst):
        return
    for path in src.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(src)
        target = dst / rel
        if target.exists():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)


def seed_config():
    """Copy templates into CONFIG_DIR when the generated files are missing.

    Does not overwrite compose.yaml, linoffice.conf, or any existing oem file.
    Does not run the locale scripts; setup.sh and a first linoffice.sh seed do that.
    Returns a dict with keys "compose" and "conf" set when that file was created.
    """
    ensure_dirs()
    created = {"compose": False, "conf": False}
    if not COMPOSE_FILE.is_file():
        if not COMPOSE_DEFAULT.is_file():
            raise FileNotFoundError("missing compose template: %s" % COMPOSE_DEFAULT)
        shutil.copy2(COMPOSE_DEFAULT, COMPOSE_FILE)
        _normalize_oem_volume(COMPOSE_FILE)
        created["compose"] = True
    if not CONF_FILE.is_file():
        if not CONF_DEFAULT.is_file():
            raise FileNotFoundError("missing config template: %s" % CONF_DEFAULT)
        shutil.copy2(CONF_DEFAULT, CONF_FILE)
        created["conf"] = True
    sync_oem_templates()
    return created


def read_data_path(relative):
    """DATA_DIR/relative if it exists, else the legacy data path, else DATA_DIR/relative."""
    primary = DATA_DIR / relative
    legacy = LEGACY_DATA_DIR / relative
    if primary.exists():
        return primary
    if legacy.exists():
        return legacy
    return primary


def legacy_fallback_copy(relative):
    """Copy DATA_DIR/relative onto ~/.local/share/linoffice/relative when those paths differ."""
    primary = DATA_DIR / relative
    legacy = LEGACY_DATA_DIR / relative
    if not primary.exists():
        return
    if _same_path(primary, legacy):
        return
    legacy.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(str(primary), str(legacy))


def find_venv():
    """Return PREFIX/venv, or the legacy quickstart venv if that is the one that exists."""
    if (VENV_DIR / "bin" / "activate").is_file():
        return VENV_DIR
    if (LEGACY_VENV_DIR / "bin" / "activate").is_file():
        return LEGACY_VENV_DIR
    return VENV_DIR
