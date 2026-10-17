mod config;
mod local;
mod net;
mod shared;
mod system;

use tauri::Manager;

/// Работа с диском — в отдельном потоке. Синхронные команды Tauri выполняются в главном потоке,
/// и медленный диск (сетевая папка, занятый файл) подвешивал бы окно
pub(crate) async fn blocking<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(f).await.map_err(|e| e.to_string())
}

#[tauri::command]
async fn load_config() -> Result<config::Config, String> {
    blocking(config::load).await
}

/// возвращает отметку изменения файла после записи
#[tauri::command]
async fn save_config(cfg: config::Config) -> Result<u64, String> {
    blocking(move || config::save(&cfg)).await?
}

#[tauri::command]
async fn config_stamp() -> Result<u64, String> {
    blocking(config::stamp).await
}

#[tauri::command]
fn default_dir() -> String {
    config::default_dir().to_string_lossy().into_owned()
}

/// режим для скриншотов (CA_DEMO=1): лимиты берутся только из кэша, без запросов в сеть
#[tauri::command]
fn demo_mode() -> bool {
    std::env::var("CA_DEMO").is_ok_and(|v| !v.is_empty())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // второй запуск просто поднимает уже открытое окно
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.unminimize();
                let _ = w.show();
                let _ = w.set_focus();
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            load_config,
            save_config,
            config_stamp,
            default_dir,
            demo_mode,
            local::read_local,
            net::fetch_usage,
            net::check_proxy,
            system::has_claude,
            system::has_wt,
            system::resolve_folder,
            system::paths_exist,
            system::launch,
            system::open_path,
            system::open_config,
            system::logout,
            system::sync_settings,
            system::create_account_dir,
            shared::share_sessions,
            shared::unshare_sessions,
            shared::shared_status,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
