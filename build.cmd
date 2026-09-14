@echo off
rem Atalho de build: acorda tools/build_single.py (fonte da verdade: source/).
rem Uso: build.cmd  (regenera)  ou  build.cmd --check  (so confere, p/ CI)
python3 "%~dp0tools\build_single.py" %*
