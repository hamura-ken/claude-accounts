// без консольного окна в релизной сборке
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    claude_accounts_lib::run()
}
