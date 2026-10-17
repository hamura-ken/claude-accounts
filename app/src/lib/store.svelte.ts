// Состояние приложения и все действия: аккаунты, лимиты, запуск, диалоги
import { getCurrentWindow } from '@tauri-apps/api/window'
import { api, type Account, type Config, type Limit, type LocalInfo, type Resume, type Usage } from './api'
import { fmtUntil } from './format'
import { setLangIdx, t } from './i18n.svelte'

export interface AccState {
  acc: Account
  local: LocalInfo | null
  live: Usage | null
  liveAt: number | null
  err: 'token' | 'rate' | 'net' | null
  fetching: boolean
  wasLimited: boolean
  /** после 429 до этого момента (unix ms) в сеть не ходим */
  retryAt: number
  /** сколько 429 подряд — пауза растёт 5 → 10 → 20 → 30 мин */
  rateHits: number
  /** идёт чтение локальных файлов — следующее не запускаем поверх */
  reading: boolean
}

export interface MenuItem {
  icon: any
  text: string
  danger?: boolean
  disabled?: boolean
  action: () => void
}

interface ConfirmReq {
  title: string
  text: string
  ok: string
  danger?: boolean
  info?: boolean
  resolve: (v: boolean) => void
}

export interface AccResult {
  name: string
  color: number
  proxy: string
  fullAccess: boolean
  args: string
}

interface AccDialogReq {
  acc: Account | null
  resolve: (v: AccResult | null) => void
}

export const PALETTE: [string, string][] = [
  ['#F09A76', '#C9553A'], ['#7FA8FF', '#4769D6'], ['#5FD891', '#259A57'], ['#C79BFF', '#8853DB'],
  ['#F7C76A', '#C98B22'], ['#FF8FB8', '#D24A7E'], ['#5ED6D6', '#1F9A9E'], ['#A9B1C2', '#5E6678'],
]

export const app = $state({
  cfg: null as Config | null,
  accs: [] as AccState[],
  folder: '',
  now: Date.now(),
  lastRefresh: 0,
  hasWt: false,
  theme: 'dark' as 'dark' | 'light',
  toast: null as { text: string; kind: 'ok' | 'err'; id: number } | null,
  menu: null as { x: number; y: number; items: (MenuItem | '-')[]; width?: number } | null,
  /** панель истории папок: позиция и ширина под строкой выбора папки */
  recent: null as { x: number; y: number; w: number } | null,
  confirm: null as ConfirmReq | null,
  accDialog: null as AccDialogReq | null,
  settingsOpen: false,
})

const cfg = () => app.cfg!

// ================= сохранение =================
/** отметка файла конфига после нашего последнего чтения или записи — по ней видно правку снаружи */
let cfgStamp = 0
let saveChain: Promise<void> = Promise.resolve()
let saveQueued = false
let saveErrAt = 0

/** записи идут строго по очереди, а несколько вызовов подряд сливаются в одну запись */
export function saveCfg(): Promise<void> {
  if (!app.cfg) return Promise.resolve()
  if (saveQueued) return saveChain
  saveQueued = true
  saveChain = saveChain.then(async () => {
    saveQueued = false
    try {
      cfgStamp = await api.saveConfig($state.snapshot(app.cfg) as Config)
    } catch (e) {
      // одна ошибка на серию, а не тост на каждое сохранение
      if (Date.now() - saveErrAt > 10_000) toast(t('eSave', String(e)), 'err')
      saveErrAt = Date.now()
    }
  })
  return saveChain
}

/** конфиг поправили снаружи (Блокнот через «Файл конфигурации», PowerShell-версия) — перечитываем,
 *  чтобы следующее наше сохранение не затёрло чужие изменения */
let reloading = false
async function reloadIfChanged() {
  if (reloading || saveQueued || app.accDialog || app.confirm || app.settingsOpen || app.recent) return
  reloading = true
  try {
    await saveChain
    const stamp = await api.configStamp()
    if (!stamp || stamp === cfgStamp) return
    const fresh = await api.loadConfig()
    // пока читали, могли начать сохранять своё — тогда перечитаем на следующем круге
    if (saveQueued) return
    cfgStamp = stamp
    app.cfg = fresh
    setLangIdx(fresh.lang)
    document.documentElement.lang = fresh.lang
    applyTheme()
    buildAccs()
    app.accs.forEach(readLocal)
  } catch {
    // файл в этот момент переписывают — попробуем на следующем круге
  } finally {
    reloading = false
  }
}

