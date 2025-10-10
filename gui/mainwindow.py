# This Python file uses the following encoding: utf-8
import sys
from PySide6.QtWidgets import QApplication, QWidget, QMainWindow, QMessageBox, QDialog, QVBoxLayout, QLabel, QPushButton, QHBoxLayout, QTextEdit
from PySide6.QtUiTools import QUiLoader
from PySide6.QtCore import QFile, QTimer, QProcess
from PySide6.QtGui import QTextCursor
import subprocess
import os
import csv
import threading
import re

LINOFFICE_SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'linoffice.sh'))
SETUP_SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'setup.sh'))
UNINSTALL_SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'uninstall.sh'))

# Define the user's local registry override config path
USER_REGISTRY_CONFIG = os.path.expanduser('~/.local/share/linoffice/registry_override.conf')

# Define the languages CSV file path
LANGUAGES_CSV = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'config', 'languages.csv'))

# Define the internet state file path
INTERNET_STATE_FILE = os.path.expanduser('~/.local/share/linoffice/internet')

def ensure_internet_state_file():
        """Ensure the internet state file exists with default 'on' value"""
        state_dir = os.path.dirname(INTERNET_STATE_FILE)
        if not os.path.exists(state_dir):
            os.makedirs(state_dir, exist_ok=True)
        
        if not os.path.exists(INTERNET_STATE_FILE):
            # Create the file with default 'on' state
            with open(INTERNET_STATE_FILE, 'w') as f:
                f.write('on\n')

def load_internet_state():
    """Load the current internet state from file"""
    ensure_internet_state_file()
    try:
        with open(INTERNET_STATE_FILE, 'r') as f:
            state = f.read().strip()
            return state == 'on'
    except Exception as e:
        print(f"Error loading internet state: {e}")
        return True  # Default to 'on' if error

def save_internet_state(state_on):
    """Save the internet state to file"""
    ensure_internet_state_file()
    try:
        with open(INTERNET_STATE_FILE, 'w') as f:
            f.write('on\n' if state_on else 'off\n')
    except Exception as e:
        print(f"Error saving internet state: {e}")

def ensure_registry_config_exists():
    """Ensure the registry_override.conf file exists in user's local directory"""
    config_dir = os.path.dirname(USER_REGISTRY_CONFIG)
    if not os.path.exists(config_dir):
        os.makedirs(config_dir, exist_ok=True)
    
    if not os.path.exists(USER_REGISTRY_CONFIG):
        # Create the file with default empty values
        with open(USER_REGISTRY_CONFIG, 'w') as f:
            f.write('DATE_FORMAT=""\n')
            f.write('DECIMAL_SEPARATOR=""\n')
            f.write('CURRENCY_SYMBOL=""\n')

