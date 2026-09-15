//! View TUI nativa (`Show-TuiMenu.ps1`): so render + leitura de tecla, sem
//! decisao de instalacao.
//!
//! Fallback `Read-Host` quando nao ha console interativo (pipe, `--no-tui`).
//! Logica de indice pura em [`move_menu_index`] (cobre sem teclado).
//! Redesenho: no Windows volta `frame_lines` linhas a partir da linha atual
//! (`CursorTop - (N + 3)`, travado em 0) e reimprime o frame sobre ele mesmo
//! — nunca no topo absoluto do buffer (era o `MoveTo(0, 0)` que empilhava uma
//! linha por cima da outra). Sem DSR (Win32 le via API de console); no Unix
//! limpa a tela (`Clear-Host`) — la, ler `CursorTop` expoe DSR via stdin e
//! rouba bytes das setas/Enter (race).

use std::io::{self, BufRead, IsTerminal, Write};

use crate::secure::SecureStr;

/// `Move-MenuIndex`: anda e trava nas bordas.
pub fn move_menu_index(current: usize, direction: i32, count: usize) -> usize {
    if count == 0 {
        return 0;
    }
    let next = current as i64 + direction as i64;
    if next < 0 {
        0
    } else if next as usize >= count {
        count - 1
    } else {
        next as usize
    }
}

/// Predicado puro de `Test-TuiAvailable` (testavel sem console).
pub fn tui_available_with(
    no_tui: bool,
    user_interactive: bool,
    input_redirected: bool,
    console_host: bool,
) -> bool {
    if no_tui {
        return false;
    }
    if !user_interactive {
        return false;
    }
    if input_redirected {
        return false;
    }
    if !console_host {
        return false;
    }
    true
}

/// `Test-TuiAvailable`: nada de TUI sob `--no-tui`, sem stdin interativo ou
/// sem terminal.
pub fn tui_available(no_tui: bool) -> bool {
    tui_available_with(
        no_tui,
        true,
        !io::stdin().is_terminal(),
        io::stdout().is_terminal(),
    )
}

/// Parse puro do fallback numerico: vazio volta ao padrao; `1..=count`
/// vira indice 0-based; resto mantem o padrao.
pub fn parse_menu_fallback_input(raw: &str, count: usize, selected: usize) -> usize {
    if count == 0 {
        return 0;
    }
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return selected;
    }
    if let Ok(n) = trimmed.parse::<usize>() {
        if n >= 1 && n <= count {
            return n - 1;
        }
    }
    selected
}

fn clamp_default(default_index: usize, count: usize) -> usize {
    if count == 0 {
        0
    } else {
        default_index.min(count - 1)
    }
}

/// Linhas impressas por frame do menu (`Show-SingleChoiceMenu`): 1 em branco
/// + titulo + N opcoes + dica.
pub fn menu_frame_lines(option_count: usize) -> u16 {
    option_count.saturating_add(3).min(u16::MAX as usize) as u16
}

/// Linha-alvo do redesenho no Windows (paridade com o PowerShell):
/// `$top = [Console]::CursorTop - ($Options.Count + 3)`, travado em 0.
/// Sobe o relativo ao frame atual em vez do topo absoluto do buffer.
pub fn menu_redraw_top(current_row: u16, frame_lines: u16) -> u16 {
    current_row.saturating_sub(frame_lines)
}

/// Menu de escolha unica com setas + Enter (`Show-SingleChoiceMenu`).
/// Retorna o indice 0-based selecionado. Fallback: prompt numerico via
/// stdin (mesmo contrato de retorno).
pub fn show_single_choice_menu(
    title: &str,
    options: &[String],
    default_index: usize,
    no_tui: bool,
) -> usize {
    if options.is_empty() {
        return 0;
    }
    let mut selected = clamp_default(default_index, options.len());
    if !tui_available(no_tui) {
        for (i, opt) in options.iter().enumerate() {
            println!("  [{}] {}", i + 1, opt);
        }
        print!("{title} [{}]: ", selected + 1);
        let _ = io::stdout().flush();
        let mut raw = String::new();
        let stdin = io::stdin();
        if stdin.lock().read_line(&mut raw).is_ok() {
            selected = parse_menu_fallback_input(&raw, options.len(), selected);
        }
        return selected;
    }
    match interactive_menu(title, options, selected) {
        Some(idx) => idx,
        // Escape ou erro de console: mantem a selecao atual (o PowerShell
        // sai do loop no Escape sem mudar `$selected`).
        None => selected,
    }
}