// ================= лимиты =================
export function effPct(lim: Limit | null | undefined, now = app.now): number {
  if (!lim) return 0
  if (lim.reset && lim.reset < now) return 0
  return lim.pct
}

/** свежие данные: живые, если они новее кэша Claude Code, иначе кэш */
export function effective(st: AccState): { data: Usage; src: 'live' | 'cache'; at: number | null } | null {
  const l = st.local
  if (st.live && (!l?.cacheAt || (st.liveAt ?? 0) >= l.cacheAt)) return { data: st.live, src: 'live', at: st.liveAt }
  if (l?.cache) return { data: l.cache, src: 'cache', at: l.cacheAt }
  return null
}

/** максимальный процент из двух лимитов; null — данных нет или не залогинен */
export function score(st: AccState): number | null {
  if (!st.local?.loggedIn) return null
  const e = effective(st)
  if (!e) return null
  return Math.max(effPct(e.data.five), effPct(e.data.week))
}

export function bestAcc(): AccState | null {
  const cand = app.accs.filter((s) => (score(s) ?? 100) < 100).sort((a, b) => score(a)! - score(b)!)
  return cand[0] ?? null
}

async function readLocal(st: AccState) {
  if (st.reading) return
  st.reading = true
  const prev = st.local
  const wasLogged = prev?.loggedIn
  try {
    const info = await api.readLocal(st.acc.dir)
    // .claude.json мог попасться недописанным, пока Claude Code его сохранял (тогда не прочитался даже email):
    // оставляем прошлые email и кэш, а не мигаем «нет данных». Если email есть, а кэша нет — это правда, не подменяем
    if (info.loggedIn && prev?.loggedIn && !info.email && prev.email) {
      info.email = prev.email
      info.cache ??= prev.cache
      info.cacheAt ??= prev.cacheAt
    }
    st.local = info
  } catch {
    return
  } finally {
    st.reading = false
  }
  if (!st.local.loggedIn) {
    st.live = null
    st.liveAt = null
  } else if (!wasLogged && wasLogged !== undefined) {
    // только что залогинились — сразу тянем лимиты
    fetchUsage(st)
  }
}

let demo = false

/** ручное обновление не чаще раза в минуту на аккаунт */
const MANUAL_GAP = 60_000
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/** самые свежие данные: наш запрос или кэш, который пишет сам Claude Code */
function dataAge(st: AccState) {
  return Date.now() - Math.max(st.liveAt ?? 0, st.local?.cacheAt ?? 0)
}

/** нужен ли запрос: без force — только если данные старше интервала из настроек.
 *  Если Claude Code сам недавно обновил свой кэш, в сеть не идём */
function shouldFetch(st: AccState, force: boolean) {
  if (demo || st.fetching || !st.local?.loggedIn || st.local.tokenExpired || Date.now() < st.retryAt) return false
  return dataAge(st) >= (force ? MANUAL_GAP : cfg().refreshSec * 1000 - 5000)
}

async function fetchUsage(st: AccState, force = false) {
  if (!shouldFetch(st, force)) return
  st.fetching = true
  try {
    st.live = await api.fetchUsage(st.acc.dir, st.acc.proxy)
    st.liveAt = Date.now()
    st.err = null
    st.rateHits = 0
  } catch (e) {
    const s = String(e)
    if (s.startsWith('rate')) {
      // сервер ограничил частоту — ждём, сколько он сказал, или с растущей паузой
      st.rateHits++
      const pause = Math.min(30, 5 * 2 ** (st.rateHits - 1)) * 60000
      st.retryAt = Date.now() + Math.max(Number(s.split(':')[1]) * 1000 || 0, pause)
      st.err = 'rate'
    } else st.err = s === 'token' ? 'token' : 'net'
  } finally {
    st.fetching = false
  }
}

/** force — ручное обновление (кнопка, F5). Аккаунты опрашиваются по очереди, с паузой */
export async function refreshAll(force = false) {
  app.lastRefresh = Date.now()
  await Promise.all(app.accs.map(readLocal))
  let sent = 0
  for (const st of [...app.accs]) {
    if (!shouldFetch(st, force)) continue
    if (sent++) await sleep(1500)
    await fetchUsage(st, force)
  }
}

export async function refreshOne(st: AccState) {
  await readLocal(st)
  await fetchUsage(st, true)
}

