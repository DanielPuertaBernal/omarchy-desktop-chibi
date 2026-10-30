# Builds dist\chibi.exe: a single file with Python, Qt and the sprites inside.
# Run from this folder in PowerShell:  .\build.ps1
$ErrorActionPreference = "Stop"

python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt

.\.venv\Scripts\pyinstaller --noconfirm --onefile --windowed --name chibi `
  --add-data "Chibi.qml;." `
  --add-data "..\sprites;sprites" `
  chibi.py

Write-Host "Listo: dist\chibi.exe"
