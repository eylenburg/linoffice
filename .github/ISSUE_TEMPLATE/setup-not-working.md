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
- The `windows_install.log` and `setup_output.log` which can be found in:
    - Flatpak version of LinOffice: `~/.var/app/io.github.eylenburg.LinOffice/data/linoffice/`
    - Manual install of LinOffice or quickstart script: `~/.local/share/linoffice/`
- The `setup.log`, `setup_office.log`, and `setup_rdp.log`, if they exist, in `C:\OEM` inside the Windows virtual machine. Open the virtual machine at http://127.0.0.1:8006 in a browser (password `MyWindowsPassword`). The browser session does not share the clipboard with Linux, so a screenshot is enough. From an install of this repository you can also connect with `xfreerdp3 /cert:ignore /u:MyWindowsUser /p:MyWindowsPassword /v:127.0.0.1 /port:3388` (use `xfreerdp` when that is the command on your system)
- Your system information (see above)
- System information:
    - The release version of LinOffice you used
    - Your Linux distribution
    - Your desktop environment
    - Are you using Wayland or X11?
    - How did you install LinOffice (Flatpak, manual install, legacy quickstart script)?
    - If you did NOT install the Flatpak version of LinOffice, how did you install Podman-Compose (e.g. from your distro's repo or via pip) and FreeRDP (e.g. from your distro's repo or as Flatpak from Flathub)?