def load_languages_from_csv():
    """Load languages from the CSV file and return a list of formatted options"""
    languages = []
    try:
        with open(LANGUAGES_CSV, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            next(reader)  # Skip header row
            for row in reader:
                if len(row) >= 3:
                    kbd_code, lang_code, lang_name = row[0], row[1], row[2]
                    # Format: "af_ZA [Afrikaans (South Africa)]"
                    formatted_option = f"{lang_code} [{lang_name}]"
                    languages.append((formatted_option, kbd_code))
    except Exception as e:
        print(f"Error loading languages from CSV: {e}")
    return languages

def strip_ansi_codes(text):
    ansi_escape = re.compile(r'\x1b\[[0-9;]*m')
    return ansi_escape.sub('', text)

class MainWindow(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        # Ensure registry config exists before loading UI
        ensure_registry_config_exists()
        self.load_ui('main.ui')
        self.setWindowTitle(self.ui.windowTitle())
        self.connect_buttons()
        self.update_container_status()
        # Set up a timer to update container status every 30 seconds
        self.status_timer = QTimer(self)
        self.status_timer.timeout.connect(self.update_container_status)
        self.status_timer.start(30000)  # 30,000 ms = 30 seconds
        # Check container status and prompt user if not running
        self.check_and_prompt_container()

    def load_ui(self, ui_file):
        loader = QUiLoader()
        file = QFile(ui_file)
        file.open(QFile.ReadOnly)
        self.ui = loader.load(file, self)
        file.close()

    # Connect the buttons to functions
    def connect_buttons(self):
        self.ui.pushButton_settings.clicked.connect(self.open_settings_window)
        self.ui.pushButton_tools.clicked.connect(self.open_tools_window)
        self.ui.pushButton_troubleshooting.clicked.connect(self.open_troubleshooting_window)
        # Connect app launch buttons
        self.ui.pushButton_word.clicked.connect(lambda: self.launch_linoffice_app('word'))
        self.ui.pushButton_excel.clicked.connect(lambda: self.launch_linoffice_app('excel'))
        self.ui.pushButton_powerpoint.clicked.connect(lambda: self.launch_linoffice_app('powerpoint'))
        self.ui.pushButton_outlook.clicked.connect(lambda: self.launch_linoffice_app('outlook'))
        self.ui.pushButton_onenote.clicked.connect(lambda: self.launch_linoffice_app('onenote'))

    # Functions to open secondary windows
    def open_settings_window(self):
        self.settings_window = SettingsWindow()
        self.settings_window.show()

    def open_tools_window(self):
        self.tools_window = ToolsWindow(main_window=self)
        self.tools_window.show()

    def open_troubleshooting_window(self):
        self.troubleshooting_window = TroubleshootingWindow()
        self.troubleshooting_window.show()

    def launch_linoffice_app(self, *args):
        subprocess.Popen([LINOFFICE_SCRIPT, *args])

    def update_container_status(self):
        try:
            result = subprocess.run(['podman', 'ps', '--filter', 'name=LinOffice', '--format', '{{.Status}}'], capture_output=True, text=True, check=True)
            status = result.stdout.strip()
            if status:
                status_text = f"Container: running ({status})"
            else:
                status_text = "Container: not running"
        except Exception as e:
            status_text = f"Container: error"
        self.ui.label.setText(status_text)

    def check_and_prompt_container(self):
        try:
            result = subprocess.run(['podman', 'ps', '--filter', 'name=LinOffice', '--format', '{{.Status}}'], capture_output=True, text=True, check=True)
            if not result.stdout.strip():
                # Container is not running, show dialog
                dialog = QMessageBox(self)
                dialog.setWindowTitle("Container Not Running")
                dialog.setText("The LinOffice container is not running. Would you like to start the container now? Otherwise, starting an Office app may take longer.")
                dialog.setStandardButtons(QMessageBox.Yes | QMessageBox.No)
                dialog.setDefaultButton(QMessageBox.Yes)
                response = dialog.exec()
                if response == QMessageBox.Yes:
                    # Run linoffice.sh --startcontainer in the background
                    threading.Thread(target=lambda: subprocess.Popen([LINOFFICE_SCRIPT, '--startcontainer'])).start()
        except subprocess.CalledProcessError as e:
            print(f"DEBUG: podman ps error: {e.stderr}")
            QMessageBox.critical(self, "Error", "Could not check container status.")

# Defining secondary windows
class SettingsWindow(QMainWindow):
    def __init__(self, parent=None):
        super(SettingsWindow, self).__init__(parent)
        self.load_ui('settings.ui')
        self.setWindowTitle(self.ui.windowTitle())
        self.settings_changed = False
        self._initial_network_checked = None  # Track initial state
        self.load_current_settings()
        # Store the initial state after loading
        self._initial_network_checked = self.ui.checkBox_network.isChecked()
        self.connect_settings_buttons()

    def load_ui(self, ui_file):
        loader = QUiLoader()
        file = QFile(ui_file)
        file.open(QFile.ReadOnly)
        self.ui = loader.load(file, self)
        file.close()

    def connect_settings_buttons(self):
        # Connect the set language button
        self.ui.pushButton_setlang.clicked.connect(self.run_setlang)
        
        # Connect OK and Cancel buttons
        self.ui.pushButton_ok.clicked.connect(self.save_settings)
        self.ui.pushButton_cancel.clicked.connect(self.close)
        
        # Connect settings change signals to track modifications
        self.ui.checkBox_suspend.toggled.connect(self.mark_settings_changed)
        self.ui.checkBox_network.toggled.connect(self.mark_settings_changed)  # Track network changes
        self.ui.comboBox_scaling.currentTextChanged.connect(self.mark_settings_changed)
        self.ui.comboBox_date.currentTextChanged.connect(self.mark_settings_changed)
        self.ui.comboBox_decimalseparator.currentTextChanged.connect(self.mark_settings_changed)
        self.ui.lineEdit_currency.textChanged.connect(self.mark_settings_changed)
        self.ui.comboBox_keyboard.currentTextChanged.connect(self.mark_settings_changed)

    def mark_settings_changed(self):
        self.settings_changed = True

    def load_current_settings(self):
        """Load current settings from config files"""
        try:
            import re
            # Load linoffice.conf settings
            linoffice_conf_path = os.path.join(os.path.dirname(LINOFFICE_SCRIPT), 'config', 'linoffice.conf')
            if os.path.exists(linoffice_conf_path):
                with open(linoffice_conf_path, 'r') as f:
                    content = f.read()
                    # Set autopause checkbox
                    if 'AUTOPAUSE="on"' in content:
                        self.ui.checkBox_suspend.setChecked(True)
                    elif 'AUTOPAUSE="off"' in content:
                        self.ui.checkBox_suspend.setChecked(False)
                    
                    # Set scaling combobox
                    if 'RDP_SCALE="100"' in content:
                        self.ui.comboBox_scaling.setCurrentText("100%")
                    elif 'RDP_SCALE="140"' in content:
                        self.ui.comboBox_scaling.setCurrentText("140%")
                    elif 'RDP_SCALE="180"' in content:
                        self.ui.comboBox_scaling.setCurrentText("180%")
                    
                    # Load and populate keyboard comboBox
                    self.populate_keyboard_combo()
                    
                    # Set current keyboard selection
                    kbd_match = re.search(r'RDP_KBD="([^"]*)"', content)
                    if kbd_match and kbd_match.group(1):
                        current_kbd = kbd_match.group(1)
                        # Find the corresponding language option
                        for i in range(self.ui.comboBox_keyboard.count()):
                            item_data = self.ui.comboBox_keyboard.itemData(i)
                            if item_data == current_kbd:
                                self.ui.comboBox_keyboard.setCurrentIndex(i)
                                break

            # Load network state from file
            network_state = load_internet_state()
            self.ui.checkBox_network.setChecked(network_state)

            # Load registry_override.conf settings
            registry_conf_path = USER_REGISTRY_CONFIG
            # Ensure the file exists (recreate if deleted)
            ensure_registry_config_exists()
            
            with open(registry_conf_path, 'r') as f:
                content = f.read()
                # Set date format
                date_match = re.search(r'DATE_FORMAT="([^"]*)"', content)
                if date_match and date_match.group(1):
                    self.ui.comboBox_date.setCurrentText(date_match.group(1))
                
                # Set decimal separator
                decimal_match = re.search(r'DECIMAL_SEPARATOR="([^"]*)"', content)
                if decimal_match and decimal_match.group(1):
                    self.ui.comboBox_decimalseparator.setCurrentText(decimal_match.group(1))
                
                # Set currency symbol
                currency_match = re.search(r'CURRENCY_SYMBOL="([^"]*)"', content)
                if currency_match and currency_match.group(1):
                    self.ui.lineEdit_currency.setText(currency_match.group(1))
        except Exception as e:
            print(f"Error loading settings: {e}")

    def populate_keyboard_combo(self):
        """Populate the keyboard comboBox with language options from CSV"""
        # Clear existing items except the first "(no change)" option
        self.ui.comboBox_keyboard.clear()
        self.ui.comboBox_keyboard.addItem("(no change)", "")
        
        # Load languages from CSV
        languages = load_languages_from_csv()
        for formatted_option, kbd_code in languages:
            self.ui.comboBox_keyboard.addItem(formatted_option, kbd_code)

    def run_setlang(self):
        """Run the set language command"""
        subprocess.Popen([LINOFFICE_SCRIPT, 'manual', 'C:\\Program Files\\Microsoft Office\\root\\Office16\\SETLANG.EXE'])

    def save_settings(self):
        """Save all settings to config files"""
        try:
            import re
            registry_settings_changed = False
            # --- Network checkbox logic ---
            network_checked = self.ui.checkBox_network.isChecked()
            if self._initial_network_checked is not None and network_checked != self._initial_network_checked:
                if network_checked:
                    threading.Thread(target=lambda: subprocess.Popen([LINOFFICE_SCRIPT, 'internet_on'])).start()
                else:
                    threading.Thread(target=lambda: subprocess.Popen([LINOFFICE_SCRIPT, 'internet_off'])).start()
                # Save the new state to file
                save_internet_state(network_checked)
                # Update the initial state for next time
                self._initial_network_checked = network_checked
            # --- End network checkbox logic ---
            
            # Save linoffice.conf settings
            linoffice_conf_path = os.path.join(os.path.dirname(LINOFFICE_SCRIPT), 'config', 'linoffice.conf')
            if os.path.exists(linoffice_conf_path):
                with open(linoffice_conf_path, 'r') as f:
                    content = f.read()
                
                # Update AUTOPAUSE setting
                autopause_value = "on" if self.ui.checkBox_suspend.isChecked() else "off"
                content = content.replace('AUTOPAUSE="on"', f'AUTOPAUSE="{autopause_value}"')
                content = content.replace('AUTOPAUSE="off"', f'AUTOPAUSE="{autopause_value}"')
                
                # Update RDP_SCALE setting
                scaling_text = self.ui.comboBox_scaling.currentText()
                if scaling_text.endswith('%'):
                    scaling_value = scaling_text[:-1]  # Remove % character
                else:
                    scaling_value = scaling_text
                
                content = content.replace('RDP_SCALE="100"', f'RDP_SCALE="{scaling_value}"')
                content = content.replace('RDP_SCALE="140"', f'RDP_SCALE="{scaling_value}"')
                content = content.replace('RDP_SCALE="180"', f'RDP_SCALE="{scaling_value}"')
                
                # Update RDP_KBD setting
                keyboard_data = self.ui.comboBox_keyboard.currentData()
                if keyboard_data:  # Only update if a keyboard is selected (not "(no change)")
                    kbd_string = f'/kbd:layout:{keyboard_data}'
                    if re.search(r'RDP_KBD="[^"]*"', content):
                        content = re.sub(r'RDP_KBD="[^"]*"', f'RDP_KBD="{kbd_string}"', content)
                    else:
                        # If RDP_KBD is missing, add it (optional, but not required by your spec)
                        content += f'\nRDP_KBD="{kbd_string}"\n'
                
                with open(linoffice_conf_path, 'w') as f:
                    f.write(content)

            # Save registry_override.conf settings
            registry_conf_path = USER_REGISTRY_CONFIG
            # Ensure the file exists before saving
            ensure_registry_config_exists()
            
            with open(registry_conf_path, 'r') as f:
                original_content = f.read()
            
            content = original_content
            
            # Update DATE_FORMAT
            date_value = self.ui.comboBox_date.currentText()
            if date_value != "(no change)":
                content = re.sub(r'DATE_FORMAT="[^"]*"', f'DATE_FORMAT="{date_value}"', content)
            
            # Update DECIMAL_SEPARATOR
            decimal_value = self.ui.comboBox_decimalseparator.currentText()
            if decimal_value != "(no change)":
                content = re.sub(r'DECIMAL_SEPARATOR="[^"]*"', f'DECIMAL_SEPARATOR="{decimal_value}"', content)
            
            # Update CURRENCY_SYMBOL
            currency_value = self.ui.lineEdit_currency.text()
            content = re.sub(r'CURRENCY_SYMBOL="[^"]*"', f'CURRENCY_SYMBOL="{currency_value}"', content)
            
            # Check if registry settings actually changed
            if content != original_content:
                registry_settings_changed = True
            
            with open(registry_conf_path, 'w') as f:
                f.write(content)
            
            # Run linoffice.sh registry_override if registry settings were changed
            if registry_settings_changed:
                try:
                    subprocess.Popen([LINOFFICE_SCRIPT, 'registry_override'])
                except FileNotFoundError:
                    QMessageBox.warning(self, 'Warning', 'LinOffice script not found or not executable')
            
            self.settings_changed = False
            self.close()
            
        except Exception as e:
            QMessageBox.critical(self, 'Error', f'Failed to save settings: {e}')

    def closeEvent(self, event):
        """Handle window close event with confirmation dialog if settings changed"""
        if self.settings_changed:
            reply = QMessageBox.question(self, 'Save Changes?',
                                       'You have unsaved changes. Do you want to save them before closing?',
                                       QMessageBox.Save | QMessageBox.Discard | QMessageBox.Cancel,
                                       QMessageBox.Save)
            
            if reply == QMessageBox.Save:
                self.save_settings()
                event.accept()
            elif reply == QMessageBox.Discard:
                event.accept()
            else:  # Cancel
                event.ignore()
        else:
            event.accept()

class ToolsWindow(QMainWindow):
    def __init__(self, parent=None, main_window=None):
        super(ToolsWindow, self).__init__(parent)
        self.main_window = main_window
        self.load_ui('tools.ui')
        self.setWindowTitle(self.ui.windowTitle())
        self.connect_tools_buttons()

    def load_ui(self, ui_file):
        loader = QUiLoader()
        file = QFile(ui_file)
        file.open(QFile.ReadOnly)
        self.ui = loader.load(file, self)
        file.close()

    def show_warning_dialog_rdp(self, action):
        dialog = QMessageBox(self)
        dialog.setWindowTitle("Warning")
        dialog.setText("Warning: Be careful when changing any Windows settings as it might break something.")
        dialog.setStandardButtons(QMessageBox.Ok)
        dialog.setIcon(QMessageBox.Information)
        
        # Execute the action only if OK is clicked
        if dialog.exec() == QMessageBox.Ok:
            action()

    def show_warning_dialog_vnc(self, action):
        dialog = QMessageBox(self)
        dialog.setWindowTitle("Warning")
        dialog.setText("Warning: Be careful when changing any Windows settings as it might break something.\n\nNote: The VNC connection does not have clipboard sharing or /home folder sharing.\n\nThe password to log in is 'MyWindowsPassword'. Please sign out at the end (Start > MyWindowsUser > Sign out) as RDP connections might be blocked otherwise.")
        dialog.setStandardButtons(QMessageBox.Ok)
        dialog.setIcon(QMessageBox.Information)
        
        # Execute the action only if OK is clicked
        if dialog.exec() == QMessageBox.Ok:
            action()

    # Connect buttons in tools window with LinOffice script
    def connect_tools_buttons(self):
        if self.main_window:
            self.ui.pushButton_updateself.clicked.connect(self.run_self_updater)
            self.ui.pushButton_update.clicked.connect(lambda: self.main_window.launch_linoffice_app('update'))
            self.ui.pushButton_powershell.clicked.connect(lambda: self.main_window.launch_linoffice_app('manual', 'powershell.exe'))
            self.ui.pushButton_regedit.clicked.connect(lambda: self.main_window.launch_linoffice_app('manual', 'regedit.exe'))
            self.ui.pushButton_cmd.clicked.connect(lambda: self.main_window.launch_linoffice_app('manual', 'cmd.exe'))
            self.ui.pushButton_explorer.clicked.connect(lambda: self.main_window.launch_linoffice_app('manual', 'explorer.exe'))
            self.ui.pushButton_access.clicked.connect(lambda: self.main_window.launch_linoffice_app('manual', 'msaccess.exe'))
            self.ui.pushButton_publisher.clicked.connect(lambda: self.main_window.launch_linoffice_app('manual', 'mspub.exe'))
            self.ui.pushButton_windows_rdp.clicked.connect(lambda: self.show_warning_dialog_rdp(lambda: self.main_window.launch_linoffice_app('windows')))
            self.ui.pushButton_windows_vnc.clicked.connect(lambda: self.show_warning_dialog_vnc(self.open_vnc_in_browser))

    def open_vnc_in_browser(self):
        import webbrowser
        webbrowser.open('http://127.0.0.1:8006')

    def run_self_updater(self):
        original_dir = os.getcwd()
        parent_dir = os.path.abspath(os.path.join(original_dir, '..'))
        updater_script = os.path.join(parent_dir, 'updater.py')

        if not os.path.exists(updater_script):
            QMessageBox.warning(self, "Error", "Updater script not found.")
            return

        self.output_dialog = QDialog(self)
        self.output_dialog.setWindowTitle("Updating LinOffice...")
        self.output_dialog.setMinimumSize(600, 400)

        layout = QVBoxLayout()

        self.text_edit = QTextEdit()
        self.text_edit.setReadOnly(True)
        layout.addWidget(self.text_edit)

        self.button_box = QHBoxLayout()
        self.yes_button = QPushButton("Yes")
        self.no_button = QPushButton("No")
        self.ok_button = QPushButton("OK")
        self.ok_button.setVisible(False)

        self.button_box.addWidget(self.yes_button)
        self.button_box.addWidget(self.no_button)
        self.button_box.addWidget(self.ok_button)
        layout.addLayout(self.button_box)

        self.output_dialog.setLayout(layout)
        self.output_dialog.show()

        # Initialize state
        self.waiting_for_input = False
        
        # Create QProcess
        self.process = QProcess(self)
        
        # Set working directory
        self.process.setWorkingDirectory(parent_dir)
        
        # Set environment to force unbuffered output
        env = self.process.processEnvironment()
        env.insert("PYTHONUNBUFFERED", "1")
        self.process.setProcessEnvironment(env)
        
        # Connect signals
        self.process.readyReadStandardOutput.connect(self._handle_stdout)
        self.process.readyReadStandardError.connect(self._handle_stderr)
        self.process.finished.connect(self._handle_finished)
        self.process.started.connect(self._handle_started)
        self.process.errorOccurred.connect(self._handle_error)
        
        # Connect buttons
        self.yes_button.clicked.connect(lambda: self._send_response('y'))
        self.no_button.clicked.connect(lambda: self._send_response('n'))
        self.ok_button.clicked.connect(self._close_updater_dialog)
        
        # Start the process
        program = sys.executable
        arguments = ['-u', 'updater.py']
        
        self.process.start(program, arguments)
        
        # Check if process started successfully
        if not self.process.waitForStarted(3000):
            self.text_edit.append("Failed to start updater process")
            self.ok_button.setVisible(True)

    def _handle_started(self):
        """Called when process starts successfully"""
        pass  # No output needed

    def _handle_stdout(self):
        """Handle stdout output from process"""
        if not self.process:
            return
            
        data = self.process.readAllStandardOutput()
        if data:
            text = bytes(data).decode('utf-8', errors='replace')
            
            # Split into lines and process each
            lines = text.replace('\r\n', '\n').replace('\r', '\n').split('\n')
            
            for line in lines:
                if line.strip():  # Only process non-empty lines
                    self.text_edit.append(line)
                    
                    # Check for input prompts, the "y/n" should handle both normal updates and major version warnings
                    lower_line = line.lower()
                    if "(y/n)" in lower_line or "update?" in lower_line:
                        self.waiting_for_input = True
                        self.yes_button.setVisible(True)
                        self.no_button.setVisible(True)
                        # Default to 'No' as the safe choice
                        try:
                            self.no_button.setAutoDefault(True)
                            self.no_button.setDefault(True)
                            self.no_button.setFocus()
                            self.yes_button.setAutoDefault(False)
                            self.yes_button.setDefault(False)
                        except Exception:
                            pass
            
            # Auto-scroll to bottom
            self._scroll_to_bottom()

    def _handle_stderr(self):
        """Handle stderr output from process"""
        if not self.process:
            return
            
        data = self.process.readAllStandardError()
        if data:
            text = bytes(data).decode('utf-8', errors='replace')
            if text.strip():
                self.text_edit.append(f"ERROR: {text.strip()}")
                self._scroll_to_bottom()

    def _handle_finished(self, exit_code, exit_status):
        """Handle process completion"""
        self.text_edit.append(f"\nUpdater finished")
        self.yes_button.setVisible(False)
        self.no_button.setVisible(False)
        self.ok_button.setVisible(True)
        self.waiting_for_input = False
        self._scroll_to_bottom()

        # Restore original working directory when process finishes
        if hasattr(self, 'original_dir'):
            os.chdir(self.original_dir)

    def _handle_error(self, error):
        """Handle process errors"""
        error_messages = {
            QProcess.FailedToStart: "Failed to start the updater process",
            QProcess.Crashed: "Updater process crashed",
            QProcess.Timedout: "Updater process timed out",
            QProcess.WriteError: "Write error to updater process",
            QProcess.ReadError: "Read error from updater process", 
            QProcess.UnknownError: "Unknown error with updater process"
        }
        
        error_msg = error_messages.get(error, f"Unknown error: {error}")
        self.text_edit.append(error_msg)
        self.ok_button.setVisible(True)
        self._scroll_to_bottom()

    def _scroll_to_bottom(self):
        """Scroll text edit to bottom"""
        cursor = self.text_edit.textCursor()
        cursor.movePosition(QTextCursor.End)
        self.text_edit.setTextCursor(cursor)

    def _send_response(self, response):
        """Send response to the process"""
        if not self.waiting_for_input:
            return
            
        if not self.process or self.process.state() != QProcess.Running:
            self.text_edit.append("Process is not running")
            return
        
        try:
            # Send the response
            response_data = (response + '\n').encode('utf-8')
            bytes_written = self.process.write(response_data)
            
            if bytes_written != -1:
                self.waiting_for_input = False
                self.yes_button.setVisible(False)
                self.no_button.setVisible(False)
            
            self._scroll_to_bottom()
            
        except Exception as e:
            self.text_edit.append(f"Error sending response: {e}")
            self._scroll_to_bottom()

    def _close_updater_dialog(self):
        """Close the dialog and clean up"""
        if hasattr(self, 'process') and self.process:
            if self.process.state() == QProcess.Running:
                self.process.terminate()
                if not self.process.waitForFinished(3000):
                    self.process.kill()
            
            # Disconnect all signals to prevent issues
            try:
                self.process.readyReadStandardOutput.disconnect()
                self.process.readyReadStandardError.disconnect()
                self.process.finished.disconnect()
                self.process.started.disconnect()
                self.process.errorOccurred.disconnect()
            except:
                pass
        
        # Restore original working directory when process finishes
        if hasattr(self, 'original_dir'):
            os.chdir(self.original_dir)

        if hasattr(self, 'output_dialog'):
            self.output_dialog.accept()

class TroubleshootingWindow(QMainWindow):
    def __init__(self, parent=None):
        super(TroubleshootingWindow, self).__init__(parent)
        self.load_ui('troubleshooting.ui')
        self.setWindowTitle(self.ui.windowTitle())
        self.connect_troubleshooting_buttons()
        # Initialize checkboxes based on current config
        self._tr_init = True
        try:
            self._load_troubleshooting_state()
        finally:
            self._tr_init = False

    def load_ui(self, ui_file):
        loader = QUiLoader()
        file = QFile(ui_file)
        file.open(QFile.ReadOnly)
        self.ui = loader.load(file, self)
        file.close()

    # Connect buttons in troubleshooting window with LinOffice script
    def connect_troubleshooting_buttons(self):
        self.ui.pushButton_lockfiles.clicked.connect(self.run_cleanup_full)
        self.ui.pushButton_desktopfiles.clicked.connect(self.run_setup_desktop)
        self.ui.pushButton_reset.clicked.connect(self.run_reset)
        self.ui.pushButton_stopcontainer.clicked.connect(self.run_stopcontainer)
        self.ui.pushButton_logfile.clicked.connect(self.open_logfile)
        self.ui.pushButton_website.clicked.connect(self.open_website)
        self.ui.pushButton_uninstall.clicked.connect(self.run_uninstall)
        self.ui.pushButton_healthcheck.clicked.connect(self.run_healthcheck)
        # Connect FreeRDP options
        self.ui.checkBox_multimon.toggled.connect(self._on_multimon_toggled)
        self.ui.checkBox_hidef.toggled.connect(self._on_hidef_toggled)

    def _conf_path(self):
        # Reuse same resolution as in SettingsWindow
        return os.path.join(os.path.dirname(LINOFFICE_SCRIPT), 'config', 'linoffice.conf')

    def _read_conf(self):
        path = self._conf_path()
        if not os.path.exists(path):
            return ''
        with open(path, 'r') as f:
            return f.read()

    def _write_conf(self, content):
        path = self._conf_path()
        with open(path, 'w') as f:
            f.write(content)

    def _load_troubleshooting_state(self):
        content = self._read_conf()
        # Multiple Monitors: check if "/multimon" present anywhere
        self.ui.checkBox_multimon.setChecked('/multimon' in content)
        # HiDef: check HIDEF value; if missing, uncheck
        hidef_match = re.search(r'^HIDEF="(on|off)"', content, re.MULTILINE)
        if hidef_match:
            self.ui.checkBox_hidef.setChecked(hidef_match.group(1) == 'on')
        else:
            self.ui.checkBox_hidef.setChecked(False)

    def _on_multimon_toggled(self, checked):
        if getattr(self, '_tr_init', False):
            return
        content = self._read_conf()
        if not content:
            return
        # Ensure there is an RDP_FLAGS line to modify
        def add_multimon_to_flags(match):
            inner = match.group(1)
            if ' /multimon' not in inner and '/multimon' not in inner:
                inner = inner + ' /multimon'
            return f'RDP_FLAGS="{inner}"'

        def remove_multimon_from_flags(match):
            inner = match.group(1)
            inner = inner.replace(' /multimon', '')
            inner = inner.replace('/multimon', '')
            return f'RDP_FLAGS="{inner}"'

        pattern = r'^RDP_FLAGS="([^"]*)"'
        if checked:
            new_content = re.sub(pattern, add_multimon_to_flags, content, count=1, flags=re.MULTILINE)
        else:
            new_content = re.sub(pattern, remove_multimon_from_flags, content, count=1, flags=re.MULTILINE)
        if new_content != content:
            self._write_conf(new_content)

    def _on_hidef_toggled(self, checked):
        if getattr(self, '_tr_init', False):
            return
        content = self._read_conf()
        if content == '':
            return
        hidef_re = r'^HIDEF="(on|off)"'
        if re.search(hidef_re, content, flags=re.MULTILINE):
            new_value = 'on' if checked else 'off'
            new_content = re.sub(hidef_re, f'HIDEF="{new_value}"', content, flags=re.MULTILINE)
            if new_content != content:
                self._write_conf(new_content)
        else:
            # Only add when enabling (checked). If disabling and missing, leave as-is.
            if checked:
                # Append at end on a new line
                suffix = '' if content.endswith('\n') else '\n'
                self._write_conf(content + suffix + 'HIDEF="on"\n')

    def run_cleanup_full(self):
        # Start the subprocess and capture the output
        process = subprocess.Popen(
            [LINOFFICE_SCRIPT, 'cleanup', '--full'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Read the first line of output and show in QMessageBox
        output_line = process.stdout.readline()
        process.wait()
        QMessageBox.information(self.ui, "Lock file cleanup", output_line.strip(), QMessageBox.Ok)

    def run_setup_desktop(self):
        # Start the subprocess and capture the output
        process = subprocess.Popen(
            [SETUP_SCRIPT, '--desktop'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        output_lines = process.stdout.readlines()
        process.wait()
        last_output_line = output_lines[-1].strip()
        clean_output_line = strip_ansi_codes(last_output_line)
        QMessageBox.information(self.ui, "Recreate app launchers", clean_output_line, QMessageBox.Ok)

    def run_reset(self):
        subprocess.Popen([LINOFFICE_SCRIPT, 'reset'])

    def run_stopcontainer(self):
        subprocess.Popen([LINOFFICE_SCRIPT, '--stopcontainer'])

    def open_logfile(self):
        logfile = os.path.expanduser('~/.local/share/linoffice/linoffice.log')
        # Try to open with xdg-open (Linux default)
        subprocess.Popen(['xdg-open', logfile])

    def open_website(self):
        import webbrowser
        webbrowser.open('https://github.com/eylenburg/linoffice')

    def run_uninstall(self):
        reply = QMessageBox.question(self, 'Confirm Uninstall',
                                     'Are you sure you want to uninstall LinOffice?',
                                     QMessageBox.Yes | QMessageBox.Cancel, QMessageBox.Cancel)
        if reply == QMessageBox.Yes:
            # Try to open in a new terminal window (x-terminal-emulator, gnome-terminal, konsole)
            terminal_cmds = [
                ['x-terminal-emulator', '-e', UNINSTALL_SCRIPT],
                ['konsole', '-e', UNINSTALL_SCRIPT],
                ['gnome-terminal', '--', UNINSTALL_SCRIPT],
                ['xfce4-terminal', '-e', UNINSTALL_SCRIPT],
                ['lxterminal', '-e', UNINSTALL_SCRIPT],
                ['mate-terminal', '-e', UNINSTALL_SCRIPT],
                ['xterm', '-e', UNINSTALL_SCRIPT],
            ]
            for cmd in terminal_cmds:
                try:
                    subprocess.Popen(cmd)
                    break
                except FileNotFoundError:
                    continue

    def run_healthcheck(self):
        reply = QMessageBox.question(self, 'Confirm Healthcheck',
                                     'Do yu want to run a healthcheck? This will run a few tests to see if your system is set up correctly.',
                                     QMessageBox.Yes | QMessageBox.Cancel, QMessageBox.Cancel)
        if reply == QMessageBox.Yes:
            # Try to open in a new terminal window (x-terminal-emulator, gnome-terminal, konsole)
            terminal_cmds = [
                ['x-terminal-emulator', '-e', 'bash', '-c', f'{SETUP_SCRIPT} --healthcheck; exec bash'],
                ['konsole', '-e', 'bash', '-c', f'{SETUP_SCRIPT} --healthcheck; exec bash'],
                ['gnome-terminal', '--', 'bash', '-c', f'{SETUP_SCRIPT} --healthcheck; exec bash'],
                ['xfce4-terminal', '-e', 'bash', '-c', f'{SETUP_SCRIPT} --healthcheck; exec bash'],
                ['lxterminal', '-e', 'bash', '-c', f'{SETUP_SCRIPT} --healthcheck; exec bash'],
                ['mate-terminal', '-e', 'bash', '-c', f'{SETUP_SCRIPT} --healthcheck; exec bash'],
                ['xterm', '-e', 'bash', '-c', f'{SETUP_SCRIPT} --healthcheck; exec bash'],
            ]
            for cmd in terminal_cmds:
                try:
                    subprocess.Popen(cmd)
                    break
                except FileNotFoundError:
                    continue

if __name__ == "__main__":
    app = QApplication(sys.argv)
    widget = MainWindow()
    widget.show()
    sys.exit(app.exec())
