#!/usr/bin/env bash
# Helper embarcado do ubuntu-gui (include_str! no Rust): subcomandos do cofre
# numa UNICA fronteira de quoting. Chega em base64 pelo argv (`echo <b64> |
# base64 -d | bash -s <sub> [args]`), sem stdin, sem sudo, sem pam.d.
#
#   probe                  sonda Locked da colecao default (2>&1: erro e diagnostico)
#   unlock-probe <senha>   unlock por stdin + sonda na MESMA chamada (daemon efemero)
#   login-create <senha>   daemon novo com --login (cria + ja destravado)
#   keyring-check <caminho>  OK / MISSING
#   mirror-rank <urls...>  mede InRelease em paralelo, imprime TIME <secs|FAIL> <url>
#   mirror-set <url> <senha-sudo>  troca o host do archive (backup antes, idempotente)
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
  mirror-rank)
    # Codename nativo do /etc/os-release; so vence quem devolve 200 no
    # InRelease (URL morta perde sozinha). Paralelo => ~5s no total.
    shift
    codename="$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-}")"
    if [ -z "$codename" ]; then echo "TIME FAIL no-codename"; exit 0; fi
    tmp="$(mktemp)"
    for u in "$@"; do
      (
        out="$(curl -o /dev/null -s -w '%{http_code} %{time_total}' -L --max-time 5 "$u/dists/$codename/InRelease" 2>/dev/null)" || out="000 0"
        code="${out%% *}"; secs="${out##* }"
        if [ "$code" = "200" ]; then echo "TIME $secs $u"; else echo "TIME FAIL $u"; fi
      >>"$tmp") &
    done
    wait
    cat "$tmp"; rm -f "$tmp"
    ;;
  mirror-set)
    # Troca o host do archive nos dois formatos (DEB822 ubuntu.sources +
    # legado sources.list). Security fica como esta (CDN, pequeno). Backup
    # com timestamp ANTES (nunca cego); sem archive-url = nada a fazer
    # (KEEP converge rerun; FAIL so se o sudo falhar).
    new="$2"; pw="$3"
    result="KEEP $new"
    for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list; do
      [ -f "$f" ] || continue
      grep -q 'http://archive\.ubuntu\.com/ubuntu' "$f" || continue
      ts="$(date +%Y%m%d-%H%M%S)"
      if printf '%s\n' "$pw" | sudo -S cp "$f" "$f.bak-$ts" 2>/dev/null \
        && printf '%s\n' "$pw" | sudo -S sed -i "s|http://archive\.ubuntu\.com/ubuntu|$new|g" "$f" 2>/dev/null; then
        result="SET $new"
      else
        result="FAIL $new"; break
      fi
    done
    echo "$result"
    ;;
  version)
    echo "UBUNTUGUI_HELPER_VERSION=$UBUNTUGUI_HELPER_VERSION"
    ;;
  *)
    echo "subcomando desconhecido: $1" >&2
    exit 1
    ;;
esac
