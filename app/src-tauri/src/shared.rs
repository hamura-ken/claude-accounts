// Общие сессии: папки с историей у всех аккаунтов — ссылки (junction) на папки основного ~/.claude.
// Сессия, начатая на одном аккаунте, продолжается на другом через claude --continue / --resume
use crate::config::{default_dir, home, is_default_dir};
use serde::Serialize;
use std::fs;
use std::io;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

/// projects — сессии и память проектов, file-history — точки отката правок,
/// plans и todos — планы и списки задач сессий
const SHARED: [&str; 4] = ["projects", "file-history", "plans", "todos"];

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

fn norm(p: &Path) -> String {
    let s = p.to_string_lossy();
    let s = s.strip_prefix(r"\\?\").unwrap_or(&s);
    s.trim_end_matches('\\').to_lowercase()
}

fn is_linked(link: &Path, target: &Path) -> bool {
    fs::read_link(link).is_ok_and(|t| norm(&t) == norm(target))
}

fn same_content(a: &Path, b: &Path) -> bool {
    match (fs::metadata(a), fs::metadata(b)) {
        // большие файлы не сравниваем побайтно — считаем разными, старший уйдёт в резерв
        (Ok(x), Ok(y)) if x.len() == y.len() && x.len() < 64 << 20 => fs::read(a).ok() == fs::read(b).ok(),
        _ => false,
    }
}

fn mtime(p: &Path) -> std::time::SystemTime {
    fs::metadata(p).and_then(|m| m.modified()).unwrap_or(std::time::UNIX_EPOCH)
}

/// Переносит содержимое src в dst. Чего в dst нет — переезжает; одноимённое и одинаковое — дубль удаляется;
/// одноимённое и разное — в dst остаётся более свежее, второе уходит в backup. Ничего не теряется
fn merge(src: &Path, dst: &Path, backup: &Path) -> io::Result<()> {
    fs::create_dir_all(dst)?;
    for e in fs::read_dir(src)? {
        let e = e?;
        let name = e.file_name();
        let (from, to) = (e.path(), dst.join(&name));
        let ft = e.file_type()?;
        if ft.is_dir() && !ft.is_symlink() && to.is_dir() {
            merge(&from, &to, &backup.join(&name))?;
            // не пусто — значит, что-то не перенеслось; это заметит проверка в link_account
            let _ = fs::remove_dir(&from);
        } else if fs::symlink_metadata(&to).is_err() {
            fs::rename(&from, &to)?;
        } else if ft.is_file() && to.is_file() && same_content(&from, &to) {
            fs::remove_file(&from)?;
        } else if ft.is_file() && to.is_file() && name.eq_ignore_ascii_case("MEMORY.md") {
            // индекс памяти проекта: у каждого аккаунта свои пункты, поэтому объединяем строки, а не выбираем один файл
            let (a, b) = (fs::read_to_string(&to)?, fs::read_to_string(&from)?);
            let (base, extra) = if mtime(&from) > mtime(&to) { (b, a) } else { (a, b) };
            fs::write(&to, union_lines(&base, &extra))?;
            fs::create_dir_all(backup)?;
            fs::rename(&from, backup.join(&name))?;
        } else {
            fs::create_dir_all(backup)?;
            if ft.is_file() && to.is_file() && mtime(&from) > mtime(&to) {
                fs::rename(&to, backup.join(&name))?;
                fs::rename(&from, &to)?;
            } else {
                fs::rename(&from, backup.join(&name))?;
            }
        }
    }
    Ok(())
}

/// base целиком, затем строки extra, которых в base нет
fn union_lines(base: &str, extra: &str) -> String {
    let have: std::collections::HashSet<&str> = base.lines().map(str::trim_end).collect();
    let mut out = base.trim_end().to_string();
    for l in extra.lines().map(str::trim_end).filter(|l| !l.trim().is_empty() && !have.contains(l)) {
        out.push('\n');
        out.push_str(l);
    }
    out.push('\n');
    out
}

/// junction создаётся без прав администратора, в отличие от символической ссылки
fn junction(link: &Path, target: &Path) -> Result<(), String> {
    let out = Command::new("cmd.exe")
        .args(["/c", "mklink", "/J"])
        .arg(link)
        .arg(target)
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() && is_linked(link, target) {
        Ok(())
    } else {
        Err(format!("mklink {}: {}", link.display(), String::from_utf8_lossy(&out.stderr).trim()))
    }
}

fn link_account(dir: &Path, backup: &Path) -> Result<(), String> {
    for sub in SHARED {
        let target = default_dir().join(sub);
        fs::create_dir_all(&target).map_err(|e| e.to_string())?;
        let link = dir.join(sub);
        if is_linked(&link, &target) {
            continue;
        }
        if let Ok(md) = fs::symlink_metadata(&link) {
            if md.file_type().is_symlink() {
                // ссылка куда-то ещё — заменяем; remove_dir удаляет саму ссылку, а не то, на что она ведёт
                fs::remove_dir(&link).map_err(|e| e.to_string())?;
            } else if md.is_dir() {
                merge(&link, &target, &backup.join(sub)).map_err(|e| format!("{}: {e}", link.display()))?;
                // осталось что-то занятое (открыт запущенным Claude) — ссылку не ставим, повторим позже
                fs::remove_dir(&link).map_err(|_| format!("busy:{}", link.display()))?;
            } else {
                return Err(format!("{} is a file", link.display()));
            }
        }
        junction(&link, &target)?;
    }
    Ok(())
}

fn unlink_account(dir: &Path) -> Result<(), String> {
    for sub in SHARED {
        let link = dir.join(sub);
        if fs::symlink_metadata(&link).is_ok_and(|m| m.file_type().is_symlink()) {
            fs::remove_dir(&link).map_err(|e| e.to_string())?;
            fs::create_dir_all(&link).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

fn is_shared(dir: &Path) -> bool {
    SHARED.iter().all(|sub| is_linked(&dir.join(sub), &default_dir().join(sub)))
}

#[derive(Serialize, Default)]
pub struct ShareReport {
    /// аккаунты, у которых что-то не получилось: «папка: причина»
    errors: Vec<String>,
    /// куда ушли одноимённые, но разные файлы (если такие были)
    backup: Option<String>,
}

/// основной аккаунт (~/.claude) и есть общее хранилище — у него ничего не меняется
fn others(dirs: Vec<String>) -> impl Iterator<Item = String> {
    dirs.into_iter().filter(|d| !d.trim().is_empty() && !is_default_dir(d))
}

#[tauri::command]
pub async fn share_sessions(dirs: Vec<String>) -> Result<ShareReport, String> {
    crate::blocking(move || {
        let backup: PathBuf = home().join(".claude-shared-backup").join(chrono::Local::now().format("%Y%m%d-%H%M%S").to_string());
        let mut r = ShareReport::default();
        for d in others(dirs) {
            if let Err(e) = link_account(Path::new(&d), &backup.join(Path::new(&d).file_name().unwrap_or_default())) {
                r.errors.push(format!("{d}: {e}"));
            }
        }
        if backup.exists() {
            r.backup = Some(backup.to_string_lossy().into_owned());
        }
        r
    })
    .await
}

/// сессии остаются в общей папке основного аккаунта, у остальных история снова своя — с чистого листа
#[tauri::command]
pub async fn unshare_sessions(dirs: Vec<String>) -> Result<Vec<String>, String> {
    crate::blocking(move || others(dirs).filter_map(|d| unlink_account(Path::new(&d)).err().map(|e| format!("{d}: {e}"))).collect()).await
}

/// для каждой папки: подключена ли она к общим сессиям (основной аккаунт — всегда да)
#[tauri::command]
pub async fn shared_status(dirs: Vec<String>) -> Result<Vec<bool>, String> {
    crate::blocking(move || dirs.iter().map(|d| is_default_dir(d) || is_shared(Path::new(d))).collect()).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merge_keeps_everything() {
        let root = std::env::temp_dir().join(format!("ca-merge-{}", std::process::id()));
        let (src, dst, bak) = (root.join("src"), root.join("dst"), root.join("bak"));
        let w = |p: &Path, s: &str| {
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, s).unwrap();
        };
        w(&src.join("p1").join("a.jsonl"), "only-src");
        w(&src.join("p2").join("same.txt"), "same");
        w(&dst.join("p2").join("same.txt"), "same");
        w(&dst.join("p2").join("conf.jsonl"), "old");
        std::thread::sleep(std::time::Duration::from_millis(20));
        w(&src.join("p2").join("conf.jsonl"), "newer");
        w(&dst.join("p2").join("memory").join("MEMORY.md"), "# Memory\n- [A](a.md)\n- [B](b.md)\n");
        w(&src.join("p2").join("memory").join("MEMORY.md"), "# Memory\n- [A](a.md)\n- [C](c.md)\n");
        merge(&src, &dst, &bak).unwrap();

        // из индексов памяти не пропадает ни один пункт
        let mem = fs::read_to_string(dst.join("p2").join("memory").join("MEMORY.md")).unwrap();
        assert_eq!(mem.lines().filter(|l| l.starts_with("- [")).count(), 3, "{mem}");
        assert!(mem.starts_with("# Memory\n- [A](a.md)\n- [C](c.md)\n"), "{mem}");
        assert_eq!(fs::read_to_string(dst.join("p1").join("a.jsonl")).unwrap(), "only-src");
        assert_eq!(fs::read_to_string(dst.join("p2").join("conf.jsonl")).unwrap(), "newer");
        assert_eq!(fs::read_to_string(bak.join("p2").join("conf.jsonl")).unwrap(), "old");
        assert!(!bak.join("p2").join("same.txt").exists());
        // источник опустел целиком
        assert_eq!(fs::read_dir(&src).unwrap().count(), 0);

        // junction без прав администратора и его распознавание
        let link = root.join("link");
        junction(&link, &dst).unwrap();
        assert!(is_linked(&link, &dst));
        assert!(link.join("p1").join("a.jsonl").exists());
        fs::remove_dir(&link).unwrap();
        assert!(dst.join("p1").join("a.jsonl").exists());
        let _ = fs::remove_dir_all(&root);
    }

    /// весь путь: подключить аккаунт, увидеть общую сессию, писать через ссылку, отключить
    #[test]
    fn link_and_unlink_account() {
        let root = std::env::temp_dir().join(format!("ca-link-{}", std::process::id()));
        let (main, acc, bak) = (root.join("main"), root.join("acc2"), root.join("bak"));
        let w = |p: &Path, s: &str| {
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, s).unwrap();
        };
        w(&main.join("projects").join("P").join("s1.jsonl"), "main-session");
        w(&acc.join("projects").join("P").join("s2.jsonl"), "acc-session");
        w(&acc.join("projects").join("Q").join("memory").join("MEMORY.md"), "acc-memory");
        w(&acc.join(".credentials.json"), "login");
        std::env::set_var("CA_MAIN_DIR", &main);

        link_account(&acc, &bak).unwrap();
        assert!(is_shared(&acc));
        // аккаунт видит и свою, и чужую сессию; свои файлы переехали в общую папку
        assert!(acc.join("projects").join("P").join("s1.jsonl").exists());
        assert_eq!(fs::read_to_string(main.join("projects").join("P").join("s2.jsonl")).unwrap(), "acc-session");
        assert!(main.join("projects").join("Q").join("memory").join("MEMORY.md").exists());
        // логин остался у аккаунта
        assert!(acc.join(".credentials.json").exists() && !main.join(".credentials.json").exists());
        // запись через ссылку попадает в общую папку
        w(&acc.join("projects").join("P").join("s3.jsonl"), "new");
        assert!(main.join("projects").join("P").join("s3.jsonl").exists());
        // повторное подключение ничего не ломает
        link_account(&acc, &bak).unwrap();

        unlink_account(&acc).unwrap();
        assert!(!is_shared(&acc));
        assert!(acc.join("projects").is_dir() && fs::read_dir(acc.join("projects")).unwrap().count() == 0);
        assert!(main.join("projects").join("P").join("s3.jsonl").exists());

        std::env::remove_var("CA_MAIN_DIR");
        let _ = fs::remove_dir_all(&root);
    }
}