// «снова доступен»: аккаунт был в лимите, а теперь нет
function checkBackOnline() {
  for (const st of app.accs) {
    const s = score(st)
    if (s === null) continue
    if (st.wasLimited && s < 100) toast(t('backOnline', st.acc.name))
    st.wasLimited = s >= 100
  }
}

function buildAccs() {
  const old = new Map(app.accs.map((s) => [s.acc.dir.toLowerCase(), s]))
  app.accs = cfg().accounts.map((acc) => {
    const o = old.get(acc.dir.toLowerCase())
    if (o) {
      o.acc = acc
      return o
    }
    return { acc, local: null, live: null, liveAt: null, err: null, fetching: false, wasLimited: false, retryAt: 0, rateHits: 0, reading: false }
  })
}

// ================= тема и язык =================
const media = window.matchMedia('(prefers-color-scheme: dark)')

function effTheme(): 'dark' | 'light' {
  const th = app.cfg?.theme ?? 'system'
  if (th === 'system') return media.matches ? 'dark' : 'light'
  return th
}

/** смена с плавным crossfade всего окна (View Transitions API) */
function withTransition(fn: () => void) {
  const d = document as Document & { startViewTransition?: (cb: () => void) => unknown }
  if (d.startViewTransition && !matchMedia('(prefers-reduced-motion: reduce)').matches) d.startViewTransition(fn)
  else fn()
}

export function applyTheme(animate = true) {
  const th = effTheme()
  const set = () => {
    app.theme = th
    document.documentElement.dataset.theme = th
  }
  if (th === document.documentElement.dataset.theme) return
  if (animate) withTransition(set)
  else set()
  getCurrentWindow().setBackgroundColor(th === 'dark' ? '#101013' : '#F4F3F0').catch(() => {})
}

export function setTheme(th: Config['theme']) {
  if (cfg().theme === th) return
  cfg().theme = th
  saveCfg()
  applyTheme()
}

export function setLang(l: 'ru' | 'en') {
  if (cfg().lang === l) return
  cfg().lang = l
  saveCfg()
  withTransition(() => {
    setLangIdx(l)
    document.documentElement.lang = l
  })
}

// ================= toast / диалоги =================
let toastTimer: number | undefined
export function toast(text: string, kind: 'ok' | 'err' = 'ok') {
  app.toast = { text, kind, id: Date.now() }
  clearTimeout(toastTimer)
  toastTimer = window.setTimeout(() => (app.toast = null), 3500)
}

export function confirmDlg(title: string, text: string, ok: string, opts: { danger?: boolean; info?: boolean } = {}) {
  return new Promise<boolean>((resolve) => {
    app.confirm = { title, text, ok, ...opts, resolve }
  })
}

export function openMenu(anchor: HTMLElement, items: (MenuItem | '-')[], align: 'left' | 'right' = 'right', width = 240) {
  const r = anchor.getBoundingClientRect()
  const x = align === 'right' ? r.right - width : r.left
  app.menu = { x: Math.max(8, x), y: r.bottom + 6, items, width }
}

// ================= действия =================
/** admin — правый клик по «Запустить»: запуск через UAC. resume — продолжить прошлую сессию */
export async function launch(st: AccState, admin = false, resume: Resume = '') {
  if (!(await api.hasClaude())) {
    await confirmDlg(t('noClaude'), t('noClaudeText'), t('gotIt'), { info: true })
    return
  }
  const folder = await api.resolveFolder(app.folder)
  if (!folder) {
    toast(t('noFolder', app.folder), 'err')
    return
  }
  app.folder = folder
  rememberFolder(folder)
  saveCfg()
  try {
    await api.launch($state.snapshot(st.acc) as Account, folder, cfg().terminal, admin, resume)
  } catch (e) {
    // «Нет» в окне UAC — не ошибка
    if (e === 'cancelled') toast(t('tCancelled'))
    else toast(t('error', String(e)), 'err')
    return
  }
  const leaf = folder.split('\\').filter(Boolean).pop() ?? folder
  const msg = !st.local?.loggedIn ? 'tLoginOpen' : resume === 'continue' ? 'tContinued' : resume === 'pick' ? 'tPickSession' : admin ? 'tLaunchedAdmin' : 'tLaunched'
  toast(t(msg, st.acc.name, leaf))
  if (cfg().minimizeOnLaunch) getCurrentWindow().minimize()
}

