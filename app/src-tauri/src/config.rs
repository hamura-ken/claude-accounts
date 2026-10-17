// Конфиг приложения: %USERPROFILE%\.claude-switcher.json — тот же файл и формат, что у PowerShell-версии
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, UNIX_EPOCH};

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
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    pub version: u32,
    pub accounts: Vec<Account>,
    /// вся история папок запуска, свежие первыми
    pub recent: Vec<String>,
    /// когда из папки запускали в последний раз, unix ms; ключ — путь как в recent
    #[serde(default)]
    pub recent_at: BTreeMap<String, i64>,
    pub refresh_sec: u32,
    pub terminal: String,
    pub minimize_on_launch: bool,
    /// общие сессии: история всех аккаунтов в одной папке, сессию можно продолжить на другом аккаунте
    #[serde(default)]
    pub shared_sessions: bool,
    /// пустая строка — язык ещё не выбран, интерфейс возьмёт системный
    pub lang: String,
    pub theme: String,
}

pub fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("."))
}

/// CA_MAIN_DIR — подмена основной папки для тестов
pub fn default_dir() -> PathBuf {
    match std::env::var("CA_MAIN_DIR") {
        Ok(p) if !p.is_empty() => PathBuf::from(p),
        _ => home().join(".claude"),
    }
}

pub fn config_path() -> PathBuf {
    match std::env::var("CA_CFG") {
        Ok(p) if !p.is_empty() => PathBuf::from(p),
        _ => home().join(".claude-switcher.json"),
    }
}

/// копия последнего удачно прочитанного конфига
fn backup_path() -> PathBuf {
    config_path().with_extension("json.bak")
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

/// повтор для файловых операций: антивирус или другая программа могут ненадолго занять файл
fn retry<T>(mut f: impl FnMut() -> std::io::Result<T>) -> std::io::Result<T> {
    let mut left = 10;
    loop {
        match f() {
            Err(_) if left > 0 => {
                left -= 1;
                std::thread::sleep(Duration::from_millis(50));
            }
            r => return r,
        }
    }
}

fn str_of(v: &Value, k: &str) -> Option<String> {
    v.get(k).and_then(|x| x.as_str()).map(str::to_string)
}

fn bool_of(v: &Value, k: &str) -> Option<bool> {
    v.get(k).and_then(|x| x.as_bool())
}

/// отметка изменения файла конфига (unix ms), 0 — файла нет. По ней интерфейс замечает правку снаружи
pub fn stamp() -> u64 {
    std::fs::metadata(config_path())
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_millis() as u64)
}

/// содержимое конфига. Битый файл не затираем молча: откладываем его копию рядом и берём резервную
fn read_stored() -> Option<Value> {
    let path = config_path();
    if !path.exists() {
        return None;
    }
    let parsed = retry(|| std::fs::read(&path)).ok().map(|b| {
        let b = b.strip_prefix(&[0xEF, 0xBB, 0xBF][..]).unwrap_or(&b).to_vec();
        serde_json::from_slice::<Value>(&b).ok().filter(|v| v.is_object())
    });
    match parsed {
        Some(Some(v)) => Some(v),
        broken => {
            if broken.is_some() {
                let ts = chrono::Utc::now().timestamp();
                let _ = std::fs::copy(&path, path.with_extension(format!("json.broken-{ts}")));
            }
            read_json(&backup_path()).filter(|v| v.is_object())
        }
    }
}

pub fn load() -> Config {
    let mut c = Config {
        version: 3,
        accounts: vec![],
        recent: vec![],
        recent_at: BTreeMap::new(),
        refresh_sec: 300,
        terminal: "cmd".into(),
        minimize_on_launch: false,
        shared_sessions: false,
        lang: String::new(),
        theme: "system".into(),
    };
    if let Some(j) = read_stored() {
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
                });
            }
        }
        // аккаунт без папки запустился бы непонятно где
        c.accounts.retain(|a| !a.dir.trim().is_empty());
        if let Some(r) = j.get("recent").and_then(|r| r.as_array()) {
            // одна и та же папка, записанная в разном регистре, — одна запись
            let mut seen = HashSet::new();
            c.recent = r
                .iter()
                .filter_map(|x| x.as_str())
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty() && seen.insert(s.to_lowercase()))
                .collect();
        }
        if let Some(m) = j.get("recentAt").and_then(|m| m.as_object()) {
            let known: HashSet<&str> = c.recent.iter().map(String::as_str).collect();
            c.recent_at = m.iter().filter(|(k, _)| known.contains(k.as_str())).filter_map(|(k, v)| Some((k.clone(), v.as_i64()?))).collect();
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
        c.shared_sessions = bool_of(&j, "sharedSessions").unwrap_or(false);
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
        });
    }
    c
}

/// записи идут по одной: две параллельные записи одного файла на Windows падают
static SAVE_LOCK: Mutex<()> = Mutex::new(());

/// возвращает новую отметку изменения файла
pub fn save(c: &Config) -> Result<u64, String> {
    let _guard = SAVE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let path = config_path();
    let json = serde_json::to_string_pretty(c).map_err(|e| e.to_string())?;
    // через временный файл, чтобы при сбое не остаться с обрезанным конфигом
    let tmp = path.with_extension("json.tmp");
    retry(|| std::fs::write(&tmp, &json)).map_err(|e| e.to_string())?;
    // текущий конфиг, если он цел, становится резервной копией
    if read_json(&path).is_some_and(|v| v.is_object()) {
        let _ = std::fs::copy(&path, backup_path());
    }
    retry(|| std::fs::rename(&tmp, &path)).map_err(|e| e.to_string())?;
    Ok(stamp())
}

#[cfg(test)]
mod tests {
    use super::*;

    // один тест: CA_CFG — переменная процесса, параллельные тесты мешали бы друг другу
    #[test]
    fn load_save_recover() {
        let dir = std::env::temp_dir().join(format!("ca-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let cfg = dir.join("cfg.json");
        std::env::set_var("CA_CFG", &cfg);

        // дубли в разном регистре схлопываются, время запуска чужих путей отбрасывается, история не обрезается
        let many: Vec<String> = (0..30).map(|i| format!(r"C:\p{i}")).collect();
        let mut recent = vec![r"C:\A".to_string(), r"c:\a".to_string(), " ".to_string()];
        recent.extend(many.clone());
        let j = serde_json::json!({
            "accounts": [{ "name": "X", "dir": r"C:\x" }, { "name": "empty", "dir": "" }],
            "recent": recent,
            "recentAt": { r"C:\A": 5, r"C:\gone": 7 },
        });
        std::fs::write(&cfg, j.to_string()).unwrap();
        let c = load();
        assert_eq!(c.accounts.len(), 1);
        assert_eq!(c.recent.len(), 31);
        assert_eq!(c.recent[0], r"C:\A");
        assert_eq!(c.recent_at.get(r"C:\A"), Some(&5));
        assert!(!c.recent_at.contains_key(r"C:\gone"));

        // запись и чтение без потерь
        let s1 = save(&c).unwrap();
        assert!(s1 > 0 && s1 == stamp());
        assert_eq!(load().recent, c.recent);

        // второе сохранение делает резервную копию; битый файл откладывается, а читается резерв
        save(&c).unwrap();
        std::fs::write(&cfg, "{ обрезан").unwrap();
        let r = load();
        assert_eq!(r.recent, c.recent);
        let broken = std::fs::read_dir(&dir).unwrap().filter_map(|e| e.ok()).any(|e| e.file_name().to_string_lossy().contains("broken-"));
        assert!(broken);

        std::env::remove_var("CA_CFG");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
