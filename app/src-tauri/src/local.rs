// Локальные данные аккаунта: логин из .credentials.json и кэш лимитов, который пишет сам Claude Code
use crate::config::{home, is_default_dir, read_json};
use serde::Serialize;
use serde_json::Value;
use std::path::{Path, PathBuf};

#[derive(Serialize, Clone, Debug)]
pub struct Limit {
    /// процент использования 0..100
    pub pct: f64,
    /// время сброса, unix ms
    pub reset: Option<i64>,
}

#[derive(Serialize, Clone, Debug, Default)]
pub struct Usage {
    pub five: Option<Limit>,
    pub week: Option<Limit>,
}

#[derive(Serialize, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub struct LocalInfo {
    pub logged_in: bool,
    pub token_expired: bool,
    pub plan: Option<String>,
    pub email: Option<String>,
    pub cache: Option<Usage>,
    /// когда Claude Code получил кэш, unix ms
    pub cache_at: Option<i64>,
}

pub fn global_json(dir: &str) -> PathBuf {
    if is_default_dir(dir) { home().join(".claude.json") } else { Path::new(dir).join(".claude.json") }
}

pub fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

fn parse_limit(v: Option<&Value>) -> Option<Limit> {
    let v = v?;
    if v.is_null() {
        return None;
    }
    let reset = match v.get("resets_at") {
        Some(Value::String(s)) => chrono::DateTime::parse_from_rfc3339(s).ok().map(|d| d.timestamp_millis()),
        Some(Value::Number(n)) => n.as_i64().map(|x| if x < 100_000_000_000 { x * 1000 } else { x }),
        _ => None,
    };
    Some(Limit { pct: v.get("utilization").and_then(|x| x.as_f64()).unwrap_or(0.0), reset })
}

pub fn parse_usage(v: &Value) -> Usage {
    Usage { five: parse_limit(v.get("five_hour")), week: parse_limit(v.get("seven_day")) }
}

pub struct Token {
    pub access: String,
    pub expired: bool,
}

pub fn read_token(dir: &str) -> Option<(Token, Option<String>)> {
    let j = read_json(&Path::new(dir).join(".credentials.json"))?;
    let c = j.get("claudeAiOauth")?;
    let access = c.get("accessToken")?.as_str()?.to_string();
    if access.is_empty() {
        return None;
    }
    let expired = c.get("expiresAt").and_then(|x| x.as_i64()).map(|e| e < now_ms() + 30_000).unwrap_or(false);
    let plan = c.get("subscriptionType").and_then(|x| x.as_str()).map(str::to_string);
    Some((Token { access, expired }, plan))
}

#[tauri::command]
pub fn read_local(dir: String) -> LocalInfo {
    let mut info = LocalInfo::default();
    if let Some((t, plan)) = read_token(&dir) {
        info.logged_in = true;
        info.token_expired = t.expired;
        info.plan = plan;
    }
    if let Some(j) = read_json(&global_json(&dir)) {
        let account = j.get("oauthAccount");
        info.email = account.and_then(|a| a.get("emailAddress")).and_then(|x| x.as_str()).map(str::to_string);
        // кэш берём, только если он от того же аккаунта, что залогинен сейчас
        if info.logged_in {
            if let Some(u) = j.get("cachedUsageUtilization") {
                let same = match account.and_then(|a| a.get("accountUuid")) {
                    Some(id) => u.get("accountUuid") == Some(id),
                    None => true,
                };
                if let (true, Some(util)) = (same, u.get("utilization")) {
                    info.cache = Some(parse_usage(util));
                    info.cache_at = u.get("fetchedAtMs").and_then(|x| x.as_i64());
                }
            }
        }
    }
    info
}
