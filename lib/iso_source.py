#!/usr/bin/env python3
"""Select the Windows installation source without modifying the compose template."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit

from paths import CONFIG_DIR, DATA_DIR

SOURCE_FILE = CONFIG_DIR / "iso-source.yaml"
HEADER = "# LinOffice ISO source: "


def local_path(value: str) -> str:
    if not value:
        raise ValueError("No ISO path was provided.")
    if value.startswith("file:"):
        uri = urlsplit(value)
        if uri.scheme != "file" or uri.netloc not in ("", "localhost"):
            raise ValueError("Only local file URLs are supported.")
        value = unquote(uri.path)
    path = Path(value).expanduser().resolve()
    if any(0xD800 <= ord(character) <= 0xDFFF for character in str(path)):
        raise ValueError("ISO paths must be valid UTF-8.")
    if "\n" in str(path) or "\r" in str(path):
        raise ValueError("ISO paths cannot contain newlines.")
    if path.suffix.lower() != ".iso" or not path.is_file() or not os.access(path, os.R_OK):
        raise ValueError(f"ISO is not a readable .iso file: {path}")
    if path.stat().st_size == 0:
        raise ValueError(f"ISO file is empty: {path}")
    return str(path)


def terminal_path(value: str) -> str:
    value = value.strip()
    if not Path(value).expanduser().is_file():
        try:
            parts = shlex.split(value)
        except ValueError as exc:
            raise ValueError("Invalid quoted ISO path.") from exc
        if len(parts) == 1:
            value = parts[0]
    return local_path(value)


def choose_terminal() -> dict[str, str]:
    if not sys.stdin.isatty():
        raise ValueError("An interactive terminal is required to select the Windows ISO.")
    while True:
        choice = input("Windows installation source: [1] Download VERSION (default), [2] Local ISO: ").strip()
        if choice in ("", "1"):
            return {"mode": "download"}
        if choice == "2":
            while True:
                try:
                    return {"mode": "local", "path": terminal_path(input("ISO path (or drag the file here): "))}
                except ValueError as exc:
                    print(f"Error: {exc}", file=sys.stderr)
        print("Enter 1 or 2.", file=sys.stderr)


def parse_selection(value: str, invalid_message: str, choice_message: str | None = None) -> dict[str, str]:
    try:
        selection: dict[str, object] = json.loads(value)
    except json.JSONDecodeError as exc:
        raise ValueError(invalid_message) from exc
    if type(selection) is not dict:
        raise ValueError(invalid_message)
    if selection.get("mode") == "download":
        return {"mode": "download"}
    path = selection.get("path")
    if selection.get("mode") == "local" and isinstance(path, str):
        return {"mode": "local", "path": local_path(path)}
    raise ValueError(choice_message or invalid_message)


def choose_gui() -> dict[str, str]:
    print("PROMPT:ISO_SOURCE", flush=True)
    line = sys.stdin.readline()
    if not line:
        raise ValueError("ISO selection was cancelled.")
    return parse_selection(line, "Invalid ISO selection from the installer.", "ISO selection was cancelled.")


def write_source(content: str) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=CONFIG_DIR, delete=False) as temp:
            temp_path = Path(temp.name)
            temp.write(content)
        os.replace(temp_path, SOURCE_FILE)
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


def yaml_source(path: str) -> str:
    source = json.dumps(path.replace("$", "$$"), ensure_ascii=False)
    return source.encode("ascii", "backslashreplace").decode("ascii")


def save_selection(selection: dict[str, str]) -> None:
    content = HEADER + json.dumps(selection, ensure_ascii=True) + "\n"
    content += "services:\n  windows:\n"
    if selection["mode"] == "local":
        source = yaml_source(selection["path"])
        content += (
            "    volumes:\n"
            "      - type: bind\n"
            f"        source: {source}\n"
            "        target: /custom.iso\n"
            "        read_only: true\n"
        )
    else:
        content += "    {}\n"
    write_source(content)


def legacy_resume() -> bool:
    progress = DATA_DIR / "setup_progress.log"
    if progress.is_file():
        steps = progress.read_text().splitlines()
        if "requirements_completed" in steps and "iso_source_selection" not in steps:
            return True
    return False


def container_exists() -> bool:
    result = subprocess.run(["podman", "container", "exists", "LinOffice"], check=False)
    if result.returncode not in (0, 1):
        raise ValueError("Could not check whether the LinOffice container exists.")
    return result.returncode == 0


def main() -> None:
    if "--quickstart" in sys.argv and container_exists():
        print("Existing container detected; keeping its Windows ISO source.")
        print("If it uses a local ISO, Podman still needs that file when restarting the container.")
        return
    if SOURCE_FILE.exists():
        content = SOURCE_FILE.read_text(encoding="utf-8")
        header = content.split("\n", 1)[0]
        if not header.startswith(HEADER):
            raise ValueError(f"Invalid ISO selection file: {SOURCE_FILE}")
        saved_selection = parse_selection(header[len(HEADER):], f"Invalid ISO selection file: {SOURCE_FILE}")
        if saved_selection["mode"] == "local":
            path = saved_selection["path"]
            # Older selections encoded non-BMP characters as invalid YAML surrogate pairs.
            if any(ord(character) > 0xFFFF for character in path):
                escaped = json.dumps(path.replace("$", "$$"), ensure_ascii=True)
                unescaped = yaml_source(path)
                old_line = f"        source: {escaped}\n"
                if old_line in content:
                    write_source(content.replace(old_line, f"        source: {unescaped}\n", 1))
        print(f"Using the previously selected Windows ISO source ({SOURCE_FILE}).")
        return
    if "--quickstart" in sys.argv and legacy_resume():
        print("Existing setup detected; keeping its Windows ISO source.")
        return
    selection = choose_gui() if os.environ.get("LINOFFICE_ISO_UI") == "gui" else choose_terminal()
    save_selection(selection)
    print("Windows ISO source saved.")


if __name__ == "__main__":
    try:
        main()
    except (EOFError, OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
