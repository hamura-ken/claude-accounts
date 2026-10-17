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
  /** вся история папок запуска, свежие первыми */
  recent: string[]
  /** когда из папки запускали в последний раз, unix ms */
  recentAt: Record<string, number>
  refreshSec: number
  terminal: string
  minimizeOnLaunch: boolean
  /** общие сессии: история всех аккаунтов в одной папке */
  sharedSessions: boolean
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

export interface ShareReport {
  /** «папка: причина» для аккаунтов, которые не удалось подключить */
  errors: string[]
  /** куда ушли одноимённые, но разные файлы */
  backup: string | null
}

/** '' — новая сессия, 'continue' — последняя в папке, 'pick' — выбрать из списка */
export type Resume = '' | 'continue' | 'pick'

export const api = {
  loadConfig: () => invoke<Config>('load_config'),
  /** возвращает отметку изменения файла после записи */
  saveConfig: (cfg: Config) => invoke<number>('save_config', { cfg }),
  /** отметка изменения файла конфига, 0 — файла нет */
  configStamp: () => invoke<number>('config_stamp'),
  defaultDir: () => invoke<string>('default_dir'),
  demoMode: () => invoke<boolean>('demo_mode'),
  readLocal: (dir: string) => invoke<LocalInfo>('read_local', { dir }),
  /** бросает 'token' | 'rate:<секунд из Retry-After>' | 'net' */
  fetchUsage: (dir: string, proxy: string) => invoke<Usage>('fetch_usage', { dir, proxy }),
  checkProxy: (proxy: string) => invoke<ProxyCheck>('check_proxy', { proxy }),
  hasClaude: () => invoke<boolean>('has_claude'),
  hasWt: () => invoke<boolean>('has_wt'),
  resolveFolder: (text: string) => invoke<string | null>('resolve_folder', { text }),
  pathsExist: (paths: string[]) => invoke<boolean[]>('paths_exist', { paths }),
  /** admin — через UAC («от имени администратора») */
  launch: (acc: Account, folder: string, terminal: string, admin: boolean, resume: Resume) =>
    invoke<void>('launch', { acc, folder, terminal, admin, resume }),
  openPath: (path: string) => invoke<void>('open_path', { path }),
  openConfig: () => invoke<void>('open_config'),
  logout: (dir: string) => invoke<void>('logout', { dir }),
  syncSettings: (src: string, dsts: string[]) => invoke<void>('sync_settings', { src, dsts }),
  createAccountDir: (mainDir: string, taken: string[]) => invoke<string>('create_account_dir', { mainDir, taken }),
  shareSessions: (dirs: string[]) => invoke<ShareReport>('share_sessions', { dirs }),
  /** возвращает ошибки «папка: причина» */
  unshareSessions: (dirs: string[]) => invoke<string[]>('unshare_sessions', { dirs }),
  sharedStatus: (dirs: string[]) => invoke<boolean[]>('shared_status', { dirs }),
}
