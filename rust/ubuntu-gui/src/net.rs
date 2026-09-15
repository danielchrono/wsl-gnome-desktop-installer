//! Selecao de porta RDP (`Test-RdpPort` nao existia no PS; funcao nova).
//!
//! Mapeamento MVVM (igual a `ip.rs` e `input.rs`):
//!
//! - ViewModel puro: [`is_port_in_use`] (testa a conexao TCP), [`choose_rdp_port`]
//!   (politica: porta livre = usa; ocupada = fallback). Sem I/O de console,
//!   sem mutacao de global, sem mensagem — o orquestrador decide o `Warn`.
//! - Execucao real atras de `cfg(windows)`: so para a sonda TCP; a politica
//!   ([`choose_rdp_port`]) e pura em qualquer SO.
//!
//! FP: [`PortChoice`] e um valor imutavel retornado pelo ViewModel; o chamador
//! interpreta os campos e decide mensagem/throw — nunca o contrario.

use std::time::Duration;

/// Resultado da selecao de porta (ViewModel puro, sem I/O).
///
/// Analogo a [`crate::input::NetworkChoice`]: retorna dados, nao decisoes de UI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PortChoice {
    /// Porta efetivamente escolhida (pode diferir de `requested` se ocupada).
    pub port: u16,
    /// `true` quando `requested` estava ocupada e `fallback` foi usado.
    pub fell_back: bool,
    /// Porta originalmente solicitada (para a mensagem de aviso no chamador).
    pub requested: u16,
    /// Porta alternativa configurada (para a mensagem de aviso no chamador).
    pub fallback: u16,
}

/// Verifica se uma porta TCP esta em uso (ViewModel puro; I/O real so no Windows).
///
/// Equivale ao `Test-NetConnection -InformationLevel Quiet` do PowerShell, mas
/// com timeout explicito para nao travar o instalador. Retorna `false` em qualquer
/// plataforma que nao seja Windows (testes no Linux sempre veem a porta como livre).
#[cfg(windows)]
pub fn is_port_in_use(host: &str, port: u16, timeout_ms: u64) -> bool {
    use std::net::{SocketAddr, TcpStream};
    let addr: SocketAddr = match format!("{host}:{port}").parse() {
        Ok(a) => a,
        Err(_) => return false,
    };
    TcpStream::connect_timeout(&addr, Duration::from_millis(timeout_ms)).is_ok()
}

/// Fora do Windows a sonda nao faz sentido: retorna `false` (porta "livre")
/// para nao quebrar os testes de politica ([`choose_rdp_port`]) no Linux.
#[cfg(not(windows))]
pub fn is_port_in_use(_host: &str, _port: u16, _timeout_ms: u64) -> bool {
    false
}

/// Politica de selecao de porta RDP (ViewModel puro, testavel sem WSL).
///
/// - Se `requested` estiver livre (ou nao houver listener): retorna `requested`,
///   `fell_back = false`.
/// - Se `requested` estiver ocupada: retorna `fallback`, `fell_back = true`.
///
/// O chamador e responsavel por emitir o `Warn` quando `fell_back == true`
/// (FP: sem efeito colateral aqui; a mensagem pertence ao orquestrador).
pub fn choose_rdp_port(requested: u16, fallback: u16, timeout_ms: u64) -> PortChoice {
    select_first_free(requested, &[requested, fallback], &|p| {
        is_port_in_use("127.0.0.1", p, timeout_ms)
    })
}

/// Primeira livre na ordem dos candidatos (puro, testavel sem rede).
///
/// `candidates[0]` deve ser a porta pedida; as demais, fallbacks em ordem.
/// O probe (`is_in_use`) e injetado para os testes nao dependerem de socket;
/// em producao e `is_port_in_use("127.0.0.1", p, timeout)`.
/// Tudo ocupado = ultimo candidato (o chamador valida e falha com diagnostico).
pub fn select_first_free(
    requested: u16,
    candidates: &[u16],
    is_in_use: &dyn Fn(u16) -> bool,
) -> PortChoice {
    let fallback = candidates
        .iter()
        .copied()
        .find(|&c| c != requested)
        .unwrap_or(requested);
    if !is_in_use(requested) {
        return PortChoice {
            port: requested,
            fell_back: false,
            requested,
            fallback,
        };
    }
    for &c in candidates {
        if c != requested && !is_in_use(c) {
            return PortChoice {
                port: c,
                fell_back: true,
                requested,
                fallback,
            };
        }
    }
    let last = candidates.iter().copied().last().unwrap_or(requested);
    PortChoice {
        port: if last == requested { fallback } else { last },
        fell_back: true,
        requested,
        fallback,
    }
}

