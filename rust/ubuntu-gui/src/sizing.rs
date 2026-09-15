//! Dimensionamento da sessao/janela a partir do monitor (nada hardcoded).
//!
//! Todo numero deriva da area util detectada na instalacao; estas funcoes sao
//! puras para serem testadas em qualquer plataforma:
//! deteccao -> [`session_size`] -> [`window_size`], com [`fit_bars`]
//! prevendo escala e tarjas para qualquer janela (`escala =
//! min(Ljanela/Lsessao, Ajanela/Asessao)`; tarja zero so com mesmo aspecto).

/// Converte o retangulo da area util em (largura, altura), sem underflow.
pub fn work_area_to_size(left: i32, top: i32, right: i32, bottom: i32) -> Option<(u32, u32)> {
    let w = right.saturating_sub(left);
    let h = bottom.saturating_sub(top);
    if w > 0 && h > 0 {
        Some((w as u32, h as u32))
    } else {
        None
    }
}

/// Sessao RDP = area util: o maximizado fica 1:1 (sem scroll, sem blur).
pub fn session_size(work_area: (u32, u32)) -> (u32, u32) {
    work_area
}

/// Janela inicial (`/w /h`) = sessao: abre exato, sem sobra inicial.
pub fn window_size(session: (u32, u32)) -> (u32, u32) {
    session
}

/// `(escala, tarja_horizontal, tarja_vertical)` para caber `sessao` em
/// `janela` com zoom uniforme. Tarjas em px totais (metade de cada lado).
/// Degenerado (algum lado 0) devolve `(1.0, 0, 0)`.
pub fn fit_bars(session: (u32, u32), window: (u32, u32)) -> (f64, u32, u32) {
    let (sw, sh) = (session.0 as f64, session.1 as f64);
    let (ww, wh) = (window.0 as f64, window.1 as f64);
    if sw <= 0.0 || sh <= 0.0 || ww <= 0.0 || wh <= 0.0 {
        return (1.0, 0, 0);
    }
    let scale = (ww / sw).min(wh / sh);
    let dw = ww - sw * scale;
    let dh = wh - sh * scale;
    (
        scale,
        dw.max(0.0).round() as u32,
        dh.max(0.0).round() as u32,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn work_area_sizes_without_underflow() {
        // Area util tipica (tela menos barra de tarefas).
        assert_eq!(work_area_to_size(0, 0, 1600, 852), Some((1600, 852)));
        assert_eq!(work_area_to_size(0, 0, 0, 0), None);
        // Retangulo invertido nao estoura para u32 gigante.
        assert_eq!(work_area_to_size(100, 100, 50, 50), None);
    }

    #[test]
    fn session_and_window_follow_work_area() {
        // Politica do "combinado": sessao = area util, janela = sessao.
        assert_eq!(session_size((1600, 852)), (1600, 852));
        assert_eq!(window_size((1600, 852)), (1600, 852));
    }

    #[test]
    fn fit_bars_zeroes_on_same_aspect() {
        // Maximizado exato: escala 1, sem tarja.
        assert_eq!(fit_bars((1600, 852), (1600, 852)), (1.0, 0, 0));
        // 16:9 arrastado numa sessao 16:9 tambem zera.
        let (s, dw, dh) = fit_bars((1600, 900), (1280, 720));
        assert!((s - 0.8).abs() < 1e-9);
        assert_eq!((dw, dh), (0, 0));
    }

    #[test]
    fn fit_bars_predicts_mismatch() {
        // Sessao 852 em janela 16:9 cheia: sobra vertical de 48px.
        let (s, dw, dh) = fit_bars((1600, 852), (1600, 900));
        assert!((s - 1.0).abs() < 1e-9);
        assert_eq!((dw, dh), (0, 48));
        // Degenerado nao quebra.
        assert_eq!(fit_bars((1600, 852), (0, 0)), (1.0, 0, 0));
        assert_eq!(fit_bars((0, 0), (1600, 852)), (1.0, 0, 0));
    }
}
