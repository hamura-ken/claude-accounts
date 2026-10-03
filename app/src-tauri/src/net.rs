// Сеть: живые лимиты (тот же адрес, что у /usage в Claude Code) и проверка прокси
use crate::local::{parse_usage, read_token, Usage};
use serde::Serialize;
use std::error::Error as _;
use std::time::{Duration, Instant};

const UA: &str = "claude-accounts/5.0";

fn client(proxy: &str, timeout: Duration, fresh: bool) -> Result<reqwest::Client, String> {
    let mut b = reqwest::Client::builder().timeout(timeout).connect_timeout(timeout).user_agent(UA);
    if fresh {
        // без пула соединений: иначе после смены логина прокси может переиспользоваться старый туннель
        b = b.pool_max_idle_per_host(0);
    }
    if proxy.is_empty() {
        b = b.no_proxy();
    } else {
        let u = url::Url::parse(proxy).map_err(|e| e.to_string())?;
        let host = u.host_str().ok_or("pxFormat")?;
        let port = u.port_or_known_default().unwrap_or(80);
        let mut p = reqwest::Proxy::all(format!("http://{host}:{port}")).map_err(|e| e.to_string())?;
        if !u.username().is_empty() {
            let dec = |x: &str| percent_encoding::percent_decode_str(x).decode_utf8_lossy().into_owned();
            p = p.basic_auth(&dec(u.username()), &dec(u.password().unwrap_or("")));
        }
        b = b.proxy(p);
    }
    b.build().map_err(|e| e.to_string())
}

fn chain(e: &reqwest::Error) -> String {
    let mut s = e.to_string();
    let mut src = e.source();
    while let Some(x) = src {
        s.push_str(" | ");
        s.push_str(&x.to_string());
        src = x.source();
    }
    s
}

fn error_kind(e: &reqwest::Error) -> &'static str {
    let c = chain(e).to_lowercase();
    if c.contains("407") || c.contains("proxy authentication") {
        "p407"
    } else if e.is_timeout() {
        "timeout"
    } else if c.contains("dns") || c.contains("no such host") || c.contains("name or service") {
        "pname"
    } else if c.contains("tls") || c.contains("certificate") || c.contains("schannel") {
        "tls"
    } else if e.is_connect() {
        "connect"
    } else if c.contains("connection closed") || c.contains("reset") || c.contains("eof") {
        "recv"
    } else {
        "raw"
    }
}

/// Ошибки: token (401/403 — токен протух), rate:N (429, N — секунд из Retry-After или 0), net (всё остальное)
#[tauri::command]
pub async fn fetch_usage(dir: String, proxy: String) -> Result<Usage, String> {
    let (token, _) = read_token(&dir).ok_or("token")?;
    if token.expired {
        return Err("token".into());
    }
    let c = client(&proxy, Duration::from_secs(20), false).map_err(|_| "net")?;
    let r = c
        .get("https://api.anthropic.com/api/oauth/usage")
        .bearer_auth(&token.access)
        .header("anthropic-beta", "oauth-2025-04-20")
        .send()
        .await
        .map_err(|_| "net")?;
    match r.status().as_u16() {
        200..=299 => {}
        401 | 403 => return Err("token".into()),
        429 => {
            let secs = r.headers().get("retry-after").and_then(|v| v.to_str().ok()).and_then(|s| s.trim().parse::<u64>().ok()).unwrap_or(0);
            return Err(format!("rate:{secs}"));
        }
        _ => return Err("net".into()),
    }
    let v: serde_json::Value = r.json().await.map_err(|_| "net")?;
    Ok(parse_usage(&v))
}

#[derive(Serialize, Default)]
pub struct ProxyCheck {
    ok: bool,
    /// p407 | code | timeout | connect | pname | tls | recv | raw
    kind: Option<String>,
    code: Option<u16>,
    err: Option<String>,
    ms: Option<u64>,
    ip: Option<String>,
    country: Option<String>,
    city: Option<String>,
}

#[tauri::command]
pub async fn check_proxy(proxy: String) -> ProxyCheck {
    let fail = |kind: &str, code: Option<u16>, err: Option<String>| ProxyCheck { kind: Some(kind.into()), code, err, ..Default::default() };
    let c = match client(&proxy, Duration::from_secs(12), true) {
        Ok(c) => c,
        Err(e) => return fail("raw", None, Some(e)),
    };
    let t = Instant::now();
    match c.get("https://api.anthropic.com/v1/models").send().await {
        Err(e) => return fail(error_kind(&e), None, Some(chain(&e))),
        Ok(r) => {
            let code = r.status().as_u16();
            // без ключа Anthropic отвечает 401 — это значит, что прокси до него достучался
            if code == 407 {
                return fail("p407", None, None);
            }
            if !(r.status().is_success() || [401, 403, 404].contains(&code)) {
                return fail("code", Some(code), None);
            }
        }
    }
    let ms = t.elapsed().as_millis() as u64;
    let mut res = ProxyCheck { ok: true, ms: Some(ms), ..Default::default() };
    if let Ok(c) = client(&proxy, Duration::from_secs(8), true) {
        if let Ok(r) = c.get("https://ipinfo.io/json").send().await {
            if let Ok(j) = r.json::<serde_json::Value>().await {
                let s = |k: &str| j.get(k).and_then(|x| x.as_str()).map(str::to_string);
                res.ip = s("ip");
                res.country = s("country");
                res.city = s("city");
            }
        }
    }
    res
}