/// Reaproveita a porta pedida quando o ocupante e o nosso proprio RDP.
///
/// O probe de loopback nao distingue "nosso RDP" (mirrored expoe o convidado
/// no 127.0.0.1 do host) de invasor: sem isso cada rerun saltava de porta.
/// O orquestrador confirma no convidado (`ss` + servico ativo) e so entao
/// volta para a pedida.
pub fn should_reuse_requested(fell_back: bool, guest_listening_on_requested: bool) -> bool {
    fell_back && guest_listening_on_requested
}

/// Varredura `[requested, fallback, fallback+1, ...]`: um fallback unico
/// queimava uma porta por rerun — o probe de loopback via o proprio RDP da
/// execucao anterior (mirrored expoe o convidado no 127.0.0.1 do host) e
/// saltava de novo a cada vez.
pub fn choose_rdp_port_scan(
    requested: u16,
    fallback: u16,
    extra: u16,
    timeout_ms: u64,
) -> PortChoice {
    let mut candidates = vec![requested];
    for i in 0..extra {
        let p = fallback.saturating_add(i);
        if p != requested {
            candidates.push(p);
        }
    }
    if candidates.len() == 1 {
        candidates.push(fallback);
    }
    select_first_free(requested, &candidates, &|p| {
        is_port_in_use("127.0.0.1", p, timeout_ms)
    })
}

/// Suprime o warning de `Duration` importada mas nunca usada fora do `cfg(windows)`.
#[allow(dead_code)]
const _: Duration = Duration::from_millis(0);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn free_port_is_not_in_use() {
        // Bind em :0 pega uma porta livre; depois fechamos o listener e
        // testamos a mesma porta — deve estar livre agora.
        let port = {
            let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            l.local_addr().unwrap().port()
            // listener dropado aqui: porta fica livre
        };
        assert!(!is_port_in_use("127.0.0.1", port, 500));
    }

    #[cfg(windows)]
    #[test]
    fn occupied_port_is_detected() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        // listener ainda vivo: porta ocupada
        assert!(is_port_in_use("127.0.0.1", port, 500));
    }

    // --- politica (pura, testavel em qualquer SO) ---

    #[test]
    fn choose_uses_requested_when_free() {
        // Porta livre: espera-se que `choose_rdp_port` retorne `requested`.
        // Em plataformas nao-Windows `is_port_in_use` sempre retorna `false`
        // (porta "livre"), entao o test passa em qualquer SO.
        let port = {
            let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            l.local_addr().unwrap().port()
        };
        let choice = choose_rdp_port(port, 9999, 500);
        assert_eq!(choice.port, port);
        assert!(!choice.fell_back);
        assert_eq!(choice.requested, port);
        assert_eq!(choice.fallback, 9999);
    }

    #[cfg(windows)]
    #[test]
    fn choose_falls_back_when_occupied() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let occupied = listener.local_addr().unwrap().port();
        // porta diferente como fallback
        let fallback = {
            let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            l.local_addr().unwrap().port()
        };
        let choice = choose_rdp_port(occupied, fallback, 500);
        assert_eq!(choice.port, fallback);
        assert!(choice.fell_back);
        assert_eq!(choice.requested, occupied);
    }

    #[test]
    fn port_choice_fields_are_always_populated() {
        // Campos de diagnostico (para a mensagem de Warn do chamador).
        let c = choose_rdp_port(3389, 3390, 100);
        assert_eq!(c.requested, 3389);
        assert_eq!(c.fallback, 3390);
        // `port` e sempre um dos dois
        assert!(c.port == 3389 || c.port == 3390);
    }

    #[test]
    fn scan_keeps_requested_when_free() {
        let c = select_first_free(3390, &[3390, 3391, 3392], &|_| false);
        assert_eq!(c.port, 3390);
        assert!(!c.fell_back);
        assert_eq!((c.requested, c.fallback), (3390, 3391));
    }

    #[test]
    fn scan_takes_first_free_fallback() {
        // 3390 e 3391 ocupadas: cai na 3392, nao queima so uma por vez.
        let busy = |p: u16| p == 3390 || p == 3391;
        let c = select_first_free(3390, &[3390, 3391, 3392], &busy);
        assert_eq!(c.port, 3392);
        assert!(c.fell_back);
        assert_eq!((c.requested, c.fallback), (3390, 3391));
    }

    #[test]
    fn reuse_only_when_fell_back_and_guest_owns_port() {
        assert!(should_reuse_requested(true, true));
        assert!(!should_reuse_requested(true, false));
        assert!(!should_reuse_requested(false, true));
        assert!(!should_reuse_requested(false, false));
    }

    #[test]
    fn scan_probes_in_candidate_order() {
        let seen = std::cell::RefCell::new(Vec::new());
        let c = select_first_free(3390, &[3390, 3391, 3392], &|p| {
            seen.borrow_mut().push(p);
            true
        });
        assert_eq!(*seen.borrow(), vec![3390, 3391, 3392]);
        // Tudo ocupado: fica no ultimo (o chamador valida e falha).
        assert_eq!(c.port, 3392);
        assert!(c.fell_back);
    }
}