export async function launchBest() {
  const best = bestAcc()
  if (best) return launch(best)
  const logged = app.accs.filter((s) => s.local?.loggedIn)
  if (!logged.length) return toast(t('noLogged'), 'err')
  // все в лимите — подскажем, кто освободится первым
  let next: number | null = null
  let nextSt: AccState | null = null
  for (const st of logged) {
    const e = effective(st)
    if (!e) continue
    for (const l of [e.data.five, e.data.week]) {
      if (l?.reset && l.pct >= 100 && (next === null || l.reset < next)) {
        next = l.reset
        nextSt = st
      }
    }
  }
  if (nextSt && next) toast(t('allLimited', nextSt.acc.name, fmtUntil(next, app.now)), 'err')
  else launch(logged[0])
}

export function accountDialog(acc: Account | null) {
  return new Promise<AccResult | null>((resolve) => {
    app.accDialog = { acc, resolve }
  })
}

export async function addAccount() {
  const r = await accountDialog(null)
  if (!r) return
  try {
    const dir = await api.createAccountDir(cfg().accounts[0].dir, cfg().accounts.map((a) => a.dir))
    cfg().accounts.push({ ...r, dir })
    // новый аккаунт сразу видит общую историю
    if (cfg().sharedSessions) await linkShared([dir])
  } catch (e) {
    return toast(t('error', String(e)), 'err')
  }
  await saveCfg()
  buildAccs()
  refreshAll()
  toast(t('tAdded', r.name))
}

export async function editAccount(st: AccState) {
  const r = await accountDialog(st.acc)
  if (!r) return
  // правим запись прямо в конфиге — так она точно попадёт в сохранение
  const a = cfg().accounts.find((x) => x.dir === st.acc.dir)
  if (a) Object.assign(a, r)
  await saveCfg()
  refreshOne(st)
  toast(t('tAccSaved'))
}

export function moveAccount(st: AccState, delta: number) {
  const list = cfg().accounts
  const i = list.findIndex((a) => a.dir === st.acc.dir)
  const j = i + delta
  if (i < 0 || j < 0 || j >= list.length) return
  const [a] = list.splice(i, 1)
  list.splice(j, 0, a)
  saveCfg()
  buildAccs()
}

export async function logoutAccount(st: AccState) {
  const def = (await api.defaultDir()).toLowerCase()
  const warn = st.acc.dir.toLowerCase().replace(/\\+$/, '') === def ? t('logoutMain') : ''
  if (!(await confirmDlg(t('logoutTitle', st.acc.name), t('logoutText', warn), t('logoutOk'), { danger: true }))) return
  await api.logout(st.acc.dir)
  st.live = null
  st.liveAt = null
  await refreshOne(st)
  toast(t('tLoggedOut', st.acc.name))
}

export async function removeAccount(st: AccState) {
  if (cfg().accounts.length <= 1) return toast(t('keepOne'), 'err')
  if (!(await confirmDlg(t('removeTitle', st.acc.name), t('removeText', st.acc.dir), t('removeOk'), { danger: true }))) return
  cfg().accounts = cfg().accounts.filter((a) => a.dir !== st.acc.dir)
  await saveCfg()
  buildAccs()
}

export async function syncSettings() {
  const list = cfg().accounts
  if (list.length < 2) return void (await confirmDlg(t('syncTitle'), t('syncNeed2'), t('gotIt'), { info: true }))
  if (!(await confirmDlg(t('syncAsk'), t('syncText', list[0].name), t('syncOk')))) return
  try {
    await api.syncSettings(list[0].dir, list.slice(1).map((a) => a.dir))
  } catch (e) {
    return toast(t('error', String(e)), 'err')
  }
  toast(t('tSynced'))
}

// ================= общие сессии =================
/** подключает папки аккаунтов к общей истории; ошибки — тостом с именами аккаунтов */
async function linkShared(dirs: string[]): Promise<boolean> {
  try {
    const r = await api.shareSessions(dirs)
    if (r.backup) toast(t('tShareBackup', r.backup))
    if (!r.errors.length) return true
    console.error('share_sessions', r.errors)
    const names = cfg().accounts.filter((a) => r.errors.some((e) => e.toLowerCase().startsWith(a.dir.toLowerCase() + ':'))).map((a) => a.name)
    toast(t('eShare', names.join(', ') || r.errors.join('; ')), 'err')
  } catch (e) {
    toast(t('error', String(e)), 'err')
  }
  return false
}

