#!/usr/bin/env bash
# Helper embarcado do ubuntu-gui (include_str! no Rust): subcomandos do cofre
# numa UNICA fronteira de quoting. Chega em base64 pelo argv (`echo <b64> |
# base64 -d | bash -s <sub> [args]`), sem stdin, sem sudo, sem pam.d.
#
#   probe                  sonda Locked da colecao default (2>&1: erro e diagnostico)
#   unlock-probe <senha>   unlock por stdin + sonda na MESMA chamada (daemon efemero)
#   login-create <senha>   daemon novo com --login (cria + ja destravado)
#   keyring-check <caminho>  OK / MISSING
#   version                UBUNTUGUI_HELPER_VERSION
#
# SEM pkill aqui de proposito: matar daemon e criar sao chamadas WSL
# SEPARADAS (o padrao '[g]...' nunca divide a linha com o literal, senao o
# pkill se mata - SIGTERM observado ao vivo). Quem chama orquestra.
set -u
UBUNTUGUI_HELPER_VERSION=1

probe_locked() {
  busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default org.freedesktop.Secret.Collection Locked 2>&1
}

case "${1:?subcomando}" in
  probe)
    probe_locked
    ;;
  unlock-probe)
    printf '%s' "$2" | gnome-keyring-daemon --unlock 2>&1 | tail -n 3
    ucode="${PIPESTATUS[1]}"
    probe="$(probe_locked)"
    echo "UBUNTUGUI_UNLOCKCODE=$ucode"
    echo "UBUNTUGUI_PROBE=$probe"
    ;;
  login-create)
    printf '%s' "$2" | gnome-keyring-daemon --daemonize --login >/dev/null 2>&1
    sleep 2
    probe_locked
    ;;
  keyring-check)
    if [ -f "$2" ]; then echo OK; else echo MISSING; fi
    ;;
  version)
    echo "UBUNTUGUI_HELPER_VERSION=$UBUNTUGUI_HELPER_VERSION"
    ;;
  *)
    echo "subcomando desconhecido: $1" >&2
    exit 1
    ;;
esac
