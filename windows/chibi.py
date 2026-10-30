"""Desktop chibi for Windows.

Hosts Chibi.qml in a Qt Quick engine and adds what Quickshell provided on
Linux: the global cursor position, the sprites folder and a tray icon to put
her to sleep, wake her or quit (the window itself has no taskbar entry).

It also carries the UDP link to her twin on the Linux PC, speaking the same
JSON messages as ../bin/chibi-link. Config: link.json next to chibi.exe (or
chibi.py), or %APPDATA%\\danso-chibi\\link.json:
  {"peer": "172.16.11.194", "port": 47800, "side": "right", "primary": false}
side: where the Linux PC sits relative to this one (as arranged in Deskflow).
Without a config file she simply stays on this PC.
"""

import json
import os
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QPointF, QUrl, Signal, Slot, Property
from PySide6.QtGui import QAction, QCursor, QIcon, QPixmap
from PySide6.QtNetwork import QAbstractSocket, QHostAddress, QHostInfo, QUdpSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon


def resource_dir() -> Path:
    """Folder holding Chibi.qml and sprites/, inside a PyInstaller bundle too."""
    if hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)
    return Path(__file__).resolve().parent


def sprites_dir() -> Path:
    bundled = resource_dir() / "sprites"
    return bundled if bundled.is_dir() else resource_dir().parent / "sprites"


def load_link_config() -> dict | None:
    app_dir = Path(sys.executable).parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent
    candidates = [app_dir / "link.json"]
    if os.environ.get("APPDATA"):
        candidates.append(Path(os.environ["APPDATA"]) / "danso-chibi" / "link.json")
    for path in candidates:
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError):
            continue
    return None


class Bridge(QObject):
    sleepRequested = Signal(bool)
    messageReceived = Signal(str)

    def __init__(self, sprites: Path, link: dict | None):
        super().__init__()
        self._sprites_url = QUrl.fromLocalFile(str(sprites)).toString()
        self._socket = None
        self._peer = None
        self._port = 47800
        self._side = "right"
        self._primary = False
        if link and link.get("peer"):
            self._open_link(link)

    def _open_link(self, link: dict) -> None:
        # The socket is IPv4 only, so a hostname must resolve to IPv4 too.
        addresses = [a for a in QHostInfo.fromName(str(link["peer"])).addresses()
                     if a.protocol() == QAbstractSocket.NetworkLayerProtocol.IPv4Protocol]
        if not addresses:
            print(f"chibi: cannot resolve peer {link['peer']} to IPv4, link disabled", file=sys.stderr)
            return
        self._peer = addresses[0]
        try:
            self._port = int(link.get("port", 47800))
        except ValueError:
            print("chibi: invalid port, link disabled", file=sys.stderr)
            return
        self._side = "left" if link.get("side") == "left" else "right"
        self._primary = bool(link.get("primary", False))
        self._socket = QUdpSocket(self)
        if not self._socket.bind(QHostAddress.AnyIPv4, self._port, QUdpSocket.ShareAddress | QUdpSocket.ReuseAddressHint):
            print(f"chibi: cannot bind UDP {self._port}, link disabled", file=sys.stderr)
            self._socket = None
            return
        self._socket.readyRead.connect(self._read)

    def _read(self) -> None:
        while self._socket.hasPendingDatagrams():
            datagram = self._socket.receiveDatagram()
            if datagram.senderAddress().isEqual(self._peer, QHostAddress.TolerantConversion):
                self.messageReceived.emit(bytes(datagram.data()).decode(errors="replace"))

    @Slot(str)
    def send(self, text: str) -> None:
        if self._socket:
            self._socket.writeDatagram(text.encode(), self._peer, self._port)

    @Property(bool, constant=True)
    def linkEnabled(self) -> bool:
        return self._socket is not None

    @Property(str, constant=True)
    def peerSide(self) -> str:
        return self._side

    @Property(bool, constant=True)
    def primary(self) -> bool:
        return self._primary

    @Slot(result=QPointF)
    def cursorPos(self) -> QPointF:
        return QPointF(QCursor.pos())

    @Property(str, constant=True)
    def spritesUrl(self) -> str:
        return self._sprites_url


def build_tray(app: QApplication, bridge: Bridge, sprites: Path) -> QSystemTrayIcon:
    icon = QIcon(QPixmap(str(sprites / "idle.png")).copy(0, 0, 83, 132))
    tray = QSystemTrayIcon(icon, app)
    tray.setToolTip("Desktop chibi")

    menu = QMenu()
    sleep = QAction("Dormir", menu)
    sleep.triggered.connect(lambda: bridge.sleepRequested.emit(True))
    wake = QAction("Despertar", menu)
    wake.triggered.connect(lambda: bridge.sleepRequested.emit(False))
    quit_ = QAction("Salir", menu)
    quit_.triggered.connect(app.quit)
    menu.addActions([sleep, wake])
    menu.addSeparator()
    menu.addAction(quit_)

    tray.setContextMenu(menu)
    tray.show()
    return tray


def main() -> int:
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    sprites = sprites_dir()
    bridge = Bridge(sprites, load_link_config())

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("bridge", bridge)
    engine.load(QUrl.fromLocalFile(str(resource_dir() / "Chibi.qml")))
    if not engine.rootObjects():
        return 1

    # Keep a reference so the tray icon is not garbage collected.
    tray = build_tray(app, bridge, sprites)  # noqa: F841
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