fn interactive_menu(title: &str, options: &[String], initial: usize) -> Option<usize> {
    use crossterm::cursor::{Hide, MoveTo, Show};
    use crossterm::event::{read, Event, KeyCode, KeyEventKind};
    use crossterm::execute;
    #[cfg(not(windows))]
    use crossterm::terminal::{Clear, ClearType};

    let mut stdout = io::stdout();
    let mut selected = initial;
    let _ = execute!(stdout, Hide);
    let frame_lines = menu_frame_lines(options.len());

    loop {
        println!();
        println!("  {title}");
        for (i, opt) in options.iter().enumerate() {
            if i == selected {
                println!("  > [{}] {opt}", i + 1);
            } else {
                println!("    [{}] {opt}", i + 1);
            }
        }
        println!("  (setas + Enter)");
        let _ = stdout.flush();
        let event = read().ok()?;
        let mut done = false;
        let mut cancelled = false;
        if let Event::Key(key) = event {
            if key.kind == KeyEventKind::Release {
                // Ignora release; repoe o frame abaixo.
            } else {
                match key.code {
                    KeyCode::Up => {
                        selected = move_menu_index(selected, -1, options.len());
                    }
                    KeyCode::Down => {
                        selected = move_menu_index(selected, 1, options.len());
                    }
                    KeyCode::Enter => done = true,
                    KeyCode::Esc => {
                        done = true;
                        cancelled = true;
                    }
                    KeyCode::Char(c) => {
                        if let Some(d) = c.to_digit(10) {
                            let n = d as usize;
                            if n >= 1 && n <= options.len() {
                                selected = n - 1;
                                done = true;
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
        if done {
            let _ = execute!(stdout, Show);
            println!();
            return if cancelled { None } else { Some(selected) };
        }
        // Volta ao inicio do frame atual (paridade com `Show-SingleChoiceMenu`:
        // `$top = CursorTop - frame`, travado em 0). No Unix segue o
        // `Clear-Host` (ler o cursor la expoe DSR via stdin e rouba bytes das
        // setas/Enter); Win32 usa API de console real, sem race.
        #[cfg(windows)]
        {
            use crossterm::cursor::{MoveUp, position};
            match position() {
                Ok((_, row)) => {
                    let _ = execute!(stdout, MoveTo(0, menu_redraw_top(row, frame_lines)));
                }
                Err(_) => {
                    let _ = execute!(stdout, MoveUp(frame_lines));
                }
            }
        }
        #[cfg(not(windows))]
        {
            let _ = execute!(stdout, Clear(ClearType::All), MoveTo(0, 0));
            let _ = frame_lines;
        }
    }
}

/// Leitura de senha com eco de asteriscos (`Read-TuiSecurePassword`).
/// Retorna [`SecureStr`] como `Read-Host -AsSecureString`.
pub fn read_secure_password(prompt: &str, no_tui: bool) -> SecureStr {
    if !tui_available(no_tui) {
        print!("{prompt}: ");
        let _ = io::stdout().flush();
        let mut raw = String::new();
        let stdin = io::stdin();
        let _ = stdin.lock().read_line(&mut raw);
        return SecureStr::new(raw.trim_end_matches(['\r', '\n']));
    }
    match interactive_password(prompt) {
        Some(s) => s,
        None => SecureStr::new(""),
    }
}

fn interactive_password(prompt: &str) -> Option<SecureStr> {
    use crossterm::event::{read, Event, KeyCode, KeyEventKind};

    print!("{prompt}: ");
    let _ = io::stdout().flush();
    let mut secret = String::new();
    loop {
        let event = read().ok()?;
        if let Event::Key(key) = event {
            if key.kind == KeyEventKind::Release {
                continue;
            }
            match key.code {
                KeyCode::Enter => break,
                KeyCode::Backspace => {
                    if secret.pop().is_some() {
                        // Apaga o `*` (equivale a `Console::Write("`b `b")`).
                        print!("\x08 \x08");
                        let _ = io::stdout().flush();
                    }
                }
                KeyCode::Esc => {
                    secret.clear();
                    break;
                }
                KeyCode::Char(c) if !c.is_control() => {
                    secret.push(c);
                    print!("*");
                    let _ = io::stdout().flush();
                }
                _ => {}
            }
        }
    }
    println!();
    Some(SecureStr::new(secret))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamps_at_edges() {
        assert_eq!(move_menu_index(0, -1, 2), 0);
        assert_eq!(move_menu_index(1, 1, 2), 1);
    }

    #[test]
    fn moves_in_middle() {
        assert_eq!(move_menu_index(0, 1, 2), 1);
        assert_eq!(move_menu_index(1, -1, 3), 0);
    }

    #[test]
    fn empty_menu_stays_zero() {
        assert_eq!(move_menu_index(5, 1, 0), 0);
    }

    #[test]
    fn availability_predicate() {
        assert!(!tui_available_with(true, true, false, true));
        assert!(!tui_available_with(false, false, false, true));
        assert!(!tui_available_with(false, true, true, true));
        assert!(!tui_available_with(false, true, false, false));
        assert!(tui_available_with(false, true, false, true));
    }

    #[test]
    fn no_tui_flag_disables() {
        assert!(!tui_available(true));
    }

    #[test]
    fn frame_lines_counts_blank_title_options_hint() {
        assert_eq!(menu_frame_lines(0), 3);
        assert_eq!(menu_frame_lines(2), 5);
    }

    #[test]
    fn redraw_top_is_relative_never_absolute_zero() {
        // Regressao: o redesenho voltava ao topo absoluto do buffer
        // (`MoveTo(0, 0)`), empilhando o frame sobre as linhas anteriores.
        // Paridade com `$top = CursorTop - (N + 3)`: acompanha a linha atual.
        assert_eq!(menu_redraw_top(20, 5), 15);
        assert_eq!(menu_redraw_top(12, 5), 7);
    }

    #[test]
    fn redraw_top_clamps_at_zero() {
        assert_eq!(menu_redraw_top(3, 5), 0);
        assert_eq!(menu_redraw_top(0, 5), 0);
    }

    #[test]
    fn fallback_parse() {
        assert_eq!(parse_menu_fallback_input("", 2, 0), 0);
        assert_eq!(parse_menu_fallback_input("2", 2, 0), 1);
        assert_eq!(parse_menu_fallback_input("9", 2, 0), 0);
        assert_eq!(parse_menu_fallback_input("abc", 2, 1), 1);
        assert_eq!(parse_menu_fallback_input("1", 0, 0), 0);
    }
}
