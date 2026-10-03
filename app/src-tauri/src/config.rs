// Конфиг приложения: %USERPROFILE%\.claude-switcher.json — тот же файл и формат, что у PowerShell-версии
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::{Path, PathBuf};

pub const PALETTE_SIZE: u64 = 8;

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Account {
    pub name: String,
    pub dir: String,
    pub color: u64,
    pub proxy: String,
    pub full_access: bool,
    pub args: String,
    /// запускать терминал от имени администратора (UAC)
    #[serde(default)]
    pub admin: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    pub version: u32,
    pub accounts: Vec<Account>,
    pub recent: Vec<String>,
    pub refresh_sec: u32,
    pub terminal: String,
    pub minimize_on_launch: bool,
    /// пустая строка — язык ещё не выбран, интерфейс возьмёт системный
    pub lang: String,
    pub theme: String,
}

pub fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("."))
}

pub fn default_dir() -> PathBuf {
    home().join(".claude")
}

pub fn config_path() -> PathBuf {
    match std::env::var("CA_CFG") {
        Ok(p) if !p.is_empty() => PathBuf::from(p),
        _ => home().join(".claude-switcher.json"),
    }
}

fn norm(p: &Path) -> String {
    let s = std::path::absolute(p).unwrap_or_else(|_| p.to_path_buf());
    s.to_string_lossy().trim_end_matches('\\').to_lowercase()
}

pub fn is_default_dir(dir: &str) -> bool {
    norm(Path::new(dir)) == norm(&default_dir())
}

/// читает файл, который Claude Code может держать открытым; убирает BOM
pub fn read_text(path: &Path) -> Option<String> {
    let bytes = std::fs::read(path).ok()?;
    let bytes = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF][..]).unwrap_or(&bytes);
    Some(String::from_utf8_lossy(bytes).into_owned())
}

pub fn read_json(path: &Path) -> Option<Value> {
    serde_json::from_str(&read_text(path)?).ok()
}

fn str_of(v: &Value, k: &str) -> Option<String> {
    v.get(k).and_then(|x| x.as_str()).map(str::to_string)
}

fn bool_of(v: &Value, k: &str) -> Option<bool> {
    v.get(k).and_then(|x| x.as_bool())
}

pub fn load() -> Config {
    let mut c = Config {
        version: 3,
        accounts: vec![],
        recent: vec![],
        refresh_sec: 300,
        terminal: "cmd".into(),
        minimize_on_launch: false,
        lang: String::new(),
        theme: "system".into(),
    };
    if let Some(j) = read_json(&config_path()) {
        // миграция с v2: общий прокси и полный доступ переезжают в каждый аккаунт
        let g_proxy = match (str_of(&j, "proxy"), bool_of(&j, "useProxy")) {
            (Some(p), use_p) if use_p != Some(false) => p,
            _ => String::new(),
        };
        let g_full = bool_of(&j, "fullAccess").unwrap_or(true);
        if let Some(arr) = j.get("accounts").and_then(|a| a.as_array()) {
            for (i, a) in arr.iter().filter(|a| a.is_object()).enumerate() {
                c.accounts.push(Account {
                    name: str_of(a, "name").unwrap_or_default(),
                    dir: str_of(a, "dir").unwrap_or_default(),
                    color: a.get("color").and_then(|x| x.as_u64()).unwrap_or(i as u64 % PALETTE_SIZE),
                    proxy: str_of(a, "proxy").unwrap_or_else(|| g_proxy.clone()),
                    full_access: bool_of(a, "fullAccess").unwrap_or(g_full),
                    args: str_of(a, "args").unwrap_or_default(),
                    admin: bool_of(a, "admin").unwrap_or(false),
                });
            }
        }
        if let Some(r) = j.get("recent").and_then(|r| r.as_array()) {
            c.recent = r.iter().filter_map(|x| x.as_str()).filter(|s| !s.is_empty()).map(str::to_string).collect();
        }
        if let Some(n) = j.get("refreshSec").and_then(|x| x.as_u64()) {
            // реже раза в 5 минут — чтобы не упираться в лимит частоты запросов Anthropic
            c.refresh_sec = n.clamp(300, 3600) as u32;
        }
        if let Some(t) = str_of(&j, "terminal") {
            c.terminal = t;
        }
        if let Some(m) = bool_of(&j, "minimizeOnLaunch") {
            c.minimize_on_launch = m;
        }
        if let Some(l) = str_of(&j, "lang").filter(|l| l == "ru" || l == "en") {
            c.lang = l;
        }
        if let Some(t) = str_of(&j, "theme").filter(|t| ["dark", "light", "system"].contains(&t.as_str())) {
            c.theme = t;
        }
    }
    if c.accounts.is_empty() {
        c.accounts.push(Account {
            name: "Account 1".into(),
            dir: default_dir().to_string_lossy().into_owned(),
            color: 0,
            proxy: String::new(),
            full_access: true,
            args: String::new(),
            admin: false,
        });
    }
    c
}

pub fn save(c: &Config) -> Result<(), String> {
    let path = config_path();
    let json = serde_json::to_string_pretty(c).map_err(|e| e.to_string())?;
    // через временный файл, чтобы при сбое не остаться с обрезанным конфигом
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, json).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &path).map_err(|e| e.to_string())
}
