mod config;
mod local;
mod net;
mod system;

use tauri::Manager;

#[tauri::command]
fn load_config() -> config::Config {
    config::load()
}

#[tauri::command]
fn save_config(cfg: config::Config) -> Result<(), String> {
    config::save(&cfg)
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
            default_dir,
            demo_mode,
            local::read_local,
            net::fetch_usage,
            net::check_proxy,
            system::has_claude,
            system::has_wt,
            system::resolve_folder,
            system::launch,
            system::open_path,
            system::open_config,
            system::logout,
            system::sync_settings,
            system::create_account_dir,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
