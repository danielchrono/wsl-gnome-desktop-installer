//! View TUI nativa (`Show-TuiMenu.ps1`): so render + leitura de tecla, sem
//! decisao de instalacao.
//!
//! Fallback `Read-Host` quando nao ha console interativo (pipe, `--no-tui`).
//! Logica de indice pura em [`move_menu_index`] (cobre sem teclado).
//! Redesenho: no Windows reposiciona o cursor (`SetCursorPosition`, sem
//! flicker e sem DSR); no Unix limpa a tela (`Clear-Host`) — la, ler
//! `CursorTop` expoe DSR via stdin e rouba bytes das setas/Enter (race).

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
    // Linhas por frame: 1 em branco + titulo + N opcoes + dica.
    let frame_lines = (options.len() + 3) as u16;

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
        // Reposiciona sem reler o cursor no Unix (DSR rouba bytes das
        // setas/Enter); Win32 usa API de console real, sem race.
        #[cfg(windows)]
        {
            let _ = execute!(stdout, MoveTo(0, 0));
            let _ = frame_lines;
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
    fn fallback_parse() {
        assert_eq!(parse_menu_fallback_input("", 2, 0), 0);
        assert_eq!(parse_menu_fallback_input("2", 2, 0), 1);
        assert_eq!(parse_menu_fallback_input("9", 2, 0), 0);
        assert_eq!(parse_menu_fallback_input("abc", 2, 1), 1);
        assert_eq!(parse_menu_fallback_input("1", 0, 0), 0);
    }
}
