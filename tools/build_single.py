"""Build do WSL Gnome-Desktop Installer.

Fonte da verdade: source/ (modulo PowerShell padrao: Public/ + Private/).
NUNCA edite o .cmd a mao - edite source/ e rode:
    python3 tools/build_single.py              # regenera o .cmd + output/UbuntuGui/
    python3 tools/build_single.py --check      # so confere se esta em dia (p/ CI)
    python3 tests/test-install-ubuntu-gui.py   # regressao
"""
import hashlib
import io
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, 'source')
TOOLS_DIR = os.path.join(ROOT, 'tools')
OUT = os.path.join(ROOT, 'Install_Gnome-Desktop.cmd')
MODULE_OUT = os.path.join(ROOT, 'output', 'UbuntuGui')

# Ordem fixa: entry-head (param) -> funcoes -> entry-tail (chamada).
FUNC_FILES = [
    os.path.join('Private', 'UbuntuGui-Constants.ps1'),
    os.path.join('Private', 'Write-Feedback.ps1'),
    os.path.join('Private', 'Invoke-WslCommand.ps1'),
    os.path.join('Private', 'Invoke-VaultCredential.ps1'),
    os.path.join('Private', 'Get-PasswordQuote.ps1'),
    os.path.join('Private', 'ConvertFrom-SecureStringPlain.ps1'),
    os.path.join('Private', 'ConvertFrom-WslDistroList.ps1'),
    os.path.join('Private', 'Get-FirstIpAddress.ps1'),
    os.path.join('Private', 'Get-WslIpAddress.ps1'),
    os.path.join('Private', 'Test-WslServiceHealth.ps1'),
    os.path.join('Private', 'Test-InstallInput.ps1'),
    os.path.join('Private', 'Show-TuiMenu.ps1'),
    os.path.join('Private', 'New-RdpFileContent.ps1'),
    os.path.join('Private', 'New-LauncherContent.ps1'),
    os.path.join('Private', 'Save-ResumeState.ps1'),
    os.path.join('Private', 'New-PublisherCertificate.ps1'),
    os.path.join('Public', 'Install-WslUbuntuGui.ps1'),
    os.path.join('Public', 'Get-WslUbuntuGuiStatus.ps1'),
]
ENTRY_HEAD = os.path.join(TOOLS_DIR, 'entry-head.ps1')
ENTRY_TAIL = os.path.join(TOOLS_DIR, 'entry-tail.ps1')
LF = chr(10)


def read(path):
    return io.open(path, encoding='utf-8', newline='').read()


def build_body():
    """Script executavel completo = entry-head + funcoes + entry-tail."""
    parts = [read(ENTRY_HEAD)]
    for name in FUNC_FILES:
        p = os.path.join(SOURCE_DIR, name)
        if not os.path.isfile(p):
            raise SystemExit('fonte ausente: source/' + name)
        text = read(p)
        if not text.endswith(LF):
            raise SystemExit('fonte sem newline final: source/' + name)
        parts.append(text)
    parts.append(read(ENTRY_TAIL))
    body = ''.join(parts)
    # Carimbo deterministico: identifica o build na primeira linha do run
    # (mesmo conteudo = mesmo id; --check segue estavel).
    digest = hashlib.sha1(body.encode('utf-8')).hexdigest()[:12]
    return body.replace('__BUILD_ID__', digest)


def build_cmd():
    header = read(os.path.join(TOOLS_DIR, 'header.cmdpart'))
    footer = read(os.path.join(TOOLS_DIR, 'footer.cmdpart'))
    return header + build_body().strip() + LF + footer


def build_module():
    """Prepara output/UbuntuGui/ (formato PSGallery) a partir de source/."""
    if os.path.isdir(MODULE_OUT):
        shutil.rmtree(MODULE_OUT)
    for sub in ('Private', 'Public'):
        shutil.copytree(os.path.join(SOURCE_DIR, sub), os.path.join(MODULE_OUT, sub))
    for f in ('UbuntuGui.psd1', 'UbuntuGui.psm1'):
        shutil.copy2(os.path.join(SOURCE_DIR, f), os.path.join(MODULE_OUT, f))
    return MODULE_OUT


def main(argv):
    if '--check' in argv:
        if not os.path.isfile(OUT) or read(OUT) != build_cmd():
            print('DIVERGENTE: rode python3 tools/build_single.py')
            return 1
        print('SINCRONIZADO')
        return 0
    io.open(OUT, 'w', encoding='utf-8', newline='').write(build_cmd())
    build_module()
    print('gerado: %s + %s/' % (OUT, MODULE_OUT))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
