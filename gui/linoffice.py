import subprocess
import sys
import os
from PySide6.QtWidgets import QApplication, QMessageBox
from PySide6.QtCore import QFileInfo
from pathlib import Path

_LIB_DIR = Path(__file__).resolve().parents[1] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))
from paths import read_data_path

def container_exists(container_name="LinOffice"):
    try:
        result = subprocess.run(
            ["podman", "ps", "-a", "--format", "{{.Names}}"],
            capture_output=True,
            text=True
        )
        return container_name in result.stdout.splitlines()
    except Exception:
        return False

def setup_successful(log_path=None):
    if log_path is None:
        log_path = str(read_data_path("setup_progress.log"))
    try:
        log_file = Path(log_path).expanduser()
        if not log_file.exists():
            return False
        with open(log_file, 'r') as file:
            return any("office_installed" in line for line in file)
    except Exception:
        return False

def start_script(script_path, working_dir=None):
    cwd = working_dir or os.path.dirname(script_path)
    subprocess.Popen([sys.executable, script_path], cwd=cwd)
    sys.exit(0)

def ask_user(message):
    msg_box = QMessageBox()
    msg_box.setText(message)
    msg_box.setStandardButtons(QMessageBox.Yes | QMessageBox.No)
    return msg_box.exec() == QMessageBox.Yes

def main():
    app = QApplication(sys.argv)

    base_dir = os.path.dirname(os.path.abspath(__file__))
    mainwindow_path = os.path.join(base_dir, "mainwindow.py")
    installer_path = os.path.join(base_dir, "installer", "installer.py")
    log_path = str(read_data_path("setup_progress.log"))

    container_found = container_exists("LinOffice")
    success = setup_successful(log_path)

    if container_found:
        if success:
            start_script(mainwindow_path)
        else:
            if ask_user("Setup might be incomplete.\nDo you want to open the installer again?"):
                start_script(installer_path, working_dir=os.path.dirname(installer_path))
            else:
                start_script(mainwindow_path)
    else:
        if success:
            if ask_user("LinOffice container can't be found.\nIt could have been deleted.\nOpen the installer again?"):
                start_script(installer_path, working_dir=os.path.dirname(installer_path))
            else:
                start_script(mainwindow_path)
        else:
            start_script(installer_path, working_dir=os.path.dirname(installer_path))

    sys.exit(app.exec())

if __name__ == "__main__":
    main()
