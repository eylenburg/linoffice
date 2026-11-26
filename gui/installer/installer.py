import sys
import re
import json
import subprocess
import os
import signal
import time
from pathlib import Path
from typing import TypeVar

_PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))
from lib.paths import SETUP_SCRIPT, read_data_path

from PySide6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout, QDialog, QLabel,
    QPushButton, QStackedWidget, QProgressBar, QTextEdit, QMessageBox, QFileDialog
)
from PySide6.QtUiTools import QUiLoader
from PySide6.QtGui import QTextCursor, QDesktopServices
from PySide6.QtCore import Qt, QFile, QTimer, QProcess, QProcessEnvironment, QIODevice, QUrl

_Widget = TypeVar("_Widget", bound=QWidget)


def _required_child(parent: QWidget, widget_type: type[_Widget], name: str) -> _Widget:
    widget = parent.findChild(widget_type, name)
    if widget is None:
        raise RuntimeError(f"Required installer widget {name!r} was not found.")
    return widget


def strip_ansi_codes(text: str) -> str:
    ansi_escape = re.compile(r'\x1b\[[0-9;]*m')
    return ansi_escape.sub('', text)


def ansi_to_html(text: str) -> str:
    # Escape HTML special chars
    text = text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

    # Regex to match ANSI color codes
    ansi_escape = re.compile(r'\x1b\[(?P<code>[0-9;]+)m')

    color_map = {
        '31': 'red', '0;31': 'red',
        '32': 'green', '0;32': 'green',
        '33': 'gold', '1;33': 'gold', '0;33': 'gold',
    }

    def repl(m: re.Match[str]) -> str:
        code = m.group('code')
        if code == '0':  # reset
            return '</span>'
        color = color_map.get(code)
        if color:
            return f'<span style="color:{color};">'
        return ''

    text = ansi_escape.sub(repl, text)

    # Remove trailing reset tags if any (optional)
    if text.endswith('</span>'):
        text = text.rstrip('</span>')

    # Now check if text (ignoring leading spaces and color spans) starts with one of the keywords
    # Strip HTML tags to check the raw text start
    raw_text = re.sub(r'<.*?>', '', text).lstrip()

    keywords = ('Step', 'INFO:', 'ERROR:', 'SUCCESS:')
    if any(raw_text.startswith(k) for k in keywords):
        text = f'<b>{text}</b>'

    return text

