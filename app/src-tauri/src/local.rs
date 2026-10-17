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

/// Тариф из профиля, который Claude Code сам периодически обновляет: «max 5x», «max 20x», «pro».
/// subscriptionType в .credentials.json записывается при входе и после перехода с Pro на Max так и остаётся pro
fn plan_from_profile(a: &Value) -> Option<String> {
    let org = a.get("organizationType")?.as_str()?;
    let base = org.strip_prefix("claude_").unwrap_or(org);
    if base.is_empty() {
        return None;
    }
    // default_claude_max_5x → 5x; у Pro тут default_claude_ai — множителя нет
    let mult = a
        .get("organizationRateLimitTier")
        .and_then(|x| x.as_str())
        .and_then(|t| t.rsplit('_').next())
        .filter(|t| t.len() > 1 && t.ends_with('x') && t[..t.len() - 1].bytes().all(|b| b.is_ascii_digit()));
    Some(match mult {
        Some(m) => format!("{base} {m}"),
        None => base.to_string(),
    })
}

/// вызывается каждые несколько секунд для каждого аккаунта; .claude.json бывает в сотни КБ — читаем не в главном потоке
#[tauri::command]
pub async fn read_local(dir: String) -> Result<LocalInfo, String> {
    crate::blocking(move || read_local_sync(&dir)).await
}

fn read_local_sync(dir: &str) -> LocalInfo {
    let mut info = LocalInfo::default();
    if let Some((t, plan)) = read_token(dir) {
        info.logged_in = true;
        info.token_expired = t.expired;
        info.plan = plan;
    }
    if let Some(j) = read_json(&global_json(dir)) {
        let account = j.get("oauthAccount");
        info.email = account.and_then(|a| a.get("emailAddress")).and_then(|x| x.as_str()).map(str::to_string);
        if info.logged_in {
            if let Some(p) = account.and_then(plan_from_profile) {
                info.plan = Some(p);
            }
        }
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

#[cfg(test)]
mod tests {
    use super::plan_from_profile;
    use serde_json::json;

    #[test]
    fn plan_from_profile_tiers() {
        let p = |org: &str, tier: &str| plan_from_profile(&json!({ "organizationType": org, "organizationRateLimitTier": tier }));
        assert_eq!(p("claude_max", "default_claude_max_5x").as_deref(), Some("max 5x"));
        assert_eq!(p("claude_max", "default_claude_max_20x").as_deref(), Some("max 20x"));
        assert_eq!(p("claude_pro", "default_claude_ai").as_deref(), Some("pro"));
        assert_eq!(plan_from_profile(&json!({ "emailAddress": "a@b.c" })), None);
    }
}
