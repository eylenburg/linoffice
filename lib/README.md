# Path helpers

`paths.sh` and `paths.py` are the only place that decides where LinOffice reads and writes.

| Variable | Role | New install | Existing install |
|---|---|---|---|
| `LINOFFICE_PREFIX` | Read-only app files, templates, GUI | Directory of `linoffice.sh` | Same |
| `LINOFFICE_CONFIG_DIR` | `compose.yaml`, `linoffice.conf`, working `oem/` | `${XDG_CONFIG_HOME:-~/.config}/linoffice` | `$PREFIX/config` when those generated files are already there |
| `LINOFFICE_DATA_DIR` | Logs, markers, `registry_override.conf` | `${XDG_DATA_HOME:-~/.local/share}/linoffice` | `~/.local/share/linoffice` when that directory already exists |

Override any of them with the environment variable of the same name. `LINOFFICE_APPLICATIONS_DIR` overrides the desktop-file directory. Do not migrate an existing user from `$PREFIX/config` to the XDG config directory; resolution already keeps them on the old tree.
