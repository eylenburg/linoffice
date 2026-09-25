#!/usr/bin/env python3
"""Simple splash window shown while the Windows container boots."""

import argparse
import sys
import time
from pathlib import Path
from typing import Optional

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import (
    QApplication,
    QLabel,
    QProgressBar,
    QVBoxLayout,
    QWidget,
)


class SplashWindow(QWidget):
    def __init__(self, title: str, icon_path: Optional[str], status_file: Path):
        super().__init__()
        self.status_file = status_file
        self.start_time = time.monotonic()

        self.setWindowTitle(title)
        self.setFixedSize(360, 160)
        self.setWindowFlags(
            Qt.WindowType.Dialog
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.CustomizeWindowHint
            | Qt.WindowType.WindowTitleHint
            | Qt.WindowType.WindowCloseButtonHint
        )

        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 16, 20, 16)
        layout.setSpacing(10)

        header = QLabel(title)
        header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        header.setStyleSheet("font-size: 14px; font-weight: 600;")
        layout.addWidget(header)

        if icon_path:
            icon_label = QLabel()
            icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            pixmap = QIcon(icon_path).pixmap(48, 48)
            if not pixmap.isNull():
                icon_label.setPixmap(pixmap)
                layout.addWidget(icon_label)

        self.status_label = QLabel("Starting Windows...")
        self.status_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.status_label.setWordWrap(True)
        layout.addWidget(self.status_label)

        self.elapsed_label = QLabel("Elapsed: 0s")
        self.elapsed_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.elapsed_label.setStyleSheet("color: gray;")
        layout.addWidget(self.elapsed_label)

        progress = QProgressBar()
        progress.setRange(0, 0)  # indeterminate
        progress.setTextVisible(False)
        layout.addWidget(progress)

        poll = QTimer(self)
        poll.timeout.connect(self._poll_status)
        poll.start(200)

        tick = QTimer(self)
        tick.timeout.connect(self._update_elapsed)
        tick.start(1000)

    def _update_elapsed(self):
        elapsed = int(time.monotonic() - self.start_time)
        self.elapsed_label.setText(f"Elapsed: {elapsed}s")

    def _poll_status(self):
        try:
            text = self.status_file.read_text(encoding="utf-8").strip()
        except OSError:
            QApplication.instance().quit()
            return

        if not text:
            return

        if text == "CLOSE":
            QApplication.instance().quit()
            return

        if text.startswith("ERROR:"):
            self.status_label.setText(text[6:].strip() or "Something went wrong.")
            QTimer.singleShot(2500, QApplication.instance().quit)
            return

        self.status_label.setText(text)


def main():
    parser = argparse.ArgumentParser(description="LinOffice startup splash")
    parser.add_argument("--title", default="Starting LinOffice")
    parser.add_argument("--icon", default="")
    parser.add_argument("--status-file", required=True)
    args = parser.parse_args()

    status_file = Path(args.status_file)
    icon_path = args.icon if args.icon and Path(args.icon).is_file() else None

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(True)

    window = SplashWindow(args.title, icon_path, status_file)
    window.show()
    # Center on the primary screen
    screen = app.primaryScreen()
    if screen is not None:
        geo = screen.availableGeometry()
        window.move(
            geo.center().x() - window.width() // 2,
            geo.center().y() - window.height() // 2,
        )

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
