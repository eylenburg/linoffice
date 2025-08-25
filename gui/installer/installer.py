import sys
import re
import subprocess
import os
import signal
import time

from PySide6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout, QDialog, QLabel,
    QPushButton, QStackedWidget, QProgressBar, QTextEdit, QMessageBox
)
from PySide6.QtUiTools import QUiLoader
from PySide6.QtGui import QTextCursor, QDesktopServices
from PySide6.QtCore import QFile, QTimer, QProcess, QIODevice, QUrl

def strip_ansi_codes(text):
    ansi_escape = re.compile(r'\x1b\[[0-9;]*m')
    return ansi_escape.sub('', text)

def ansi_to_html(text):
    # Escape HTML special chars
    text = text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

    # Regex to match ANSI color codes
    ansi_escape = re.compile(r'\x1b\[(?P<code>[0-9;]+)m')

    color_map = {
        '31': 'red', '0;31': 'red',
        '32': 'green', '0;32': 'green',
        '33': 'gold', '1;33': 'gold', '0;33': 'gold',
    }

    def repl(m):
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
    def __init__(self):
        super().__init__()
        self.setWindowTitle("LinOffice Installer")
        self.setMinimumSize(600, 400)

        self.stack = QStackedWidget()

        self.welcome_page = self.load_ui("welcome.ui")
        self.install_page = self.load_ui("install_progress.ui")
        self.done_page = self.load_ui("done.ui")

        self.stack.addWidget(self.welcome_page)  # index 0
        self.stack.addWidget(self.install_page)  # index 1
        self.stack.addWidget(self.done_page)     # index 2

        self.back_btn = QPushButton("Back")
        self.next_btn = QPushButton("Next")

        self.back_btn.setEnabled(False)
        self.back_btn.clicked.connect(self.prev_page)
        self.next_btn.clicked.connect(self.next_page)

        self.last_error_line = None # for tracking the last error if setup exists with error

        nav_layout = QHBoxLayout()
        nav_layout.addWidget(self.back_btn)
        nav_layout.addStretch()
        nav_layout.addWidget(self.next_btn)

        layout = QVBoxLayout()
        layout.addWidget(self.stack)
        layout.addLayout(nav_layout)
        self.setLayout(layout)

        # For subprocess tracking
        self.process = None
        self.current_step = 0

    def load_ui(self, path):
        loader = QUiLoader()
        file = QFile(path)
        file.open(QFile.ReadOnly)
        widget = loader.load(file, self)
        file.close()
        return widget

    def next_page(self):
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

    def prev_page(self):
        index = self.stack.currentIndex()
        if index > 0:
            self.stack.setCurrentIndex(index - 1)
            self.next_btn.setText("Next")
        if index - 1 == 0:
            self.back_btn.setEnabled(False)

    def start_installation(self):
        self.progress_bar = self.install_page.findChild(QProgressBar, "progressBar")
        self.terminal_output = self.install_page.findChild(QTextEdit, "terminalOutput")

        self.abort_button = self.install_page.findChild(QPushButton, "abortButton")
        if self.abort_button:
            self.abort_button.clicked.connect(self.confirm_abort)

        self.process = QProcess(self)
        # Get the path to the setup.sh located two directories above
        setup_script_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "setup.sh")
        
        # Debugging: Print the path to ensure it's correct
        print(f"Setup script path: {setup_script_path}")

        self.process.setProgram("/bin/bash")
        self.process.setArguments([setup_script_path])
        self.process.setProcessChannelMode(QProcess.MergedChannels)
        self.process.readyReadStandardOutput.connect(self.handle_output)
        self.process.finished.connect(self.installation_finished)
        self.process.start()

    def handle_output(self):
        while self.process.canReadLine():
            line = bytes(self.process.readLine()).decode(errors="ignore").rstrip()

            # convert to HTML for display
            html_line = ansi_to_html(line)
            self.terminal_output.insertHtml(html_line + '<br>')

            # Auto-scroll to the bottom
            self.terminal_output.moveCursor(QTextCursor.End)

            # strip ANSI for regex matching
            clean_line = strip_ansi_codes(line)
            
            # Track last ERROR line
            if clean_line.startswith("ERROR:"):
                self.last_error_line = clean_line

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
            download_match = re.search(r'Downloading Windows (10|11): (\d+)%', clean_line)
            if download_match:
                win_percent = int(download_match.group(2))
                # Map to range 37–50%
                mapped_percent = 37 + (win_percent / 100) * (50 - 37)
                self.progress_bar.setValue(int(mapped_percent))
        # Check if process has finished and exited successfully
        if self.process.state() == QProcess.NotRunning:
            if self.process.exitStatus() == QProcess.NormalExit and self.process.exitCode() == 0:
                self.progress_bar.setValue(100)

    def installation_finished(self):
        exit_code = self.process.exitCode()
        self.progress_bar.setValue(100)

        if exit_code == 0:
            self.terminal_output.append("\nInstallation finished.")
            self.next_btn.setEnabled(True)
            self.abort_button.setEnabled(False)
        else:
            self.show_failure_dialog()

    def show_failure_dialog(self):
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

        def on_try_again():
            dialog.accept()
            QTimer.singleShot(100, self.start_installation)

        def on_show_log():
            log_path = os.path.expanduser("~/.local/share/linoffice/windows_install.log")
            QDesktopServices.openUrl(QUrl.fromLocalFile(log_path))
            # Keep dialog open

        def on_abort():
            dialog.accept()
            self.confirm_abort()

        try_again_btn.clicked.connect(on_try_again)
        show_log_btn.clicked.connect(on_show_log)
        abort_btn.clicked.connect(on_abort)

        dialog.exec()

    def confirm_abort(self):
        # Disable buttons
        self.next_btn.setEnabled(False)
        self.back_btn.setEnabled(False)
        if self.abort_button:
            self.abort_button.setEnabled(False)

        # Always show abort confirmation dialog first
        reply = QMessageBox.question(
            self, "Confirm Abort",
            "Are you sure you want to abort the setup?",
            QMessageBox.Yes | QMessageBox.No
        )

        if reply != QMessageBox.Yes:
            # User cancelled abort → re-enable buttons
            self.next_btn.setEnabled(True)
            self.back_btn.setEnabled(False)  # Still in install state
            if self.abort_button:
                self.abort_button.setEnabled(True)
            return

        # If process is still running, try to stop it gracefully
        if self.process and self.process.state() == QProcess.Running:
            pid = self.process.processId()
            try:
                os.kill(pid, signal.SIGINT)
            except Exception as e:
                print(f"Graceful kill failed: {e}")

            time.sleep(10)

            if self.process.state() == QProcess.Running:
                self.process.kill()

        # Ask about removing the container
        msg_box = QMessageBox()
        msg_box.setWindowTitle("Remove Container?")
        msg_box.setText("Do you want to remove the 'LinOffice' podman container and all its data? This action cannot be undone.\n\nIf you are running this installer for the first time, you can select 'Yes'. If you have previously set up LinOffice and are running this installer again, you should select 'No' unless you explicitly want your Windows container including all its data to be deleted.")
        msg_box.setStandardButtons(QMessageBox.Yes | QMessageBox.No)
        msg_box.setDefaultButton(QMessageBox.No)
        msg_box.setIcon(QMessageBox.Warning)
        yes_button = msg_box.button(QMessageBox.Yes)
        yes_button.setText("Yes, delete")

        # Show the message box and get the response
        remove_reply = msg_box.exec()

        # THIS IS NOT WORKING YET, SCRIPT IS NOT EXECUTED!
        if remove_reply == QMessageBox.Yes:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            script_path = os.path.join(script_dir, 'remove_container.sh')
        
            if not os.path.isfile(script_path):
                QMessageBox.critical(
                    self, "Error",
                    f"Error. Podman container and volume have not been removed. Script not found: {script_path}",
                    QMessageBox.Ok
                )
                return
            if not os.access(script_path, os.X_OK):
                os.chmod(script_path, 0o755)
        
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
                    QMessageBox.Ok
                )

        self.close()


if __name__ == "__main__":
    app = QApplication(sys.argv)
    wizard = Wizard()
    wizard.show()
    sys.exit(app.exec())
