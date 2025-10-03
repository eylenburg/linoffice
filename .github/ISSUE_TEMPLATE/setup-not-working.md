---
name: Setup not working
about: The setup.sh fails to install Windows and Office
title: "[SETUP ERROR] (short description here) "
labels: bug
assignees: ''

---

Please provide the following information:
- Description of what seems to work and what not, where you think the setup has failed
- Confirmation whether you have [tried the setup troubleshooting tips](https://github.com/eylenburg/linoffice?tab=readme-ov-file#problems-with-the-setup) already
- The `windows_install.log` and `setup_output.log` (in `~/.local/share/linoffice`)
- The `setup.log`, `setup_office.log`, and `setup_rdp.log` (if they exist) in `C:\OEM` in the Windows VM (you can access it through `127.0.0.1:8006` in the browser (password is `MyWindowsPassword`) or via RDP with the command `xfreerdp /cert:ignore /u:MyWindowsUser /p:MyWindowsPassword /v:127.0.0.1 /port:3388`)
- Your system information (see above)
- System information:
    - The release version of LinOffice you used
    - Your Linux distribution
    - Your desktop environment
    - Are you using Wayland or X11?
    - How did you install Podman? (e.g. was it preinstalled, or did you install it from the repo, or did you do something more exotic like installing it in a Distrobox container)
    - How did you install Podman-Compose? (e.g. did you install it from the repo, did you install it via `pip`, or did you install it manually)
    - Which FreeRDP version are you using ('native' version from repo or Flatpak)