class Wizard(QWidget):
    def __init__(self) -> None:
        super().__init__()
        # UI files are loaded by a relative path.
        os.chdir(os.path.dirname(os.path.abspath(__file__)))
        self.setWindowTitle("LinOffice Installer")
        self.setMinimumSize(600, 400)

        self.stack = QStackedWidget()

        self.welcome_page = self.load_ui("welcome.ui")
        self.install_page = self.load_ui("install_progress.ui")
        self.done_page = self.load_ui("done.ui")
        self.progress_bar = _required_child(self.install_page, QProgressBar, "progressBar")
        self.terminal_output = _required_child(self.install_page, QTextEdit, "terminalOutput")
        self.copy_output_button = self.install_page.findChild(QPushButton, "copyOutputButton")
        self.abort_button = _required_child(self.install_page, QPushButton, "abortButton")

        self.stack.addWidget(self.welcome_page)  # index 0
        self.stack.addWidget(self.install_page)  # index 1
        self.stack.addWidget(self.done_page)     # index 2

        self.back_btn = QPushButton("Back")
        self.next_btn = QPushButton("Next")

        self.back_btn.setEnabled(False)
        self.back_btn.clicked.connect(self.prev_page)
        self.next_btn.clicked.connect(self.next_page)

        self.last_error_line: str | None = None

        nav_layout = QHBoxLayout()
        nav_layout.addWidget(self.back_btn)
        nav_layout.addStretch()
        nav_layout.addWidget(self.next_btn)

        layout = QVBoxLayout()
        layout.addWidget(self.stack)
        layout.addLayout(nav_layout)
        self.setLayout(layout)

        # For subprocess tracking
        self.process: QProcess | None = None
        self.current_step = 0
        QTimer.singleShot(0, self.prepare_flatpak_welcome)

    def load_ui(self, path: str) -> QWidget:
        loader = QUiLoader()
        file = QFile(path)
        if not file.open(QIODevice.OpenModeFlag.ReadOnly):
            raise OSError(f"Could not open installer UI file {path!r}: {file.errorString()}")
        widget = loader.load(file, self)
        file.close()
        return widget

    def prepare_flatpak_welcome(self) -> None:
        if not os.environ.get("FLATPAK_ID"):
            return
        label = self.welcome_page.findChild(QLabel, "welcomeLabel")
        if label is not None:
            label.setText(
                "Welcome to LinOffice!\n"
                "LinOffice is a Microsoft Office launcher for Linux.\n"
                "\n"
                "Requirements:\n"
                "1. Fast Internet connection (as you will need to download several GB from Microsoft)\n"
                "2. Modern hardware (at least 8 GB RAM, 64 GB free storage, >4 CPU cores, virtualization support)\n"
                "3. Podman is installed on the host. FreeRDP and podman-compose are included in this Flatpak.\n"
                "\n"
                "Click on Next to install Microsoft Office.\n"
            )
        podman_ok, detail = self._host_podman_status()
        if podman_ok:
            QMessageBox.information(
                self,
                "Podman",
                "This Flatpak needs Podman on the host computer. "
                "FreeRDP and podman-compose are already included.\n\n"
                "Podman is installed (%s)." % detail,
            )
            return
        QMessageBox.information(
            self,
            "Podman is required",
            "This Flatpak needs Podman on the host computer. "
            "FreeRDP and podman-compose are already included.\n\n"
            "%s\n\n"
            "Ubuntu/Debian: sudo apt update && sudo apt install podman\n"
            "Fedora/RHEL: sudo dnf install podman\n"
            "openSUSE: sudo zypper install podman\n"
            "Arch Linux: sudo pacman -S podman\n\n"
            "More options: https://podman.io/getting-started/installation" % detail,
        )

    def _host_podman_status(self) -> tuple[bool, str]:
        try:
            version = subprocess.run(
                ["podman", "--version"],
                capture_output=True,
                text=True,
                timeout=20,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            return False, "Podman could not be started (%s)." % exc
        if version.returncode != 0:
            message = (version.stderr or version.stdout or "").strip()
            if not message:
                message = "Podman was not found on the host."
            return False, message
        version_line = (version.stdout or "").strip().splitlines()
        version_text = version_line[0] if version_line else "podman"
        try:
            info = subprocess.run(
                ["podman", "info"],
                capture_output=True,
                text=True,
                timeout=30,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            return False, "%s was found, but 'podman info' did not finish (%s)." % (version_text, exc)
        if info.returncode != 0:
            message = (info.stderr or info.stdout or "").strip().splitlines()
            extra = message[-1] if message else "podman info failed."
            return False, "%s was found, but it is not ready: %s" % (version_text, extra)
        return True, version_text

    def next_page(self) -> None:
        index = self.stack.currentIndex()

        if index == 0:  # Start install
            self.stack.setCurrentIndex(1)
            self.back_btn.setEnabled(False)
            self.next_btn.setEnabled(False)
            QTimer.singleShot(100, self.start_installation)

        elif index == 1:  # From install to done
            self.stack.setCurrentIndex(2)
            self.next_btn.setText("Finish")
            self.back_btn.setEnabled(False)

        elif index == 2:
            os.chdir(os.path.dirname(os.getcwd())) # Change working directory to the one above where the main GUI lives
            subprocess.Popen([sys.executable, 'mainwindow.py']) # Load main GUI when the installer finishes
            self.close()

    def prev_page(self) -> None:
        index = self.stack.currentIndex()
        if index > 0:
            self.stack.setCurrentIndex(index - 1)
            self.next_btn.setText("Next")
        if index - 1 == 0:
            self.back_btn.setEnabled(False)

    def start_installation(self) -> None:
        self.terminal_output.setReadOnly(True)
        self.terminal_output.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse
            | Qt.TextInteractionFlag.TextSelectableByKeyboard
        )
        self.terminal_output.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

        if self.copy_output_button:
            self.copy_output_button.clicked.connect(self.copy_output)

        self.abort_button.clicked.connect(self.confirm_abort)

        self.process = QProcess(self)
        setup_script_path = str(SETUP_SCRIPT)
        
        # Debugging: Print the path to ensure it's correct
        print(f"Setup script path: {setup_script_path}")

        self.process.setProgram("/bin/bash")
        self.process.setArguments([setup_script_path])
        environment = QProcessEnvironment.systemEnvironment()
        environment.insert("LINOFFICE_ISO_UI", "gui")
        self.process.setProcessEnvironment(environment)
        self.process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self.process.readyReadStandardOutput.connect(self.handle_output)
        self.process.finished.connect(self.installation_finished)
        self.process.start()

    def copy_output(self) -> None:
        text = self.terminal_output.toPlainText()
        if text:
            QApplication.clipboard().setText(text)

    def handle_output(self) -> None:
        process = self.process
        if process is None:
            raise RuntimeError("The setup process is not running.")

        scrollbar = self.terminal_output.verticalScrollBar()
        follow_output = (
            not self.terminal_output.textCursor().hasSelection()
            and scrollbar.value() >= scrollbar.maximum() - 4
        )

        while process.canReadLine():
            line = bytes(process.readLine().data()).decode(errors="ignore").rstrip()

            # convert to HTML for display
            html_line = ansi_to_html(line)
            cursor = QTextCursor(self.terminal_output.document())
            cursor.movePosition(QTextCursor.MoveOperation.End)
            cursor.insertHtml(html_line + '<br>')

            # Auto-scroll only when the user is not selecting text
            if follow_output:
                self.terminal_output.moveCursor(QTextCursor.MoveOperation.End)

            # strip ANSI for regex matching
            clean_line = strip_ansi_codes(line)
            
            # Track last ERROR line
            if clean_line.startswith("ERROR:"):
                self.last_error_line = clean_line

            # Detect podman migrate  prompt marker from setup.sh and show GUI dialog
            if "PROMPT:PODMAN_MIGRATE" in clean_line:
                self.show_podman_migrate_dialog()
            
            # Detect VNC retry prompt marker from setup.sh and show GUI dialog
            if "PROMPT:VNC_SIGN_OUT_AND_RETRY" in clean_line:
                self.show_vnc_retry_dialog()

            if clean_line == "PROMPT:ISO_SOURCE":
                self.select_iso_source()

            # increase progress bar
            match = re.search(r'^Step (\d+):', clean_line)
            if match:
                step_num = int(match.group(1))
                if step_num == 1:
                    percentage = 0
                elif 2 <= step_num <= 8:
                    percentage = (step_num - 1) * 12.5
                else:
                    percentage = min(87.5, self.progress_bar.value())  # Cap at 87.5% for steps > 8
                self.progress_bar.setValue(int(percentage))

            # Handle Windows download percentage
            download_match = re.search(r'Downloading Windows: (\d+)%', clean_line)
            if download_match:
                win_percent = int(download_match.group(1))
                # Map to range 37–50%
                mapped_percent = 37 + (win_percent / 100) * (50 - 37)
                self.progress_bar.setValue(int(mapped_percent))
        # Check if process has finished and exited successfully
        if process.state() == QProcess.ProcessState.NotRunning:
            if process.exitStatus() == QProcess.ExitStatus.NormalExit and process.exitCode() == 0:
                self.progress_bar.setValue(100)

    def select_iso_source(self) -> None:
        dialog = QMessageBox(self)
        dialog.setWindowTitle("Windows installation source")
        dialog.setText("Download the Windows version configured in Compose, or use a local ISO?")
        download = dialog.addButton("Download", QMessageBox.ButtonRole.AcceptRole)
        local = dialog.addButton("Choose ISO...", QMessageBox.ButtonRole.ActionRole)
        dialog.addButton(QMessageBox.StandardButton.Cancel)
        dialog.exec()
        selection = {"mode": "cancel"}
        if dialog.clickedButton() == download:
            selection = {"mode": "download"}
        elif dialog.clickedButton() == local:
            path, _ = QFileDialog.getOpenFileName(self, "Choose Windows ISO", "", "ISO images (*.iso *.ISO)")
            if path:
                selection = {"mode": "local", "path": path}
        self.respond_to_prompt((json.dumps(selection) + "\n").encode())

    def installation_finished(self) -> None:
        process = self.process
        if process is None:
            raise RuntimeError("The setup process is not running.")
        exit_code = process.exitCode()
        self.progress_bar.setValue(100)

        if exit_code == 0:
            self.terminal_output.append("\nInstallation finished.")
            self.next_btn.setEnabled(True)
            self.abort_button.setEnabled(False)
        else:
            self.show_failure_dialog()

    def respond_to_prompt(self, response: bytes) -> None:
        process = self.process
        if not process or process.state() != QProcess.ProcessState.Running:
            print("Cannot answer setup prompt: the setup process is not running.", file=sys.stderr)
        elif process.write(response) == -1:
            print(f"Cannot answer setup prompt: {process.errorString()}", file=sys.stderr)

    
    def show_failure_dialog(self) -> None:
        error_text = self.last_error_line or "Unknown error"

        dialog = QDialog(self)
        dialog.setWindowTitle("Setup failed.")

        layout = QVBoxLayout(dialog)
        label = QLabel("<b>Setup failed.</b>")
        label_info = QLabel(f"<pre>{error_text}</pre>")

        layout.addWidget(label)
        layout.addWidget(label_info)

        # Buttons
        button_layout = QHBoxLayout()
        try_again_btn = QPushButton("Try again")
        show_log_btn = QPushButton("Show log")
        abort_btn = QPushButton("Exit")

        button_layout.addWidget(try_again_btn)
        button_layout.addWidget(show_log_btn)
        button_layout.addWidget(abort_btn)
        layout.addLayout(button_layout)

        def on_try_again() -> None:
            dialog.accept()
            QTimer.singleShot(100, self.start_installation)

        def on_show_log() -> None:
            log_path = str(read_data_path("windows_install.log"))
            QDesktopServices.openUrl(QUrl.fromLocalFile(log_path))
            # Keep dialog open

        def on_abort() -> None:
            dialog.accept()
            self.confirm_abort()

        try_again_btn.clicked.connect(on_try_again)
        show_log_btn.clicked.connect(on_show_log)
        abort_btn.clicked.connect(on_abort)

        dialog.exec()

    def show_podman_migrate_dialog(self) -> None:
        dialog = QDialog(self)
        dialog.setWindowTitle("Podman Storage Driver Migration")

        layout = QVBoxLayout(dialog)
        label = QLabel("""
<b>All running Podman containers will need to be stopped in order to migrate to the overlay storage driver. <br />
If you press OK, the command 'podman system migrate' will be run.</b>
        """)
        label.setWordWrap(True)
        layout.addWidget(label)

        button_layout = QHBoxLayout()
        ok_btn = QPushButton("OK")
        cancel_btn = QPushButton("Cancel")
        button_layout.addWidget(ok_btn)
        button_layout.addWidget(cancel_btn)
        layout.addLayout(button_layout)

        def migrate_ok() -> None:
            dialog.accept()
            self.respond_to_prompt(b"Y\n")

        def migrate_cancel() -> None:
            dialog.reject()
            self.respond_to_prompt(b"n\n")

        ok_btn.clicked.connect(migrate_ok)
        cancel_btn.clicked.connect(migrate_cancel)
        dialog.exec()
    
    def show_vnc_retry_dialog(self) -> None:
        dialog = QDialog(self)
        dialog.setWindowTitle("RDP Connection Help")

        layout = QVBoxLayout(dialog)
        label = QLabel("""
<b>We couldn't connect to Windows via RDP yet.</b><br><br>
Let's try a potential fix:
<ol>
<li>Open your web browser and go to the address <code>127.0.0.1:8006</code>.</li>
<li>Log in to the virtual machine using the password: <b>MyWindowsPassword</b>.</li>
<li>In Windows, click Start (Windows logo), then click <b>MyWindowsUser</b> at the bottom-left, then click <b>Sign out</b>.</li>
<li><b>Important:</b> Do <u>not</u> shut down the virtual machine. Only sign out.</li>
</ol>
After you've signed out, click <b>Try Again</b>.
        """)
        label.setWordWrap(True)
        layout.addWidget(label)

        button_layout = QHBoxLayout()
        try_again_btn = QPushButton("Try Again")
        cancel_btn = QPushButton("Cancel")
        button_layout.addWidget(try_again_btn)
        button_layout.addWidget(cancel_btn)
        layout.addLayout(button_layout)

        def on_try_again() -> None:
            dialog.accept()
            self.respond_to_prompt(b"Y\n")

        def on_cancel() -> None:
            dialog.reject()
            self.respond_to_prompt(b"n\n")

        try_again_btn.clicked.connect(on_try_again)
        cancel_btn.clicked.connect(on_cancel)
        dialog.exec()

    def confirm_abort(self) -> None:
        # Disable buttons
        self.next_btn.setEnabled(False)
        self.back_btn.setEnabled(False)
        if self.abort_button:
            self.abort_button.setEnabled(False)

        # Always show abort confirmation dialog first
        reply = QMessageBox.question(
            self, "Confirm Abort",
            "Are you sure you want to abort the setup?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )

        if reply != QMessageBox.StandardButton.Yes:
            # User cancelled abort → re-enable buttons
            self.next_btn.setEnabled(True)
            self.back_btn.setEnabled(False)  # Still in install state
            if self.abort_button:
                self.abort_button.setEnabled(True)
            return

        # If process is still running, try to stop it gracefully
        process = self.process
        if process and process.state() == QProcess.ProcessState.Running:
            pid = process.processId()
            try:
                os.kill(pid, signal.SIGINT)
            except Exception as e:
                print(f"Graceful kill failed: {e}")

            time.sleep(10)

            if process.state() == QProcess.ProcessState.Running:
                process.kill()

        # Ask about removing the container
        if os.environ.get("FLATPAK_ID"):
            remove_text = (
                "Do you want to delete the LinOffice container, the Windows virtual machine, "
                "and the setup files this Flatpak created (compose.yaml, configuration, and setup progress)? "
                "The next setup will start from scratch. The Flatpak itself stays installed. "
                "This cannot be undone.\n\n"
                "If this is your first setup attempt, choose Yes. "
                "If Windows is already installed and you only wanted to stop this run, choose No."
            )
        else:
            remove_text = (
                "Do you want to delete the LinOffice container, the Windows virtual machine, "
                "and the generated setup files (compose.yaml, configuration, and setup progress)? "
                "The next setup will start from scratch. The LinOffice program stays installed. "
                "This cannot be undone.\n\n"
                "If this is your first setup attempt, choose Yes. "
                "If you already have a working Windows install and are running setup again, choose No "
                "unless you want that Windows install deleted."
            )
        msg_box = QMessageBox()
        msg_box.setWindowTitle("Remove Container?")
        msg_box.setText(remove_text)
        msg_box.setStandardButtons(
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        msg_box.setDefaultButton(QMessageBox.StandardButton.No)
        msg_box.setIcon(QMessageBox.Icon.Warning)
        yes_button = msg_box.button(QMessageBox.StandardButton.Yes)
        yes_button.setText("Yes, delete")

        # Show the message box and get the response
        remove_reply = msg_box.exec()

        if remove_reply == QMessageBox.StandardButton.Yes:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            script_path = os.path.join(script_dir, 'remove_container.sh')
        
            if not os.path.isfile(script_path):
                QMessageBox.critical(
                    self, "Error",
                    f"Error. Podman container and volume have not been removed. Script not found: {script_path}",
                    QMessageBox.StandardButton.Ok
                )
                return
            if not os.access(script_path, os.X_OK):
                try:
                    os.chmod(script_path, 0o755)
                except OSError:
                    # /app is read-only in a Flatpak. bash can run the script anyway.
                    pass

            if os.environ.get("FLATPAK_ID"):
                # Host terminal programs are not in the sandbox. The dialog
                # already asked for confirmation, so answer the script's prompt.
                result = subprocess.run(
                    ['bash', script_path],
                    input='y\n',
                    text=True,
                    capture_output=True,
                )
                message = ((result.stdout or '') + (result.stderr or '')).strip()
                if result.returncode == 0:
                    QMessageBox.information(
                        self,
                        "Container removed",
                        message or "LinOffice container removed.",
                        QMessageBox.StandardButton.Ok,
                    )
                else:
                    QMessageBox.critical(
                        self,
                        "Error",
                        message or "Failed to remove the LinOffice container.",
                        QMessageBox.StandardButton.Ok,
                    )
                self.close()
                return
        
            terminal_cmds = [
                ['konsole', '--hold', '-e', 'bash', script_path],
                ['gnome-terminal', '--', 'bash', script_path],
                ['xfce4-terminal', '--hold', '-e', 'bash', script_path],
                ['lxterminal', '-e', 'bash', script_path],
                ['mate-terminal', '--disable-factory', '-e', 'bash', script_path],
                ['xterm', '-hold', '-e', 'bash', script_path],
            ]
        
            success = False
            for cmd in terminal_cmds:
                try:
                    subprocess.Popen(cmd, start_new_session=True)
                    success = True
                    break
                except FileNotFoundError:
                    continue
        
            if not success:
                QMessageBox.critical(
                    self, "Error",
                    "Error. Podman container and volume have not been removed. Could not load terminal.",
                    QMessageBox.StandardButton.Ok
                )

        self.close()


if __name__ == "__main__":
    app = QApplication(sys.argv)
    wizard = Wizard()
    wizard.show()
    sys.exit(app.exec())
