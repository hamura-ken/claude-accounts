// Обёртки над командами Rust-бэкенда
import { invoke } from '@tauri-apps/api/core'

export interface Account {
  name: string
  dir: string
  color: number
  proxy: string
  fullAccess: boolean
  args: string
}

export interface Config {
  version: number
  accounts: Account[]
  recent: string[]
  refreshSec: number
  terminal: string
  minimizeOnLaunch: boolean
  lang: string
  theme: 'dark' | 'light' | 'system'
}

export interface Limit {
  pct: number
  /** unix ms */
  reset: number | null
}

export interface Usage {
  five: Limit | null
  week: Limit | null
}

export interface LocalInfo {
  loggedIn: boolean
  tokenExpired: boolean
  plan: string | null
  email: string | null
  cache: Usage | null
  cacheAt: number | null
}

export interface ProxyCheck {
  ok: boolean
  kind: string | null
  code: number | null
  err: string | null
  ms: number | null
  ip: string | null
  country: string | null
  city: string | null
}

export const api = {
  loadConfig: () => invoke<Config>('load_config'),
  saveConfig: (cfg: Config) => invoke<void>('save_config', { cfg }),
  defaultDir: () => invoke<string>('default_dir'),
  demoMode: () => invoke<boolean>('demo_mode'),
  readLocal: (dir: string) => invoke<LocalInfo>('read_local', { dir }),
  /** бросает 'token' | 'rate:<секунд из Retry-After>' | 'net' */
  fetchUsage: (dir: string, proxy: string) => invoke<Usage>('fetch_usage', { dir, proxy }),
  checkProxy: (proxy: string) => invoke<ProxyCheck>('check_proxy', { proxy }),
  hasClaude: () => invoke<boolean>('has_claude'),
  hasWt: () => invoke<boolean>('has_wt'),
  resolveFolder: (text: string) => invoke<string | null>('resolve_folder', { text }),
  launch: (acc: Account, folder: string, terminal: string) => invoke<void>('launch', { acc, folder, terminal }),
  openPath: (path: string) => invoke<void>('open_path', { path }),
  openConfig: () => invoke<void>('open_config'),
  logout: (dir: string) => invoke<void>('logout', { dir }),
  syncSettings: (src: string, dsts: string[]) => invoke<void>('sync_settings', { src, dsts }),
  createAccountDir: (mainDir: string, taken: string[]) => invoke<string>('create_account_dir', { mainDir, taken }),
}
