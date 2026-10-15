# LinOffice - Microsoft Office launcher for Linux

<p align="center">
  <a href="https://eylenburg.github.io/linoffice/io.github.eylenburg.LinOffice.flatpakref"><img alt="Click here to install LinOffice with Flatpak" height="64" src="https://img.shields.io/badge/Click%20here%20to%20install-Flatpak-0D597F?style=for-the-badge&logo=flatpak&logoColor=white"></a>
</p>

<p align="center">The button installs LinOffice with Flatpak. It opens in GNOME Software, KDE Discover, or another Flatpak software center. You also need <a href="#flatpak">Podman</a>.</p>

**LinOffice enables you to run Microsoft Office applications in Linux.** In the background, it runs a virtual machine with Windows and Office installed which is then accessed via FreeRDP. LinOffice's aim is to be a "1-click" setup for Microsoft Office in Linux.

By default, **Microsoft Office 2024** (Home & Retail) is installed, containing Word, Excel, Powerpoint, Onenote and Outlook. If you have a **Microsoft Office 365** subscription you can log in with your Microsoft account and it should upgrade from 2024 to 365.

The project utilises [Winapps](https://github.com/winapps-org/winapps), [Dockur/Windows](https://github.com/dockur/windows), FreeRDP, Podman, and Qemu. You *can* run LinOffice alongside WinApps - all the names and RDP ports have been changed to avoid conflicts between the two.

# Screenshot

![ScreenShot](screenshot.png).
<img src="https://raw.githubusercontent.com/eylenburg/linoffice/refs/heads/main/screenshot2.png" width="394" height="398" />

# Features

- [x] **Automatic non-interactive setup**
- [x] **Run Microsoft Office apps as if they were native Linux apps**
- [x] **Office apps have access to /home folder and Linux clipboard**
- [x] Run Publisher or Access, if manually installed by user
- [x] Quickly access useful tools such as Powershell, Command Prompt, Windows Explorer, Registry Editor, Office Language Settings
- [x] Run a full Windows session via RDP or VNC
- [x] Automatic suspension of the Windows container when inactive, resume when starting an Office app
- [x] Automatic deletion of Office lock files (like `~$file.docx`)
- [x] Force time sync in Windows after Linux host wakes up from sleep, to avoid time drift (time zone is always set to UTC for simplicity)
- [x] Automatic detection of language, date format, thousand and decimal separator, currency symbol, keyboard layout etc
- [x] Toggle settings such as display scaling, auto-suspend on/off,  network on/off (to prevent Windows and Office from "phoning home") 
- [x] Circumvent geo-blocking for the Office installation
- [x] Install updates for Windows and Office
- [x] Tidy Quick Access pane in Windows File Explorer
- [x] Automatically debloats Windows and disables telemetry and ads, using [Win11Debloat](https://github.com/Raphire/Win11Debloat/)
- [x] Troubleshooting functions e.g. force cleanup of Office lock files, recreate .desktop files for the Office apps, reboot the Windows container, container health check

<details>
<summary><strong>Planned features</strong></summary>

### Planned features

- [ ] Logo to use for the GUI
- [ ] Translations for the GUI
- [x] Flatpak, published from this repository (not Flathub). It bundles FreeRDP, podman-compose, and PySide6. Podman stays installed on the system. See [Installation](#installation).
- [ ] AppImage


### Nice to have but lower priority

- [ ] ARM support (should be possible as both Windows and Office have ARM versions)
- [ ] Support for non-core Office apps (e.g. Access, Publisher, Visio)
- [ ] Support for older Office versions (e.g. 2016, 2019, 2021)

</details>

### Comparison with other options to run Microsoft Office in Linux

| |Linoffice|Winapps|Windows VM|Crossover|Wine|
|:----|:----|:----|:----|:----|:----|
|Latest supported Office versions|**2024** (installed by default) and **365** (upgrade after login)|All up to **2024** and **365**|All up to **2024** and **365**|All up to **2016**, **365** may or may not work ([List](https://www.codeweavers.com/compatibility?browse=&app_desc=&company=&rating=&platform=&date_start=&date_end=&name=microsoft+excel&search=app#cxlinux))|All up to **2016** ([List](https://appdb.winehq.org/objectManager.php?sClass=application&iId=11))|
|Office components|All, but installed by default: Excel, Word, Powerpoint, OneNote, Outlook|All: Excel, Word, Powerpoint, OneNote, Outlook, Access, Publisher, Visio, Project|All: Excel, Word, Powerpoint, OneNote, Outlook, Access, Publisher, Visio, Project|Excel, Word, Powerpoint|Excel, Word, Powerpoint|
|Bugginess|🐞 Issues when moving or resizing Office windows or when working with multiple open Office windows|🐞 Issues when moving or resizing Office windows or when working with multiple open Office windows|✅ No bugs, working just as Microsoft intended|🐞🐞 UI bugs, crashes, failing to save files, certain features may not work|🐞🐞🐞 UI bugs, crashes, failing to save files, certain features may not work, installation or activation may fail|
|Cost|Free|Free|Free|$60/€60/£60 for Crossover|Free|
|Activation with MAS|✅Yes|✅Yes|✅Yes|❌No|❌No|
|RAM & CPU use|🔴 Significant (Windows VM)|🔴 Significant (Windows VM)|🔴 Significant (Windows VM)|🟢 Modest|🟢 Modest|
|Integration into Linux|✅ App launchers<br />✅ File associations<br />✅ Access to `/home`<br />✅ Shared clipboard|✅ App launchers<br />✅ File associations<br />✅ Access to `/home`<br />✅ Shared clipboard|❌ App launchers<br />❌ File associations<br />⚠️ Access to `/home`\*<br />⚠️ Shared clipboard\*|✅ App launchers<br />✅ File associations<br />✅ Access to `/home`<br />✅ Shared clipboard|✅ App launchers<br />✅ File associations<br />✅ Access to `/home`<br />✅ Shared clipboard|
|Installation & setup|🟢 Easy:<br />1. Install Podman<br />2. Install the LinOffice Flatpak<br />3. Open LinOffice|🔴 Complicated:<br />1. Install dependencies<br />2. Set up Windows VM<br />3. Install Office in VM<br />4. Create config file<br />5. Run WinApps installer|🟡 Medium:<br />1. Install dependencies<br />2. Set up Windows VM<br />3. Install Office in VM|🟢 Easy:<br />1. Install Crossover<br />2. Download Office installer and open it in Crossover|🔴 Complicated; installation and activation will fail without arcane workarounds\**, no automatic creation of `.desktop` files|

\*requires manual setup, e.g. VirtIO-win and WinFSP or Samba when using Virt-Manager/Qemu, or Virtualbox Guest Additions for Virtualbox

\**PlayOnLinux 4 has install scripts for Office 2016 and below that may or may not work

# Installation

All Linux distributions are supported. The button at the top of this page is the easiest install. The steps further down are for installing the files from this repository yourself.

**Hardware requirements:**
- Enough resources for the Windows virtual machine (up to 4 GB RAM, 64 GB storage, and 4 CPU cores). Setup checks for at least 8 GB RAM and 64 GB free storage before it continues.
- Virtualization support (KVM)
- An x86_64 CPU (ARM is not supported yet)
- A fast Internet connection. Setup downloads several GB from Microsoft.

## Flatpak

Use this unless you want to run LinOffice from a folder you downloaded yourself.

The Flatpak includes FreeRDP, podman-compose, Python, and PySide6. Two things still have to be installed on your system:

- **Flatpak**, if it is not already there
- **Podman**

Office itself is not inside the Flatpak. The first time you open LinOffice, it downloads Windows and Microsoft Office (about 8 GB) and installs them. You need your own Office license.

**Click the button at the top of this page.** The same file is [io.github.eylenburg.LinOffice.flatpakref](https://eylenburg.github.io/linoffice/io.github.eylenburg.LinOffice.flatpakref). Your software center adds the LinOffice repository and installs LinOffice.

From a terminal, adding the repository and installing LinOffice is one command:

```bash
flatpak remote-add --if-not-exists --user linoffice https://eylenburg.github.io/linoffice/index.flatpakrepo && flatpak install --user linoffice io.github.eylenburg.LinOffice
```

Then open **LinOffice** from your application menu. The Office apps appear in the menu after setup finishes. The package already includes those launchers, so setup does not write extra `.desktop` files.

Updates for the LinOffice application come from this Flatpak repository. See [Updating](#updating). Removing the Flatpak does not delete the Windows virtual machine. See [Uninstall](#uninstall).

## Install from this repository

Do these steps in order. Step 3 is optional.

### 1. Install the dependencies

You need:

- **Podman**
- **podman-compose**
- **FreeRDP 3** (the `xfreerdp3` command)
- **Python 3** and **PySide6**, so the LinOffice window can run the setup

On Debian and Ubuntu, PySide6 is split into extra packages. The commands below include `python3-pyside6.qtwidgets` and `python3-pyside6.qtuitools`, which the window needs in order to load its interface.

>[!WARNING]
>FreeRDP 3.23 does not work with LinOffice. If your distribution ships 3.23, downgrade to 3.22 or upgrade to a newer version.

Copy the command for your distribution.

**Debian 13 and newer**

```bash
sudo apt install podman podman-compose freerdp3-x11 python3 python3-pyside6 python3-pyside6.qtwidgets python3-pyside6.qtuitools
```

**Ubuntu 24.10 and newer**

```bash
sudo apt install podman podman-compose freerdp3-x11 python3 python3-pyside6 python3-pyside6.qtwidgets python3-pyside6.qtuitools
```

FreeRDP 3 is available from Ubuntu 24.04. PySide6 is available from Ubuntu 24.10. On Ubuntu 24.04, install `podman`, `podman-compose`, and `freerdp3-x11` with `apt`, then install PySide6 [with pip](https://pip.pypa.io/en/stable/installation/). Debian 12 and Ubuntu older than 24.04 do not include FreeRDP 3. Use backports, or install FreeRDP from [Flathub](https://flathub.org/apps/com.freerdp.FreeRDP) and give that Flatpak access to your home folder.

**Fedora**

```bash
sudo dnf install podman podman-compose freerdp python3 python3-pyside6
```

On Fedora Atomic (Silverblue, Kinoite, and similar), Podman and Python 3 are already installed. Run `rpm-ostree install podman-compose freerdp python3-pyside6`, then reboot.

**openSUSE**

```bash
sudo zypper install podman podman-compose freerdp python3 python3-pyside6
```

**Arch Linux**

```bash
sudo pacman -S --needed podman podman-compose freerdp python pyside6
```

If a package is missing from your repositories, podman-compose and PySide6 can be installed [with pip](https://pip.pypa.io/en/stable/installation/). FreeRDP can be installed from [Flathub](https://flathub.org/apps/com.freerdp.FreeRDP). Give that Flatpak access to your home folder.

### 2. Download LinOffice

This downloads the current repository and unpacks it to `~/.local/bin/linoffice`. It needs `curl` and `unzip`. It stops if that folder already exists, so it will not overwrite an install you already have.

```bash
mkdir -p "$HOME/.local/bin" && curl -fL "https://github.com/eylenburg/linoffice/archive/refs/heads/main.zip" -o /tmp/linoffice.zip && unzip -qo /tmp/linoffice.zip -d /tmp && rm -f /tmp/linoffice.zip && if [ -e "$HOME/.local/bin/linoffice" ]; then echo "Stop: $HOME/.local/bin/linoffice already exists. Move it aside, then run this again. The download is in /tmp/linoffice-main."; else mv /tmp/linoffice-main "$HOME/.local/bin/linoffice" && echo "LinOffice is in $HOME/.local/bin/linoffice"; fi
```

A tagged release is also fine. Download the zip from the [releases page](https://github.com/eylenburg/linoffice/releases), unpack it, and put the folder at `~/.local/bin/linoffice`.

### 3. Optional: change settings before the first start

Skip this step to accept the defaults (Windows 11 Pro, 4 GB RAM, 4 CPU cores, 64 GB disk).

If you do want to change something, edit the templates **before** you start LinOffice:

- `~/.local/bin/linoffice/config/compose.yaml.default` — Windows version, RAM, CPU cores, disk size
- `~/.local/bin/linoffice/config/linoffice.conf.default` — display scaling, auto-suspend, extra FreeRDP flags

The first start copies those templates into `~/.config/linoffice/`. After that, change `compose.yaml` and `linoffice.conf` in that folder. An older install that already has those files in `config/` next to `linoffice.sh` keeps using that folder.

<details><summary><strong>Don't want to use Windows 11?</strong></summary>

Windows 11 Pro is the default. Windows 10 is a bit snappier. To install it, replace `VERSION: "11"` with `VERSION: "10"` in `config/compose.yaml.default` before the first start.

Mainstream support for Windows 10 ended in October 2025. After installation you can use Microsoft Activation Scripts (MAS) to receive Extended Security Updates until 2028. Windows 10 LTSC 2021 still receives security updates until 2032. For that image, set `VERSION` to `https://archive.org/download/Windows10EnterpriseLTSC202164Bit/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso`.

LinOffice cannot ship a ready-made virtual machine. Redistributing Windows and Office is not allowed. Setup downloads Windows from Microsoft, installs it, then downloads and installs Office.

</details>

### 4. Start LinOffice

```bash
cd "$HOME/.local/bin/linoffice" && python3 gui/linoffice.py
```

This opens the installer. It downloads about 8 GB and installs Windows, then Office. On a 2023 mid-range laptop with a 250 Mbps connection, that took about 15 minutes (about 3 minutes to download Windows, 8 minutes to install it, and 4 minutes to download and install Office).

When it finishes, Word, Excel, PowerPoint, OneNote, Outlook, and LinOffice are in your application menu.

If setup succeeds, please [share your system setup](https://github.com/eylenburg/linoffice/issues/16). That helps show where LinOffice works without extra steps.

## Updating

**Flatpak.** LinOffice updates come from the LinOffice Flatpak repository. Update it in your software store, or run:

```bash
flatpak update io.github.eylenburg.LinOffice
```

The updater inside the LinOffice window does not update a Flatpak.

**Installed from this repository.** Use the updater in the LinOffice window. You can also download the newest version and copy its files over the old folder. Do not delete the old folder first. Setup creates files that the existing install still needs, and an older install may keep its configuration next to `linoffice.sh`.

**Windows and Office.** These update on their own. The LinOffice window also has an update action for them. From a terminal, that is `./linoffice.sh update`.

**LinOffice v1.0.7 and older.** If the Windows virtual machine was created by one of those versions, copy the files from `config/oem` into `C:\OEM` in the virtual machine and overwrite the old copies. In a full Windows session (`./linoffice.sh windows`), your Linux home folder is `\\tsclient\home`. On a current install, `./linoffice.sh refresh-oem` copies the OEM scripts into the existing virtual machine for you.

## Uninstall

**Flatpak.** Remove LinOffice in your software store, or run:

```bash
flatpak uninstall io.github.eylenburg.LinOffice
```

That removes the application only. The Windows virtual machine stays until you delete the Podman container `LinOffice` and the volume `linoffice_data`.

**Installed from this repository.** Open LinOffice, open **Troubleshooting**, and click **Uninstall**.

<details><summary>Where are the files saved?</summary>

- **App files:** the folder that contains `linoffice.sh`. An install from this repository is usually `~/.local/bin/linoffice`. A Flatpak keeps the application under `/app`, which is removed with the Flatpak itself.
- **Config:** `compose.yaml`, `linoffice.conf`, and the working `oem/` directory. A new install uses `${XDG_CONFIG_HOME:-~/.config}/linoffice`. If `config/compose.yaml` or `config/linoffice.conf` already exists next to `linoffice.sh`, that folder keeps being used.
- **Data:** logs, setup progress, `registry_override.conf`, and the suspend marker. If `~/.local/share/linoffice` already exists, it stays the data directory. Otherwise the directory is `${XDG_DATA_HOME:-~/.local/share}/linoffice`.
- **Desktop files:** `${XDG_DATA_HOME:-~/.local/share}/applications`, unless `LINOFFICE_APPLICATIONS_DIR` is set. The Flatpak exports its own launchers and does not write these files.
- **Windows VM:** Podman project name `linoffice`, container `LinOffice`, volume `linoffice_data` (`podman rm -f LinOffice && podman volume rm linoffice_data`).
- Path overrides: `LINOFFICE_PREFIX`, `LINOFFICE_CONFIG_DIR`, `LINOFFICE_DATA_DIR`, `LINOFFICE_APPLICATIONS_DIR`. `lib/paths.sh` and `lib/paths.py` resolve them.

</details>

# Usage

### Starting Office applications

After installation, you should find the launchers for the Office applications in your app menu.

### Opening Office files

You can open files from your file manager with Right-click -> Open with. 

### Using the GUI

You will find a launcher for "LinOffice" in your app menu.

<details>
<summary><strong>Using the terminal</strong></summary>

Most people can ignore this and use the LinOffice window and the Office launchers in the application menu.

Run the commands below from the folder that contains `linoffice.sh` (usually `~/.local/bin/linoffice`). To run them from anywhere, add an alias and change the path if your copy lives somewhere else:

```bash
echo "alias linoffice=\"$HOME/.local/bin/linoffice/linoffice.sh\"" >> ~/.bashrc && source ~/.bashrc
```

After that, `linoffice` means the same thing as `./linoffice.sh`.

- `./linoffice.sh [excel|word|powerpoint|onenote|outlook]`: open one of the Office applications
- `./linoffice.sh manual [msaccess.exe|mspub.exe]`: open Access or Publisher, if you installed them yourself (they are not in the default Office install)
- `./linoffice.sh manual [explorer.exe|regedit.exe|powershell.exe|cmd.exe]`: open a Windows program that is on the Windows PATH
- `./linoffice.sh manual "C:\Program Files\Microsoft Office\root\Office16\SETLANG.EXE"`: open any program by its full path (this example is Office Language Preferences)
- `./linoffice.sh windows`: show the whole Windows desktop in an RDP session
- `./linoffice.sh update`: run the Windows and Office update script
- `./linoffice.sh reset`: close FreeRDP, clean up Office lock files, and reboot the Windows virtual machine
- `./linoffice.sh --startcontainer`: start the Windows container and do nothing else
- `./linoffice.sh --stopcontainer`: shut the Windows container down and leave its data in place
- `./linoffice.sh cleanup [--full|--reset]`: delete Office lock files (such as `~$file.xlsx`) in the home folder and on removable media; `--full` deletes them regardless of age, `--reset` resets the last-cleanup timestamp
- `./linoffice.sh refresh-oem`: copy the current OEM scripts into an existing Windows virtual machine (`C:\OEM`, and `TimeSync.ps1` into the Windows directory) without reinstalling Windows

`setup.sh` can also be run on its own:

- `./setup.sh --desktop`: only (re)create the application launchers. The Flatpak already includes them.
- `./setup.sh --firstrun`: run the RDP and Office checks again, after the Windows virtual machine has finished installing
- `./setup.sh --installoffice`: only run the Office installation script, when Windows is installed but Office is not
- `./setup.sh --healthcheck`: check that Podman is available, the required programs are present, and the container is healthy (the window has a button for this)
- `./setup.sh --refresh-oem`: same as `./linoffice.sh refresh-oem`

</details>

### Office activation 

You will need an Office 2024 license key or Office 365 subscription to use Office. During the first 5 days after installation, you can use Office without activation by clicking on "I have a product key" and then on the "X" of the window where you are supposed to enter your product key.

The **Microsoft Activation Scripts (MAS)** will also work if you have, let's say, trouble with activation - just run `./linoffice.sh manual powershell.exe` from the script's directory to open a Powershell window where you can then paste the command to run MAS. 

### Printing

The Office application are running in a virtual machine with Windows, meaning that the printers you have set up in Linux are not available. There are two options if you need to print from Office:

1. Print to PDF / export to PDF and then print the PDF from Linux
2. If you have a network printer you can easily install it in Windows. Find out its local IP address (e.g. with `lpstat -v`), then open the Windows VM (e.g. via the Tools menu in LinOffice), then Settings -> Printers and Scanners -> Add Device -> Add a new device manually -> Add printer using IP Address


# Troubleshooting

<details>
<summary><strong>Problems with the setup</strong></summary>

Work through these checks in order. Stop as soon as Word and Excel open from your application menu.

Run `./setup.sh` from the folder that contains it. On an install from this repository that is usually `~/.local/bin/linoffice`. Logs are in the LinOffice data directory. On an existing install that is still `~/.local/share/linoffice`. On a new install it is `${XDG_DATA_HOME:-~/.local/share}/linoffice`.

#### 1. Can you log in to the virtual machine?

Open http://127.0.0.1:8006 in a browser. The password is `MyWindowsPassword`.

- **The page does not load, or Windows will not let you log in.** Read `windows_install.log` in the data directory. That log is from the Windows download and install.
- **You can log in, but Microsoft Office is not installed.** Install Office yourself inside the virtual machine. Then create an empty file, not a folder, named `success` in `C:\OEM`. Sign out from the Start menu. Do not shut Windows down.
- **You can log in and Office is installed.** Sign out. A login in the browser blocks RDP until you sign out.

From the LinOffice folder, run:

```bash
./setup.sh --firstrun
```

If the Office apps are now in your menu, you are done.

#### 2. Can Linux connect with FreeRDP?

Stay signed out of the browser session from step 1.

Use whichever FreeRDP command exists on your system:

| Installed as | Command to use below |
| --- | --- |
| `xfreerdp3` | `xfreerdp3` |
| `xfreerdp` | `xfreerdp` |
| Flathub FreeRDP | `flatpak run --command=xfreerdp com.freerdp.FreeRDP` |

The LinOffice Flatpak brings its own FreeRDP. These three commands are for an install from this repository.

Replace `xfreerdp3` if your command is different. Close each window if it opens.

1. Desktop: `xfreerdp3 /cert:ignore /u:MyWindowsUser /p:MyWindowsPassword /v:127.0.0.1 /port:3388`
   You should see the Windows desktop.
2. File Explorer: add `/app:program:explorer.exe` to that command.
   You should see Windows File Explorer.
3. Excel: add `/app:program:excel.exe` instead.
   You should see Excel.

If a window does not open, the problem is the connection or the Office install. Fix that before continuing. If all three open, run `./setup.sh --firstrun` again.

#### 3. Office opens from FreeRDP, but setup still stops

1. Open `setup_progress.log` in the data directory.
2. If that file does not already contain the line `office_installed`, add it at the end.
3. Run `./setup.sh --desktop`.

Word, Excel, and LinOffice should then be in your application menu. A Flatpak already includes those launchers, so this step does not apply to it.

#### 4. Still stuck

Please [open a bug report](https://github.com/eylenburg/linoffice/issues) and include:

- `windows_install.log` and `setup_output.log` from the data directory
- `setup.log`, `setup_office.log`, and `setup_rdp.log` from `C:\OEM` in the virtual machine, if they exist. The browser session does not share the clipboard with Linux, so a screenshot is enough.
- LinOffice version, Linux distribution, desktop environment, Wayland or X11, and how Podman, podman-compose, and FreeRDP were installed

</details>

### Logging in to Microsoft

Some users have reported the issue that when they try to log in to Microsoft (e.g. in order to activate Microsoft 365) they login window would hang and not progress. The workaround for this access a "full" RDP session (in GUI: `Tools` -> Access Windows desktop `via RDP`; in CLI: `./linoffice.sh windows`). You should be able to log in in this session. Afterwards, you can close the window and use LinOffice as usual.

### Window management

In my experience, window management can be wonky, particularly if you're using Wayland instead of X11 or if you're using multiple monitors.

A potential solution for multimonitor issues could be to open `linoffice.conf` in the config directory (see "Where are the files saved?") and in the last line (`RDP_FLAGS`) adding `/multimon`. This is supposed to add multimonitor support to FreeRDP, but a FreeRDP bug may result in a black screen, in which case you should revert this change. Another potential solution is to add `/monitors:1` or `/monitors:0` to the `RDP_FLAGS` line in `linoffice.conf`, where the monitor ID is based on your "desired" monitor that the apps will run in;  while it restricts the Office windows to this desktop you should avoid the windows being unresponsive or disappearing and resizing works properly within this monitor.

<details><summary>Examples</summary>
    
- Using multiple Office documents/windows can be tricky. For example, opening an Office window might not open until you start it a second time and you may or may not get two windows then. Or, opening a new Office window might close already open ones. Don't panic - your documents are not lost. Just launch the latest Office window again and you should now see both the new one and old one. Sometimes, opening a new windows might also have the quirk that the focus is on the older Office window which is sitting in the background. The solution is to minimize the old one so that the focus is gone..
- Moving and resizing windows does not always work well, particularly on setups with multiple monitors. Most desktop environments use the shortcut "Meta or Alt + Left-Click" for moving a window and and "Meta or Alt + Right-Click" for resizing; this is a very reliable to move around or resize Office windows.
- Dialog boxes (commonly encountered when working with charts in Excel for example) spawn as new, separate windows, but they can sometimes appear behind the main window and at the same time block the main window until you close the dialog box.
- Dialog windows may also have a bad size, e.g. the "edit chart data" window in Excel often cuts off the "OK" at the bottom. The solution, again, is to resize the window using a shortcut like "Meta or Alt + Right-Click" in order to access the "OK" button.

</details>

I believe that these are FreeRDP issues. If it becomes too bad, you can try `./linoffice.sh reset` to kill all FreeRDP processes and reboot the Windows VM - but be aware that you will lose any unsaved Office documents this way.

### Wrong keyboard layout

Setup tries to copy your Linux keyboard layout into Windows. If it cannot detect the layout, or cannot match it to a Windows layout, Windows uses the US layout. Try the LinOffice setting first.

**1. Choose the layout in LinOffice**

Open LinOffice and pick the layout in **Settings**.

To set the same thing without the window, edit `linoffice.conf` in the config directory:

- New install: `~/.config/linoffice/linoffice.conf`
- Older install that already had its config next to the script: `config/linoffice.conf` in the LinOffice folder

Find this line:

```
RDP_KBD=""
```

Look up your layout in [`config/languages.csv`](https://github.com/eylenburg/linoffice/blob/main/config/languages.csv). The first column is the FreeRDP code. Two examples:

```
RDP_KBD="/kbd:layout:0x0809"
```

United Kingdom.

```
RDP_KBD="/kbd:layout:0x0407"
```

Germany.

**2. Set the layout inside Windows**

Use this when the setting above has no effect.

1. Open a full Windows session. In LinOffice, use **Tools** and open the Windows desktop via RDP. From a terminal: `./linoffice.sh windows`. Or open http://127.0.0.1:8006 in a browser (password `MyWindowsPassword`). Sign out when you leave the browser session, or a later RDP connection can fail.
2. In Windows Settings, set the keyboard layout.
3. Open Command Prompt and run:

```
REG ADD "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout" /v IgnoreRemoteKeyboardLayout /t REG_DWORD /d 1
```

That tells Windows to keep its own layout instead of the layout sent by FreeRDP.

**More than one Linux layout**

Switching layouts in Linux, for example between a Latin and a non-Latin script, is not copied into Windows. A workaround is described in [this WinApps comment](https://github.com/winapps-org/winapps/issues/43#issuecomment-3227432458).

### Orphaned lock files

There is a strange issue that Microsoft Office will not clean up the lock files in the Linux /home folder. If you open, say, "Book1.xlsx" then Excel will create a file called "~$Book1.xlsx" which is just a few bytes in size and serves the purpose of "locking" this file so other users can't edit it at the same time. Normally these files should be deleted when you close the file, but this doesn't happen for whatever reason. The /home folder is mounted by FreeRDP and appears in Windows as a network drive accessed via RDP Drive Redirection (RDPDR).

LinOffice searches and deletes these lock files when the last Office process is closed. If this fails for any reason you can manually delete all lock files by running `./linoffice.sh cleanup --full` or by using the button in the "Troubleshooting" window.

<details><summary>How to hide these lock files in KDE's Dolphin file manager</summary>

1. Go to KDE `System Settings` -> `Default Applications` -> `File Associations`, then search for the mime type corresponding to .xlsx (in this case it's called `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`). Select the existing filename pattern (`*.xlsx`) and click `- Remove` and then click `+ Add` and enter `[!~][!$]*.xlsx`. Do the same for docx and pptx, and, if you use them, odt, ods, odp, docm, xlsm and pptm. 

(By default files starting with `~$` have the mime type `application/x-trash`. By making the above change, a file like "~$Book1.xlsx" will be seen as a trash file rather than a spreadsheet.)

2. Open Dolphin, go to `Configure Dolphin` -> `View` and check `[x] Also hide backup files when hiding files`. 

("Backup files" in this case actually refers to all files with the `application/x-trash` mime type.)

</details>

### Changing the password or username for the Windows virtual machine

At the moment, these are hardcoded to `MyWindowsUser` and `MyWindowsPassword` in several files. However, once the setup finishes and you are able to successfully start Office applications via LinOffice, you can change the password or username if you wish to do so.

First, change the password and/or username in Windows. To do this you need to access the "full" Windows session, either via RDP (`./linoffice.sh windows`) or VNC (`127.0.0.1:8006` in the browser, password is `MyWindowsPassword`; log out from Windows when you're done).

Then, find the file `linoffice.sh`, which is most likely located in `~/.local/bin/linoffice/` and edit these lines (currently in line 60-61):

```
RDP_USER="MyWindowsUser"
RDP_PASS="MyWindowsPassword"
```

Make sure they match your newly set Windows password and username.

>[!WARNING]
>Please note that the setup script (`setup.sh`) currently still expects the original credentials, so if you need to run it again for any reason it may fail after you have changed the password or username.

# For developers

These are the files that are part of LinOffice and what they do. Paths are from the repository root. Setup creates `compose.yaml`, `linoffice.conf`, and `regional_settings.reg` in the config directory.

<details><summary>File list</summary>

- `lib/paths.sh` and `lib/paths.py`: Decide the application directory, the writable config directory, and the data directory. See `lib/README.md`.
- `setup.sh`: Install script. Checks that requirements and dependencies are present, runs `config/locale_reg.sh` and `config/locale_lang.sh`, downloads Windows and creates the virtual machine, installs Office, connects with RDP, runs `FirstRDPRun.ps1`, and creates application launchers. Flags: `--desktop`, `--firstrun`, `--installoffice`, `--healthcheck`, `--refresh-oem`.
- `linoffice.sh`: Main script. Starts, resumes, or pauses the Podman container and runs the FreeRDP command for Office and the other Windows programs. Also implements `refresh-oem`, which copies the current OEM scripts into an existing virtual machine.
- `uninstall.sh`: Asks before it deletes anything. Removes the application launchers, offers to remove packages listed in `installed_dependencies` when that file exists, offers to remove a Python virtual environment, offers to remove the `LinOffice` container and the `linoffice_data` volume, and offers to delete the data directory and a config directory that lives outside the application folder. It deletes the application folder unless that folder is a system location such as `/usr`, `/app`, or `/nix/store`.
- `updater.py`: Compares `CURRENT_VERSION` with the latest non-draft, non-prerelease GitHub release and replaces the application files. It keeps an existing `compose.yaml`, `linoffice.conf`, and `oem/registry/regional_settings.reg`. The Flatpak does not use this updater.
- `gui/linoffice.py`: Starts `gui/installer/installer.py` when setup is not finished, and `gui/mainwindow.py` when the `LinOffice` container exists and `setup_progress.log` contains `office_installed`. If those two facts disagree, it asks which one to open.
- `gui/mainwindow.py`: The main window: Office launchers, settings, tools, troubleshooting, and the in-app updater.
- `gui/splash.py`: Small window shown while the Windows container is starting. `linoffice.sh` launches it.
- `gui/main.ui`, `gui/settings.ui`, `gui/tools.ui`, `gui/troubleshooting.ui`: Qt Designer files for the main window.
- `gui/installer/installer.py`: Graphical installer. It runs `setup.sh` and can abort by running `remove_container.sh`.
- `gui/installer/remove_container.sh`: Removes the `LinOffice` container and the `linoffice_data` volume when installation is aborted. A missing container or volume counts as success.
- `gui/installer/welcome.ui`, `gui/installer/install_progress.ui`, `gui/installer/done.ui`: Qt Designer files for the installer.
- `apps/desktop/*.desktop`: Launcher templates for LinOffice and the Office apps. `setup.sh` replaces `/PATH/` with the install directory. The Flatpak exports its own copies.
- `apps/word/`, `apps/excel/`, `apps/powerpoint/`, `apps/onenote/`, `apps/outlook/`: Each has `icon.svg` and `info.txt` (display name, Windows executable, categories, and MIME types) used to build the launchers.
- `config/locale_lang.sh`: Copies `compose.yaml.default` and `linoffice.conf.default` into the config directory, then writes the host language, region, and keyboard layout into those copies. It does not edit the templates in place.
- `config/compose.yaml.default`: Template for the Podman Compose file. The generated `compose.yaml` creates the Windows container. Users can change the Windows version, RAM, CPU, and disk size here before the first start.
- `config/linoffice.conf.default`: Template for LinOffice settings. The generated `linoffice.conf` is read by `linoffice.sh` for auto-pause, keyboard layout, display scaling, and extra FreeRDP flags.
- `config/locale_reg.sh`: Reads decimal and thousand separators, the currency symbol, and the date format from the host, and writes `oem/registry/regional_settings.reg` in the config directory. `install.bat` imports that file inside Windows.
- `config/languages.csv`: Keyboard layouts. The first column is the FreeRDP layout code.
- `config/oem/install.bat`: Runs once at the end of the Windows installation, before the desktop is shown. Imports `linoffice.reg` for the system, and `regional_settings.reg` plus `explorer_settings.reg` for the default user. Copies `NetProfileCleanup.ps1` and `TimeSync.ps1` to the Windows directory and creates scheduled tasks for them. Sets the time zone to UTC, runs Win11Debloat, schedules `InstallOffice.ps1` for the next logon, turns on a one-time automatic logon, and reboots.
- `config/oem/OfficeConfiguration.xml`: Office Deployment Tool configuration: which Office apps to install.
- `config/oem/InstallOffice.ps1`: Started by `install.bat` after the reboot. Turns automatic logon back off, downloads the Office Deployment Tool, installs Office with `OfficeConfiguration.xml`, creates the empty file `C:\OEM\success`, and restarts Windows. `setup.sh` treats that file as the signal that Office is installed.
- `config/oem/NetProfileCleanup.ps1`: Scheduled task created by `install.bat`. Renames the current network profile to LinOffice and deletes the others.
- `config/oem/TimeSync.ps1`: Scheduled task created by `install.bat`. Syncs the clock when it finds `sleep_marker` at `\\tsclient\linoffice\sleep_marker`, or, for an existing virtual machine, at `\\tsclient\home\.local\share\linoffice\sleep_marker`. `linoffice.sh` creates that file after the Linux host wakes from sleep. `linoffice_paths.txt` can name another path.
- `config/oem/linoffice_paths.txt`: Optional UNC hints (`SleepMarker`, `Success`, `RegistryOverride`) copied into the working OEM directory. Guest scripts use them when `C:\OEM\linoffice_paths.txt` is present.
- `config/oem/FirstRDPRun.ps1`: Called by `setup.sh` over RDP. If `C:\OEM\success` exists, writes the Linux `success` marker (on the LinOffice share, or the older home-folder share) and runs `QuickAccess.ps1`.
- `config/oem/QuickAccess.ps1`: Unpins the default Quick Access folders in File Explorer and pins the Linux home folder (`\\tsclient\home`).
- `config/oem/RegistryOverride.ps1`: Applies localization changes made in the LinOffice window. It reads `registry_override.conf`, which `mainwindow.py` writes, and updates the Windows registry.
- `config/oem/UpdateWindows.ps1`: Updates Windows and Microsoft Office. Called from the LinOffice window or by `./linoffice.sh update`.
- `config/oem/dns_off.bat`: Points the Windows Ethernet adapter at `127.0.0.1`, so name lookups fail. Direct connections to an IP address still work. Called from the LinOffice window or from `linoffice.sh`.
- `config/oem/dns_on.bat`: Sets that adapter's DNS back to DHCP.
- `config/oem/registry/explorer_settings.reg`: File Explorer settings, including showing file extensions. Applied by `install.bat` to the default user.
- `config/oem/registry/linoffice.reg`: Windows settings such as allowing any program to run as a RemoteApp, disabling automatic logon, allowing long paths, and stopping Windows Update from rebooting the machine. Applied by `install.bat`.
- `.flatpak/io.github.eylenburg.LinOffice.yml`: Flatpak manifest. It bundles FreeRDP, podman-compose, and PySide6, and calls Podman on the host.
- `.flatpak/io.github.eylenburg.LinOffice.metainfo.xml`: AppStream metadata for the Flatpak.
- `.flatpak/io.github.eylenburg.LinOffice.flatpakref`: One-step install file. The publish workflow writes it from the signing key and publishes it at `https://eylenburg.github.io/linoffice/io.github.eylenburg.LinOffice.flatpakref`. It names the app, the `master` branch, and that repository.
- `.flatpak/icons/`: Icons exported with the Flatpak.
- `.github/workflows/flatpak-repo.yml`: Builds the Flatpak on a version tag or a manual run, and publishes the repository to GitHub Pages.

</details>

# Legal information

This project is licensed under the GNU AGPL 3. 

The main script (`linoffice.sh`) is forked from [Winapps](https://github.com/winapps-org/winapps), AGPL license.

The Windows VM is set up using the [Dockur/Windows](https://github.com/dockur/windows) OCI container, MIT license.

Windows and Office are directly downloaded from Microsoft. This project contains only open-source code and does not distribute any copyrighted material. Any product keys found in the code are just generic placeholders provided by Microsoft for trial purposes. You will need to provide your own product keys to activate Windows and Office.
