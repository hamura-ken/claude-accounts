// Запуск Claude в терминале и операции с папками аккаунтов
use crate::config::{home, is_default_dir, read_json, Account};
use crate::local::global_json;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const CREATE_NEW_CONSOLE: u32 = 0x0000_0010;
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

fn find_in_path(names: &[&str]) -> bool {
    let Some(path) = std::env::var_os("PATH") else { return false };
    std::env::split_paths(&path).any(|d| names.iter().any(|n| d.join(n).is_file()))
}

#[tauri::command]
pub fn has_claude() -> bool {
    find_in_path(&["claude.exe", "claude.cmd", "claude.bat", "claude.ps1"])
}

#[tauri::command]
pub fn has_wt() -> bool {
    find_in_path(&["wt.exe"])
}

/// путь из поля «папка проекта»: пусто — домашняя папка, файл — его папка, несуществующий — None
#[tauri::command]
pub fn resolve_folder(text: String) -> Option<String> {
    let t = text.trim().trim_matches('"');
    if t.is_empty() {
        return Some(home().to_string_lossy().into_owned());
    }
    let p = Path::new(t);
    let dir = if p.is_dir() { p.to_path_buf() } else if p.is_file() { p.parent()?.to_path_buf() } else { return None };
    let abs = std::path::absolute(&dir).unwrap_or(dir);
    Some(abs.to_string_lossy().into_owned())
}

#[tauri::command]
pub fn launch(acc: Account, folder: String, terminal: String) -> Result<(), String> {
    // окружение задаём прямо в команде — так оно не зависит от того, как терминал наследует переменные
    let mut parts: Vec<String> = vec![];
    if is_default_dir(&acc.dir) {
        parts.push(r#"set "CLAUDE_CONFIG_DIR=""#.into());
    } else {
        parts.push(format!(r#"set "CLAUDE_CONFIG_DIR={}""#, acc.dir));
    }
    for var in ["HTTPS_PROXY", "HTTP_PROXY"] {
        parts.push(format!(r#"set "{var}={}""#, acc.proxy));
    }
    let clean: String = acc.name.chars().filter(|c| c.is_alphanumeric() || c.is_whitespace() || "-.#_".contains(*c)).collect();
    let title = format!("Claude - {}", clean.trim());
    parts.push(format!("title {title}"));
    let mut cmd_line = String::from("claude");
    if acc.full_access {
        cmd_line.push_str(" --dangerously-skip-permissions");
    }
    if !acc.args.trim().is_empty() {
        cmd_line.push(' ');
        cmd_line.push_str(acc.args.trim());
    }
    parts.push(cmd_line);
    let inner = parts.join(" && ");

    let res = if terminal == "wt" && has_wt() {
        Command::new("wt.exe")
            .raw_arg(format!(r#"-w new -d "{folder}" --title "{title}" cmd /k "{}""#, inner.replace(';', r"\;")))
            .creation_flags(CREATE_NO_WINDOW)
            .spawn()
    } else {
        Command::new("cmd.exe").raw_arg(format!(r#"/k "{inner}""#)).current_dir(&folder).creation_flags(CREATE_NEW_CONSOLE).spawn()
    };
    res.map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn open_path(path: String) -> Result<(), String> {
    Command::new("explorer.exe").arg(&path).spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn open_config() -> Result<(), String> {
    Command::new("notepad.exe").arg(crate::config::config_path()).spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn logout(dir: String) -> Result<(), String> {
    let p = Path::new(&dir).join(".credentials.json");
    if p.exists() {
        std::fs::remove_file(p).map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// как robocopy /E: копирует всё, ничего не удаляя в приёмнике
fn copy_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for e in std::fs::read_dir(src)? {
        let e = e?;
        let to = dst.join(e.file_name());
        if e.file_type()?.is_dir() {
            copy_dir(&e.path(), &to)?;
        } else {
            // занятый файл (например, открытый плагином) пропускаем, как robocopy /R:0
            let _ = std::fs::copy(e.path(), &to);
        }
    }
    Ok(())
}

fn copy_settings(src: &Path, dst: &Path) {
    let s = src.join("settings.json");
    if s.is_file() {
        let _ = std::fs::copy(&s, dst.join("settings.json"));
    }
    for sub in ["skills", "plugins"] {
        let s = src.join(sub);
        if s.is_dir() {
            let _ = copy_dir(&s, &dst.join(sub));
        }
    }
}

#[tauri::command]
pub fn sync_settings(src: String, dsts: Vec<String>) {
    for d in dsts {
        copy_settings(Path::new(&src), Path::new(&d));
    }
}

/// создаёт папку для нового аккаунта (.claude-accN) с настройками из первого
#[tauri::command]
pub fn create_account_dir(main_dir: String, taken: Vec<String>) -> Result<String, String> {
    let taken: Vec<String> = taken.iter().map(|t| t.to_lowercase()).collect();
    let mut i = 2;
    let dir: PathBuf = loop {
        let d = home().join(format!(".claude-acc{i}"));
        if !d.exists() && !taken.contains(&d.to_string_lossy().to_lowercase()) {
            break d;
        }
        i += 1;
    };
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    copy_settings(Path::new(&main_dir), &dir);
    // без онбординга и с теми же MCP-серверами, что у основного аккаунта
    let main = read_json(&global_json(&main_dir)).unwrap_or_default();
    let mut o = serde_json::Map::new();
    o.insert("hasCompletedOnboarding".into(), true.into());
    for k in ["lastOnboardingVersion", "mcpServers"] {
        if let Some(v) = main.get(k) {
            o.insert(k.into(), v.clone());
        }
    }
    let json = serde_json::to_string_pretty(&o).map_err(|e| e.to_string())?;
    std::fs::write(dir.join(".claude.json"), json).map_err(|e| e.to_string())?;
    Ok(dir.to_string_lossy().into_owned())
}