/** включение и выключение применяются сразу, с подтверждением */
export async function setSharedSessions(on: boolean): Promise<void> {
  const dirs = cfg().accounts.map((a) => a.dir)
  if (on) {
    if (!(await confirmDlg(t('shareTitle'), t('shareText'), t('shareOk')))) return
    // флаг ставим даже при частичной неудаче: занятые аккаунты подключатся при следующем запуске приложения
    cfg().sharedSessions = true
    await saveCfg()
    if (await linkShared(dirs)) toast(t('tShared'))
  } else {
    if (!(await confirmDlg(t('unshareTitle'), t('unshareText'), t('unshareOk'), { danger: true }))) return
    cfg().sharedSessions = false
    await saveCfg()
    try {
      const errs = await api.unshareSessions(dirs)
      if (errs.length) toast(t('error', errs.join('; ')), 'err')
      else toast(t('tUnshared'))
    } catch (e) {
      toast(t('error', String(e)), 'err')
    }
  }
}

/** при старте: аккаунты, добавленные мимо приложения или занятые в прошлый раз, подключаем молча */
async function ensureShared() {
  if (!cfg().sharedSessions) return
  const dirs = cfg().accounts.map((a) => a.dir)
  const ok = await api.sharedStatus(dirs).catch(() => dirs.map(() => true))
  const todo = dirs.filter((_, i) => !ok[i])
  if (todo.length) await linkShared(todo)
}

// ================= история папок =================
const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase()

/** папка запуска — в начало истории. История не обрезается */
function rememberFolder(folder: string) {
  const c = cfg()
  c.recent = [folder, ...c.recent.filter((r) => !same(r, folder))]
  for (const k of Object.keys(c.recentAt)) if (same(k, folder)) delete c.recentAt[k]
  c.recentAt[folder] = Date.now()
}

export function removeRecent(paths: string[]) {
  const c = cfg()
  const drop = new Set(paths.map((p) => p.toLowerCase()))
  c.recent = c.recent.filter((r) => !drop.has(r.toLowerCase()))
  for (const k of Object.keys(c.recentAt)) if (drop.has(k.toLowerCase())) delete c.recentAt[k]
  saveCfg()
}

export async function clearRecent() {
  const n = cfg().recent.length
  if (!n) return
  if (!(await confirmDlg(t('rcClearTitle'), t('rcClearText', n), t('rcClearOk'), { danger: true }))) return
  cfg().recent = []
  cfg().recentAt = {}
  saveCfg()
  toast(t('rcCleared'))
}

export function openRecent(anchor: HTMLElement) {
  const r = anchor.getBoundingClientRect()
  app.menu = null
  app.recent = { x: r.left, y: r.bottom + 6, w: r.width }
}

export async function pickFolderFromPath(p: string) {
  const f = await api.resolveFolder(p)
  if (!f) return
  app.folder = f
  toast(t('folderPicked', f.split('\\').filter(Boolean).pop() ?? f))
}

// ================= старт =================
export async function init() {
  demo = await api.demoMode()
  app.cfg = await api.loadConfig()
  cfgStamp = await api.configStamp().catch(() => 0)
  if (!cfg().lang) {
    const sys = navigator.language.slice(0, 2).toLowerCase()
    cfg().lang = ['ru', 'uk', 'be', 'kk'].includes(sys) ? 'ru' : 'en'
    saveCfg()
  }
  setLangIdx(cfg().lang)
  document.documentElement.lang = cfg().lang
  applyTheme(false)
  media.addEventListener('change', () => applyTheme())
  app.folder = cfg().recent[0] ?? ''
  buildAccs()
  api.hasWt().then((v) => (app.hasWt = v))
  await Promise.all(app.accs.map(readLocal))
  refreshAll()
  ensureShared()

  // раз в секунду: тикают таймеры сброса, по расписанию обновляются лимиты
  setInterval(() => {
    app.now = Date.now()
    if (app.now - app.lastRefresh >= cfg().refreshSec * 1000) refreshAll().catch(() => {})
    checkBackOnline()
  }, 1000)
  // логин мог появиться из терминала — локальные файлы читаем чаще, это дёшево и без сети.
  // В сеть ходим только по расписанию: лишние запросы упираются в лимит частоты (429)
  setInterval(() => {
    app.accs.forEach(readLocal)
    reloadIfChanged()
  }, 4000)
  // вернулись в окно — сразу подхватываем правку конфига, не дожидаясь таймера
  window.addEventListener('focus', () => reloadIfChanged())
}
