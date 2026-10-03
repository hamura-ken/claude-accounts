# Claude Accounts v4 - менеджер аккаунтов Claude Code с живыми лимитами (WPF)
# Каждый аккаунт = своя папка конфига (CLAUDE_CONFIG_DIR) + свой прокси. Account 1 = стандартная ~/.claude
# Тема (тёмная/светлая/системная) и язык (ru/en) переключаются на лету через DynamicResource

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$UserHome   = $env:USERPROFILE
$DefaultDir = Join-Path $UserHome '.claude'
$CfgPath    = if ($env:CA_CFG) { $env:CA_CFG } else { Join-Path $UserHome '.claude-switcher.json' }
$IconPath   = Join-Path $PSScriptRoot 'claude-accounts.ico'
$FontDir    = Join-Path $PSScriptRoot 'fonts'
$Utf8NoBom  = New-Object Text.UTF8Encoding $false
$IconFont   = 'Segoe Fluent Icons, Segoe MDL2 Assets'
$HasWt      = [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)
$Inv        = [Globalization.CultureInfo]::InvariantCulture

# цвета аккаунтов: [светлый, тёмный]
$Palette = @(
  @('#F09A76', '#C9553A'), @('#7FA8FF', '#4769D6'), @('#5FD891', '#259A57'), @('#C79BFF', '#8853DB'),
  @('#F7C76A', '#C98B22'), @('#FF8FB8', '#D24A7E'), @('#5ED6D6', '#1F9A9E'), @('#A9B1C2', '#5E6678')
)

# ================= strings (ru, en) =================
$S = @{
  # main window
  settings     = 'Настройки', 'Settings'
  minimize     = 'Свернуть', 'Minimize'
  close        = 'Закрыть', 'Close'
  themeTip     = 'Сменить тему', 'Toggle theme'
  langTip      = 'Switch to English', 'Переключить на русский'
  folderPh     = 'Папка проекта — перетащи сюда или нажми «Обзор»', 'Project folder — drop it here or press Browse'
  recent       = 'Недавние папки', 'Recent folders'
  recentEmpty  = 'Пока пусто — папки появятся после запуска', 'Nothing yet — folders appear after a launch'
  browse       = 'Обзор', 'Browse'
  browseTitle  = 'Папка проекта', 'Project folder'
  best         = 'Запустить лучший', 'Launch best'
  bestTip      = 'Запустить аккаунт с самым большим запасом лимитов', 'Launch the account with the most limit left'
  sumOk        = '{0} доступно', '{0} available'
  sumLim       = '{0} в лимите', '{0} limited'
  refreshTip   = 'Обновить лимиты (F5)', 'Refresh limits (F5)'
  refreshing   = 'Обновляю лимиты…', 'Refreshing limits…'
  checkedAt    = 'Проверено {0} · следующее через {1} сек', 'Checked {0} · next in {1}s'
  folderPicked = 'Папка: {0}', 'Folder: {0}'
  # card
  five         = '5 часов', '5 hours'
  week         = 'Неделя', 'Week'
  actions      = 'Действия', 'Actions'
  bestStar     = 'Лучший выбор — больше всего запаса', 'Best pick — the most limit left'
  resetTip     = 'Сброс {0}', 'Resets {0}'
  proxyTip     = 'Через прокси {0}', 'Via proxy {0}'
  noLogin      = 'Вход не выполнен', 'Not signed in'
  noLoginHint  = 'Войди, чтобы видеть лимиты', 'Sign in to see the limits'
  notSignedIn  = 'не авторизован', 'not signed in'
  signedIn     = 'вход выполнен', 'signed in'
  run          = 'Запустить', 'Launch'
  signIn       = 'Войти в аккаунт', 'Sign in'
  addAcc       = 'Добавить аккаунт', 'Add account'
  stOk         = 'Доступен', 'Available'
  stNear       = 'Почти лимит', 'Near the limit'
  stLim        = 'Лимит исчерпан', 'Limit reached'
  stNoLogin    = 'Нет входа', 'Not signed in'
  stNoData     = 'Вход выполнен · нет данных', 'Signed in · no data'
  direct       = 'напрямую', 'direct'
  liveUpd      = 'Live · обновлено {0}', 'Live · updated {0}'
  liveAgo      = 'Live · {0}', 'Live · {0}'
  fromCache    = 'Из кэша · {0}', 'Cached · {0}'
  loading      = 'Загружаю лимиты…', 'Loading limits…'
  noData       = 'Нет данных', 'No data'
  whyToken     = 'Токен истёк — запусти аккаунт', 'Token expired — launch the account'
  whyRate      = 'Anthropic ограничил частоту запросов', 'Anthropic rate-limited the requests'
  whyNet       = 'Нет связи', 'No connection'
  whyNetPx     = 'Нет связи — проверь прокси', 'No connection — check the proxy'
  backOnline   = '«{0}» снова доступен — лимит сбросился', '“{0}” is available again — the limit has reset'
  # time
  justNow      = 'только что', 'just now'
  secAgo       = '{0} сек назад', '{0}s ago'
  minAgo       = '{0} мин назад', '{0} min ago'
  atTime       = 'в {0}', 'at {0}'
  lessMin      = 'меньше минуты', 'under a minute'
  fmtD         = '{0} д {1} ч', '{0}d {1}h'
  fmtH         = '{0} ч {1} мин', '{0}h {1}m'
  fmtM         = '{0} мин', '{0} min'
  today        = 'сегодня в {0}', 'today at {0}'
  tomorrow     = 'завтра в {0}', 'tomorrow at {0}'
  onDate       = '{0} в {1}', '{0} at {1}'
  # card menu
  mSettings    = 'Настройки аккаунта…', 'Account settings…'
  mRefresh     = 'Обновить лимиты', 'Refresh limits'
  mDir         = 'Открыть папку с логином', 'Open login folder'
  mUp          = 'Переместить выше', 'Move up'
  mDown        = 'Переместить ниже', 'Move down'
  mLogout      = 'Выйти из аккаунта', 'Sign out'
  mRemove      = 'Убрать из списка', 'Remove from list'
  # account dialog
  aName        = 'НАЗВАНИЕ', 'NAME'
  aNamePh      = 'Например: Основной, Рабочий, Max #2', 'e.g. Main, Work, Max #2'
  aColor       = 'ЦВЕТ', 'COLOR'
  aProxy       = 'ПРОКСИ', 'PROXY'
  aPxNone      = 'Без прокси', 'No proxy'
  aPxOn        = 'Через прокси', 'Via proxy'
  aPxPh        = 'host:port:логин:пароль  или  http://логин:пароль@host:port', 'host:port:user:pass  or  http://user:pass@host:port'
  aCheck       = 'Проверить', 'Check'
  aPxNoneHint  = 'Claude будет подключаться напрямую, без прокси.', 'Claude will connect directly, without a proxy.'
  aLaunch      = 'ЗАПУСК', 'LAUNCH'
  aFull        = 'Полный доступ — Claude не спрашивает подтверждений', 'Full access — Claude does not ask for confirmations'
  aArgs        = 'Дополнительные аргументы claude', 'Extra claude arguments'
  aArgsPh      = 'необязательно, например: --model opus', 'optional, e.g. --model opus'
  aDir         = 'Папка с логином', 'Login folder'
  aOpenDir     = 'Открыть папку', 'Open folder'
  aNewTitle    = 'Новый аккаунт', 'New account'
  aNewSub      = 'Логин аккаунта хранится в отдельной папке. Если указан прокси — он проверяется до добавления, через него же идут Claude и запрос лимитов.', 'The login is kept in its own folder. A proxy, if set, is checked before adding — Claude and the limits request both go through it.'
  aNewOk       = 'Добавить аккаунт', 'Add account'
  aEditTitle   = 'Настройки аккаунта', 'Account settings'
  aEditSub     = 'Изменения применятся при следующем запуске Claude на этом аккаунте.', 'Changes apply the next time Claude launches on this account.'
  vName        = 'Укажи название аккаунта', 'Enter an account name'
  vBusy        = 'Идёт проверка прокси…', 'Checking the proxy…'
  vFailed      = 'Прокси не работает — исправь данные или выбери «Без прокси»', 'The proxy does not work — fix it or choose No proxy'
  vCheck       = 'Нажми «Проверить» — без рабочего прокси аккаунт не сохранить', 'Press Check — the account cannot be saved without a working proxy'
  pxEmpty      = 'Введи адрес прокси', 'Enter a proxy address'
  pxSocks      = 'SOCKS не поддерживается Claude Code — нужен HTTP-прокси', 'Claude Code does not support SOCKS — use an HTTP proxy'
  pxFormat     = 'Не понял формат. Пример: 1.2.3.4:8080:логин:пароль', 'Unknown format. Example: 1.2.3.4:8080:user:pass'
  pxChecking   = 'Проверяю соединение через {0}…', 'Checking the connection via {0}…'
  pxOk         = 'Прокси работает · {0} мс{1}', 'Proxy works · {0} ms{1}'
  e407         = 'Прокси отклонил логин/пароль (407)', 'The proxy rejected the username/password (407)'
  eCode        = 'Прокси не смог достучаться до Anthropic (код {0})', 'The proxy could not reach Anthropic (code {0})'
  eTimeout     = 'Прокси не отвечает (таймаут 12 сек)', 'The proxy is not responding (12 s timeout)'
  eConnect     = 'Не удалось подключиться к прокси — проверь host и порт', 'Could not connect to the proxy — check host and port'
  ePName       = 'Хост прокси не найден', 'Proxy host not found'
  eDns         = 'Не удалось найти api.anthropic.com через прокси', 'Could not resolve api.anthropic.com through the proxy'
  eRecv        = 'Прокси оборвал соединение', 'The proxy dropped the connection'
  eTls         = 'Ошибка TLS через прокси', 'TLS error through the proxy'
  # settings dialog
  setTitle     = 'Настройки', 'Settings'
  setSub       = 'Общие параметры приложения. Прокси, цвет и запуск задаются у каждого аккаунта через «⋯ → Настройки аккаунта».', 'App-wide options. Proxy, color and launch options are set per account via “⋯ → Account settings”.'
  sAppearance  = 'ОФОРМЛЕНИЕ', 'APPEARANCE'
  sTheme       = 'Тема', 'Theme'
  sLang        = 'Язык', 'Language'
  thDark       = 'Тёмная', 'Dark'
  thLight      = 'Светлая', 'Light'
  thSys        = 'Как в системе', 'System'
  sRefresh     = 'ОБНОВЛЕНИЕ ЛИМИТОВ', 'LIMITS REFRESH'
  sTerminal    = 'ТЕРМИНАЛ', 'TERMINAL'
  sCmd         = 'Командная строка', 'Command Prompt'
  sBehavior    = 'ПОВЕДЕНИЕ', 'BEHAVIOR'
  sMinLaunch   = 'Сворачивать окно после запуска Claude', 'Minimize the window after launching Claude'
  sTools       = 'ИНСТРУМЕНТЫ', 'TOOLS'
  sSync        = 'Синхронизировать настройки Claude', 'Sync Claude settings'
  sCfg         = 'Файл конфигурации', 'Config file'
  sSyncHint    = 'Синхронизация копирует settings.json, skills и плагины из первого аккаунта во все остальные. Логины не затрагиваются.', 'Sync copies settings.json, skills and plugins from the first account to all others. Logins are not touched.'
  iv300        = '5 мин', '5 min'
  iv600        = '10 мин', '10 min'
  iv900        = '15 мин', '15 min'
  iv1800       = '30 мин', '30 min'
  noWt         = 'Windows Terminal не установлен', 'Windows Terminal is not installed'
  tSaved       = 'Настройки сохранены', 'Settings saved'
  # common / actions
  cancel       = 'Отмена', 'Cancel'
  save         = 'Сохранить', 'Save'
  gotIt        = 'Понятно', 'Got it'
  tAdded       = 'Аккаунт «{0}» добавлен — нажми «Войти» на его карточке', 'Account “{0}” added — press Sign in on its card'
  tAccSaved    = 'Настройки аккаунта сохранены', 'Account settings saved'
  syncTitle    = 'Синхронизация', 'Sync'
  syncNeed2    = 'Нужно хотя бы два аккаунта.', 'You need at least two accounts.'
  syncAsk      = 'Синхронизировать настройки?', 'Sync settings?'
  syncText     = 'settings.json, skills и плагины из «{0}» будут скопированы во все остальные аккаунты. Логины не затрагиваются.', 'settings.json, skills and plugins from “{0}” will be copied to every other account. Logins are not touched.'
  syncOk       = 'Синхронизировать', 'Sync'
  tSynced      = 'Настройки синхронизированы', 'Settings synced'
  noClaude     = 'Claude не найден', 'Claude not found'
  noClaudeText = 'Команда claude не найдена в PATH. Установи Claude Code CLI.', 'The claude command is not in PATH. Install the Claude Code CLI.'
  noFolder     = 'Папка не найдена: {0}', 'Folder not found: {0}'
  tLaunched    = 'Запущен «{0}» · {1}', 'Launched “{0}” · {1}'
  tLoginOpen   = 'Открыт вход в «{0}» · {1}', 'Sign-in opened for “{0}” · {1}'
  noLogged     = 'Нет залогиненных аккаунтов — нажми «Войти» на карточке', 'No signed-in accounts — press Sign in on a card'
  allLimited   = 'Все аккаунты в лимите. Ближе всего «{0}» — через {1}', 'All accounts are limited. “{0}” frees up first — in {1}'
  logoutTitle  = 'Выйти из «{0}»?', 'Sign out of “{0}”?'
  logoutText   = 'Логин будет удалён из этой папки, настройки останутся. Потом можно нажать «Войти» и залогиниться в другой аккаунт.{0}', 'The login is deleted from this folder, settings stay. Later you can press Sign in and log in to another account.{0}'
  logoutMain   = ' Это основной логин Claude Code на компьютере.', ' This is the main Claude Code login on this computer.'
  logoutOk     = 'Выйти', 'Sign out'
  tLoggedOut   = 'Вы вышли из «{0}»', 'Signed out of “{0}”'
  keepOne      = 'Должен остаться хотя бы один аккаунт', 'At least one account must remain'
  removeTitle  = 'Убрать «{0}»?', 'Remove “{0}”?'
  removeText   = 'Аккаунт исчезнет из списка. Папка {0} с логином останется на диске — её можно удалить вручную.', 'The account disappears from the list. Its login folder {0} stays on disk — delete it manually if needed.'
  removeOk     = 'Убрать', 'Remove'
}

# ================= themes =================
# строки = цвета (кисти B.*), числа = N.*
$Themes = @{
  dark = @{
    bg0 = '#101013'; glowStart = '#2B1C17'; line = '#25252C'; panel = '#16161A'; panelLine = '#24242B'
    card = '#17171B'; cardLine = '#25252C'; text = '#F4F4F5'; text2 = '#E6E6E9'; muted = '#8E8E96'; faint = '#64646C'; caption = '#6A6A73'
    input = '#141418'; inputLine = '#2C2C34'; inputHover = '#3C3C46'; ph = '#55555E'
    ghost = '#1D1D22'; ghostLine = '#2E2E36'; btnFg = '#ECECEE'; icon = '#8E8E96'; iconHover = '#F4F4F5'; hover = '#FFFFFF'
    track = '#30303A'; seg = '#111114'; segLine = '#24242B'; segFg = '#9A9AA3'; segHover = '#202027'; segOn = '#30303A'; segOnFg = '#FFFFFF'
    menu = '#1F1F25'; menuLine = '#34343D'; menuHover = '#2D2D35'; thumb = '#34343D'; gaugeTrack = '#22222A'
    pill = '#1A1A1F'; pillLine = '#26262D'; toast = '#25252C'; toastLine = '#3A3A44'
    dialog = '#17171B'; dialogLine = '#30303A'; dlgGlow = '#231A17'; swatchRing = '#F4F4F5'; dash = '#33333C'; addBg = '#221D1E'
    noLogin = '#121216'; noLoginIcon = '#1E1E24'; inset = '#121216'; insetLine = '#222229'; tint = '#07FFFFFF'
    green = '#4CD97B'; orange = '#F0B44C'; red = '#FF6B6F'; gray = '#8E8E96'
    greenBg = '#1C4CD97B'; orangeBg = '#1EF0B44C'; redBg = '#22FF6B6F'; grayBg = '#22262630'
    greenText = '#7BE8A0'; redText = '#FF9A9D'; accentText = '#F6B096'; bestBg = '#2AD97757'; planBg = '#33D97757'; planText = '#F3B79E'
    shadow = 0.6; cardShadow = 0.0; glow = 0.55
  }
  light = @{
    bg0 = '#F4F3F0'; glowStart = '#FBE3D6'; line = '#E2E0DB'; panel = '#FFFFFF'; panelLine = '#E7E5E0'
    card = '#FFFFFF'; cardLine = '#E7E5E0'; text = '#18181B'; text2 = '#2A2A30'; muted = '#6C6C75'; faint = '#9A9AA2'; caption = '#8A8A92'
    input = '#F6F5F2'; inputLine = '#DDDBD6'; inputHover = '#C9C6C0'; ph = '#A3A3AA'
    ghost = '#FFFFFF'; ghostLine = '#DDDBD6'; btnFg = '#26262B'; icon = '#75757E'; iconHover = '#18181B'; hover = '#000000'
    track = '#D6D4CF'; seg = '#F0EFEB'; segLine = '#E3E1DC'; segFg = '#6C6C75'; segHover = '#E7E5E0'; segOn = '#FFFFFF'; segOnFg = '#18181B'
    menu = '#FFFFFF'; menuLine = '#E2E0DB'; menuHover = '#F2F0EC'; thumb = '#CCC9C3'; gaugeTrack = '#EEECE8'
    pill = '#FFFFFF'; pillLine = '#E2E0DB'; toast = '#FFFFFF'; toastLine = '#E0DED9'
    dialog = '#FFFFFF'; dialogLine = '#E2E0DB'; dlgGlow = '#FDEDE5'; swatchRing = '#18181B'; dash = '#CFCCC6'; addBg = '#FBEDE6'
    noLogin = '#F8F7F4'; noLoginIcon = '#EEECE8'; inset = '#F8F7F4'; insetLine = '#ECEAE5'; tint = '#05000000'
    green = '#1E9E57'; orange = '#C67A0C'; red = '#D9383E'; gray = '#8C8C94'
    greenBg = '#1A1E9E57'; orangeBg = '#1CC67A0C'; redBg = '#1AD9383E'; grayBg = '#10000000'
    greenText = '#1B8A4C'; redText = '#C8323A'; accentText = '#C2512D'; bestBg = '#1FD97757'; planBg = '#22D97757'; planText = '#B9502E'
    shadow = 0.16; cardShadow = 0.07; glow = 0.3
  }
}

# ================= config =================
function Load-Cfg {
  $sysLang = if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -in 'ru', 'uk', 'be', 'kk') { 'ru' } else { 'en' }
  $c = @{ version = 3; accounts = @(); recent = @(); refreshSec = 300; terminal = 'cmd'; minimizeOnLaunch = $false; lang = $sysLang; theme = 'system' }
  if (Test-Path -LiteralPath $CfgPath) {
    try {
      $j = [IO.File]::ReadAllText($CfgPath) | ConvertFrom-Json
      # миграция с v2: общий прокси/полный доступ -> в каждый аккаунт
      $gProxy = if ($j.proxy -and $j.useProxy -ne $false) { [string]$j.proxy } else { '' }
      $gFull  = if ($null -ne $j.fullAccess) { [bool]$j.fullAccess } else { $true }
      $i = 0
      $c.accounts = @(foreach ($a in @($j.accounts)) {
        if (-not $a) { continue }
        $has = @($a.PSObject.Properties.Name)
        @{
          name       = [string]$a.name
          dir        = [string]$a.dir
          color      = if ($has -contains 'color') { [int]$a.color } else { $i % $Palette.Count }
          proxy      = if ($has -contains 'proxy') { [string]$a.proxy } else { $gProxy }
          fullAccess = if ($has -contains 'fullAccess') { [bool]$a.fullAccess } else { $gFull }
          args       = if ($has -contains 'args') { [string]$a.args } else { '' }
        }
        $i++
      })
      $c.recent = @($j.recent | Where-Object { $_ } | ForEach-Object { [string]$_ })
      if ($j.refreshSec) { $c.refreshSec = [math]::Max(300, [int]$j.refreshSec) }  # не чаще раза в 5 минут — иначе Anthropic отвечает 429
      if ($j.terminal) { $c.terminal = [string]$j.terminal }
      if ($null -ne $j.minimizeOnLaunch) { $c.minimizeOnLaunch = [bool]$j.minimizeOnLaunch }
      if ($j.lang -in 'ru', 'en') { $c.lang = [string]$j.lang }
      if ($j.theme -in 'dark', 'light', 'system') { $c.theme = [string]$j.theme }
    } catch {}
  }
  if ($c.accounts.Count -eq 0) {
    $c.accounts = @(@{ name = 'Account 1'; dir = $DefaultDir; color = 0; proxy = ''; fullAccess = $true; args = '' })
  }
  $c
}
function Save-Cfg { [IO.File]::WriteAllText($CfgPath, (ConvertTo-Json -InputObject $script:cfg -Depth 6), $Utf8NoBom) }
$script:cfg = Load-Cfg

# ================= i18n =================
function Get-Lang { if ($env:CA_LANG -in 'ru', 'en') { $env:CA_LANG } else { $script:cfg.lang } }
$script:LangIdx = if ((Get-Lang) -eq 'en') { 1 } else { 0 }
# $script:S явно: иначе $s из вызывающей функции или обработчика (param($s, $e)) перекрывает таблицу строк
function T($k) { $v = $script:S[$k]; if (-not $v) { return $k }; $v[$script:LangIdx] }
function TF($k) { (T $k) -f $args }

# ================= proxy helpers =================
# принимает host:port, host:port:user:pass, user:pass@host:port, http://user:pass@host:port
function Normalize-Proxy([string]$s) {
  $s = ([string]$s).Trim()
  if (-not $s) { return @{ Ok = $false; Err = (T 'pxEmpty') } }
  if ($s -match '^socks') { return @{ Ok = $false; Err = (T 'pxSocks') } }
  $s = $s -replace '^https?://', ''
  if ($s -match '^(?<cred>[^@]+)@(?<host>[^:@/]+):(?<port>\d{1,5})/?$') {
    return @{ Ok = $true; Url = "http://$($matches.cred)@$($matches.host):$($matches.port)" }
  }
  $p = $s.Split(':')
  if ($p.Count -eq 2 -and $p[1] -match '^\d{1,5}$') { return @{ Ok = $true; Url = "http://$($p[0]):$($p[1])" } }
  if ($p.Count -ge 4 -and $p[1] -match '^\d{1,5}$') {
    $user = [Uri]::EscapeDataString($p[2]); $pass = [Uri]::EscapeDataString(($p[3..($p.Count - 1)] -join ':'))
    return @{ Ok = $true; Url = "http://${user}:${pass}@$($p[0]):$($p[1])" }
  }
  @{ Ok = $false; Err = (T 'pxFormat') }
}
function Proxy-Display($url) {
  if (-not $url) { return (T 'direct') }
  try { $u = [Uri]$url; "$($u.Host):$($u.Port)" } catch { $url }
}

# ================= local data =================
function Is-DefaultDir($d) { ([IO.Path]::GetFullPath($d)).TrimEnd('\') -ieq $DefaultDir }
function Get-GlobalJson($d) { if (Is-DefaultDir $d) { Join-Path $UserHome '.claude.json' } else { Join-Path $d '.claude.json' } }
function Read-Shared($path) {
  $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')
  try { (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $fs.Dispose() }
}
function To-Local($v) {
  if ($v -is [datetime]) { return $v.ToLocalTime() }
  [DateTimeOffset]::Parse([string]$v, $Inv).LocalDateTime
}
function From-Ms($ms) { [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms).LocalDateTime }
function Get-Limit($l) {
  if (-not $l) { return $null }
  $reset = $null
  if ($l.resets_at) { try { $reset = To-Local $l.resets_at } catch {} }
  @{ Pct = [double]$l.utilization; Reset = $reset }
}
function Read-Local($st) {
  $d = $st.Acc.dir
  $st.LoggedIn = $false; $st.Token = $null; $st.TokenExpired = $false; $st.Plan = $null
  $cred = Join-Path $d '.credentials.json'
  if (Test-Path -LiteralPath $cred) {
    try {
      $c = (Read-Shared $cred | ConvertFrom-Json).claudeAiOauth
      if ($c -and $c.accessToken) {
        $st.LoggedIn = $true; $st.Token = $c.accessToken; $st.Plan = $c.subscriptionType
        if ($c.expiresAt) { $st.TokenExpired = (From-Ms $c.expiresAt) -lt (Get-Date).AddSeconds(30) }
      }
    } catch {}
  }
  if (-not $st.LoggedIn) { $st.Live = $null; $st.LiveAt = $null; $st.Cache = $null; $st.CacheAt = $null }
  $gp = Get-GlobalJson $d
  if (Test-Path -LiteralPath $gp) {
    try {
      $j = Read-Shared $gp | ConvertFrom-Json
      $st.Email = if ($j.oauthAccount) { $j.oauthAccount.emailAddress } else { $null }
      $u = $j.cachedUsageUtilization
      if ($u -and $u.utilization -and (-not $j.oauthAccount -or $u.accountUuid -eq $j.oauthAccount.accountUuid)) {
        $st.Cache   = @{ Five = Get-Limit $u.utilization.five_hour; Week = Get-Limit $u.utilization.seven_day }
        $st.CacheAt = if ($u.fetchedAtMs) { From-Ms $u.fetchedAtMs } else { $null }
      }
    } catch {}
  }
}
function Get-Effective($st) {
  if ($st.Live -and (-not $st.CacheAt -or $st.LiveAt -ge $st.CacheAt)) { return @{ Data = $st.Live; Src = 'live'; At = $st.LiveAt } }
  if ($st.Cache) { return @{ Data = $st.Cache; Src = 'cache'; At = $st.CacheAt } }
  $null
}
function Eff-Pct($lim) {
  if (-not $lim) { return 0 }
  if ($lim.Reset -and $lim.Reset -lt (Get-Date)) { return 0 }
  $lim.Pct
}

# ================= network (в фоне) =================
$script:Pool = [runspacefactory]::CreateRunspacePool(1, 6); $script:Pool.Open()
$script:Jobs = New-Object Collections.ArrayList
$NetScript = {
  param($mode, $token, $proxy)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  function New-Req($url, $proxy, $timeout, [switch]$Fresh) {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.Timeout = $timeout; $req.ReadWriteTimeout = $timeout; $req.UserAgent = 'claude-accounts/4.0'
    # .NET переиспользует туннели к прокси без учёта логина — разводим соединения по группам
    if ($Fresh) { $req.ConnectionGroupName = [guid]::NewGuid().ToString(); $req.KeepAlive = $false }
    else { $req.ConnectionGroupName = 'p:' + [string]$proxy }
    if ($proxy) {
      $u = [Uri]$proxy
      $wp = New-Object Net.WebProxy("http://$($u.Host):$($u.Port)")
      if ($u.UserInfo) {
        $p = $u.UserInfo.Split(':', 2)
        $wp.Credentials = New-Object Net.NetworkCredential([Uri]::UnescapeDataString($p[0]), [Uri]::UnescapeDataString($p[1]))
      }
      $req.Proxy = $wp
    } else { $req.Proxy = $null }
    $req
  }
  function Read-Body($resp) { $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $b = $sr.ReadToEnd(); $resp.Close(); $b }
  function Get-WebEx($e) { $x = $e; while ($x -and -not ($x -is [Net.WebException])) { $x = $x.InnerException }; $x }

  if ($mode -eq 'usage') {
    try {
      $req = New-Req 'https://api.anthropic.com/api/oauth/usage' $proxy 20000
      $req.Headers.Add('Authorization', "Bearer $token"); $req.Headers.Add('anthropic-beta', 'oauth-2025-04-20')
      return @{ Ok = $true; Body = (Read-Body $req.GetResponse()) }
    } catch {
      $w = Get-WebEx $_.Exception; $code = 0
      if ($w -and $w.Response) { $code = [int]$w.Response.StatusCode }
      return @{ Ok = $false; Code = $code; Err = $_.Exception.Message }
    }
  }

  # mode = check: проверка прокси. Текст ошибки собирается в UI-потоке по Kind (там известен язык)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try { $r = (New-Req 'https://api.anthropic.com/v1/models' $proxy 12000 -Fresh).GetResponse(); $r.Close() }
  catch {
    $em = $_.Exception.Message
    $w = Get-WebEx $_.Exception
    if ($w -and $w.Response) {
      $code = [int]$w.Response.StatusCode
      if ($code -eq 407) { return @{ Ok = $false; Kind = 'p407' } }
      if ($code -ne 401 -and $code -ne 403 -and $code -ne 404) { return @{ Ok = $false; Kind = 'code'; Code = $code } }
    } else {
      $status = if ($w) { [string]$w.Status } else { '' }
      $kind = switch ($status) {
        'Timeout'                    { 'timeout' }
        'ConnectFailure'             { 'connect' }
        'ProxyNameResolutionFailure' { 'pname' }
        'NameResolutionFailure'      { 'dns' }
        'ReceiveFailure'             { 'recv' }
        'SecureChannelFailure'       { 'tls' }
        default                      { 'raw' }
      }
      if ($em -match '407') { $kind = 'p407' }
      return @{ Ok = $false; Kind = $kind; Err = $em }
    }
  }
  $ms = $sw.ElapsedMilliseconds
  $ip = $null; $country = $null; $city = $null
  try { $j = (Read-Body ((New-Req 'https://ipinfo.io/json' $proxy 8000 -Fresh).GetResponse())) | ConvertFrom-Json; $ip = $j.ip; $country = $j.country; $city = $j.city } catch {}
  @{ Ok = $true; Ms = $ms; Ip = $ip; Country = $country; City = $city }
}
function Net-ErrText($r) {
  switch ($r.Kind) {
    'p407'    { T 'e407' }
    'code'    { TF 'eCode' $r.Code }
    'timeout' { T 'eTimeout' }
    'connect' { T 'eConnect' }
    'pname'   { T 'ePName' }
    'dns'     { T 'eDns' }
    'recv'    { T 'eRecv' }
    'tls'     { T 'eTls' }
    default   { $r.Err }
  }
}
function Start-Net($mode, $token, $proxy, $ctx, [scriptblock]$onDone) {
  $ps = [powershell]::Create(); $ps.RunspacePool = $script:Pool
  [void]$ps.AddScript($NetScript).AddArgument($mode).AddArgument($token).AddArgument($proxy)
  [void]$script:Jobs.Add(@{ Ps = $ps; H = $ps.BeginInvoke(); Ctx = $ctx; Done = $onDone })
}
function Collect-Jobs {
  foreach ($j in @($script:Jobs)) {
    if (-not $j.H.IsCompleted) { continue }
    $script:Jobs.Remove($j)
    try { $r = @($j.Ps.EndInvoke($j.H))[0] } catch { $r = @{ Ok = $false; Code = 0; Err = $_.Exception.Message } }
    $j.Ps.Dispose()
    try { & $j.Done $r $j.Ctx } catch {}
  }
  Update-Spinner
}
function Start-Fetch($st) {
  if ($st.Fetching -or -not $st.LoggedIn -or $st.TokenExpired -or -not $st.Token) { return }
  $st.Fetching = $true
  Start-Net 'usage' $st.Token $st.Acc.proxy $st {
    param($r, $st)
    $st.Fetching = $false
    if ($r.Ok) {
      try {
        $u = $r.Body | ConvertFrom-Json
        $st.Live = @{ Five = Get-Limit $u.five_hour; Week = Get-Limit $u.seven_day }
        $st.LiveAt = Get-Date; $st.Err = $null
      } catch { $st.Err = 'net' }
    } elseif ($r.Code -eq 401 -or $r.Code -eq 403) { $st.Err = 'token' }
    elseif ($r.Code -eq 429) { $st.Err = 'rate' }
    else { $st.Err = 'net' }
    Update-All
  }
}
function Refresh-All {
  foreach ($st in $script:States) { Read-Local $st; Start-Fetch $st }
  $script:LastRefresh = Get-Date
  Update-All; Update-Spinner
}

# ================= formatting =================
function Fmt-Time($dt) {
  if (-not $dt) { return '?' }
  if ($dt.Date -eq (Get-Date).Date) { return $dt.ToString('HH:mm') }
  if ($script:LangIdx) { $dt.ToString('MMM d, HH:mm', $Inv) } else { $dt.ToString('dd.MM HH:mm') }
}
function Fmt-At($dt) {
  $today = (Get-Date).Date; $hm = $dt.ToString('HH:mm')
  if ($dt.Date -eq $today) { return (TF 'today' $hm) }
  if ($dt.Date -eq $today.AddDays(1)) { return (TF 'tomorrow' $hm) }
  $day = if ($script:LangIdx) { $dt.ToString('MMM d', $Inv) } else { $dt.ToString('dd.MM') }
  TF 'onDate' $day $hm
}
function Fmt-Until($dt) {
  $d = $dt - (Get-Date)
  if ($d.TotalMinutes -lt 1) { return (T 'lessMin') }
  if ($d.TotalDays -ge 1) { return (TF 'fmtD' ([int][math]::Floor($d.TotalDays)) $d.Hours) }
  if ($d.TotalHours -ge 1) { return (TF 'fmtH' ([int][math]::Floor($d.TotalHours)) $d.Minutes) }
  TF 'fmtM' $d.Minutes
}
function Fmt-Ago($dt) {
  $s = ((Get-Date) - $dt).TotalSeconds
  if ($s -lt 10) { return (T 'justNow') }
  if ($s -lt 60) { return (TF 'secAgo' ([int]$s)) }
  if ($s -lt 3600) { return (TF 'minAgo' ([int]($s / 60))) }
  TF 'atTime' (Fmt-Time $dt)
}

# ================= brushes / theme / animation =================
function Col($hex) { [Windows.Media.ColorConverter]::ConvertFromString($hex) }
function Br($hex) { $b = New-Object Windows.Media.SolidColorBrush (Col $hex); $b.Freeze(); $b }
function Grad($a, $b, $angle = 0) { $g = New-Object Windows.Media.LinearGradientBrush (Col $a), (Col $b), $angle; $g.Freeze(); $g }
function Radial($a, $b, $cx, $rx, $ry) {
  $g = New-Object Windows.Media.RadialGradientBrush
  $g.Center = New-Object Windows.Point($cx, 0); $g.GradientOrigin = $g.Center; $g.RadiusX = $rx; $g.RadiusY = $ry
  $g.GradientStops.Add((New-Object Windows.Media.GradientStop((Col $a), 0)))
  $g.GradientStops.Add((New-Object Windows.Media.GradientStop((Col $b), 1)))
  $g.Freeze(); $g
}

# Application нужен, чтобы ресурсы темы/языка были общими для окна, диалогов, меню и подсказок
$app = [Windows.Application]::Current
if (-not $app) { $app = New-Object Windows.Application; $app.ShutdownMode = 'OnExplicitShutdown' }

# шрифт Inter лежит рядом со скриптом; если его нет — Segoe UI
$UiFont = if (Test-Path -LiteralPath (Join-Path $FontDir 'Inter-Regular.ttf')) {
  New-Object Windows.Media.FontFamily((New-Object Uri ($FontDir.TrimEnd('\') + '\')), './#Inter, Segoe UI')
} else { New-Object Windows.Media.FontFamily 'Segoe UI' }

function Sys-Light {
  try { [int](Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme') -eq 1 } catch { $false }
}
function Get-EffTheme {
  if ($env:CA_THEME -in 'dark', 'light') { return $env:CA_THEME }
  if ($script:cfg.theme -eq 'system') { if (Sys-Light) { 'light' } else { 'dark' } } else { $script:cfg.theme }
}

function Set-ThemeResources($name) {
  $t = $Themes[$name]
  foreach ($k in $t.Keys) {
    $v = $t[$k]
    # приведение типа снимает PSObject-обёртку — иначе WPF не принимает кисть из ресурсов
    if ($v -is [string]) { $app.Resources["B.$k"] = [Windows.Media.Brush](Br $v) } else { $app.Resources["N.$k"] = [double]$v }
  }
  $app.Resources['B.shellBg']  = [Windows.Media.Brush](Radial $t.glowStart $t.bg0 0.08 0.75 0.65)
  $app.Resources['B.dialogBg'] = [Windows.Media.Brush](Radial $t.dlgGlow $t.dialog 0 0.9 0.6)
  $script:CurTheme = $name; $script:Th = $t
  $script:BR = @{
    Text = Br $t.text; Muted = Br $t.muted; Faint = Br $t.faint
    Green = Br $t.green; Orange = Br $t.orange; Red = Br $t.red; Gray = Br $t.gray
    GreenBg = Br $t.greenBg; OrangeBg = Br $t.orangeBg; RedBg = Br $t.redBg; GrayBg = Br $t.grayBg
    RingGreen = Grad '#2FBF62' '#7BF0A2' 0; RingOrange = Grad '#E08E1E' '#FFCB6B' 0; RingRed = Grad '#E3393F' '#FF8A8D' 0; RingGray = Br $t.gaugeTrack
    NumGreen = Br $t.text; NumOrange = Br $t.orange; NumRed = Br $t.red; NumGray = Br $t.faint
  }
  $script:GlowCol = @{ Green = Col '#3FD97A'; Orange = Col '#F0A83A'; Red = Col '#FF5A60'; Gray = Col '#000000' }
}
function Set-LangResources {
  $script:LangIdx = if ((Get-Lang) -eq 'en') { 1 } else { 0 }
  foreach ($k in $script:S.Keys) { $app.Resources["s.$k"] = $script:S[$k][$script:LangIdx] }
}
Set-ThemeResources (Get-EffTheme)
Set-LangResources

function Animate($target, $prop, $to, $ms = 220, $from = $null, $delay = 0) {
  $a = New-Object Windows.Media.Animation.DoubleAnimation
  $a.To = [double]$to
  if ($null -ne $from) { $a.From = [double]$from }
  $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms))
  $a.BeginTime = [TimeSpan]::FromMilliseconds($delay)
  $e = New-Object Windows.Media.Animation.CubicEase; $e.EasingMode = 'EaseOut'; $a.EasingFunction = $e
  $dp = switch ($prop) {
    'Opacity' { [Windows.UIElement]::OpacityProperty }
    'Height'  { [Windows.FrameworkElement]::HeightProperty }
    'Y'       { [Windows.Media.TranslateTransform]::YProperty }
    'X'       { [Windows.Media.TranslateTransform]::XProperty }
    'ScaleX'  { [Windows.Media.ScaleTransform]::ScaleXProperty }
    'ScaleY'  { [Windows.Media.ScaleTransform]::ScaleYProperty }
    'Angle'   { [Windows.Media.RotateTransform]::AngleProperty }
  }
  $target.BeginAnimation($dp, $a)
}
function Spin($rot, [bool]$on) {
  if ($on) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation 0, 360, (New-Object Windows.Duration ([TimeSpan]::FromSeconds(0.9)))
    $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $a)
  } else { $rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null) }
}

# снимок всего окна поверх него самого, который плавно тает — так смена темы/языка выглядит как crossfade.
# снимаем окно целиком (а не элемент через VisualBrush) — иначе снимок съезжает и окно «дёргается»
function Snap-Fade($w, $img) {
  if (-not $w -or -not $img -or -not $w.IsVisible -or $w.ActualWidth -lt 1) { return }
  $src = [Windows.PresentationSource]::FromVisual($w)
  $sc = if ($src) { $src.CompositionTarget.TransformToDevice.M11 } else { 1 }
  $img.BeginAnimation([Windows.UIElement]::OpacityProperty, $null); $img.Opacity = 0
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($w.ActualWidth * $sc)), ([int]($w.ActualHeight * $sc)), (96 * $sc), (96 * $sc), ([Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($w); $rtb.Freeze()
  $img.Source = $rtb
  Animate $img 'Opacity' 0 380 1
}
function Start-Crossfade {
  Snap-Fade $win $fadeImg
  if ($script:DlgFade) { Snap-Fade $script:DlgFade.Win $script:DlgFade.Img }
}

# ================= XAML =================
function Ico($glyph, $text, $size = 12, $gap = 8) {
  $t = if ($text) { "<TextBlock Text=`"$text`" VerticalAlignment=`"Center`"/>" } else { '' }
  $m = if ($text) { "0,1,$gap,0" } else { '0' }
  "<StackPanel Orientation=`"Horizontal`"><TextBlock Text=`"$glyph`" FontFamily=`"$IconFont`" FontSize=`"$size`" VerticalAlignment=`"Center`" Margin=`"$m`"/>$t</StackPanel>"
}
$NS = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'

$BtnTemplate = @"
<Setter Property="Template"><Setter.Value>
  <ControlTemplate TargetType="Button">
    <Grid x:Name="R" RenderTransformOrigin="0.5,0.5">
      <Grid.RenderTransform><ScaleTransform x:Name="S"/></Grid.RenderTransform>
      <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10"/>
      <Border x:Name="H" Background="{DynamicResource B.hover}" Opacity="0" CornerRadius="10"/>
      <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Grid>
    <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True">
        <Trigger.EnterActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="H" Storyboard.TargetProperty="Opacity" To="0.075" Duration="0:0:0.15"/></Storyboard></BeginStoryboard></Trigger.EnterActions>
        <Trigger.ExitActions><BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetName="H" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.25"/></Storyboard></BeginStoryboard></Trigger.ExitActions>
      </Trigger>
      <Trigger Property="IsPressed" Value="True">
        <Trigger.EnterActions><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetName="S" Storyboard.TargetProperty="ScaleX" To="0.965" Duration="0:0:0.08"/>
          <DoubleAnimation Storyboard.TargetName="S" Storyboard.TargetProperty="ScaleY" To="0.965" Duration="0:0:0.08"/>
        </Storyboard></BeginStoryboard></Trigger.EnterActions>
        <Trigger.ExitActions><BeginStoryboard><Storyboard>
          <DoubleAnimation Storyboard.TargetName="S" Storyboard.TargetProperty="ScaleX" To="1" Duration="0:0:0.18"/>
          <DoubleAnimation Storyboard.TargetName="S" Storyboard.TargetProperty="ScaleY" To="1" Duration="0:0:0.18"/>
        </Storyboard></BeginStoryboard></Trigger.ExitActions>
      </Trigger>
      <Trigger Property="IsEnabled" Value="False"><Setter TargetName="R" Property="Opacity" Value="0.38"/></Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate>
</Setter.Value></Setter>
"@

$Styles = @"
<Style x:Key="BtnBase" TargetType="Button">
  <Setter Property="Foreground" Value="{DynamicResource B.btnFg}"/><Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="Medium"/><Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Padding" Value="16,0"/><Setter Property="Height" Value="40"/><Setter Property="Focusable" Value="False"/>
  <Setter Property="BorderThickness" Value="0"/><Setter Property="Background" Value="Transparent"/>
  $BtnTemplate
</Style>
<Style x:Key="Accent" TargetType="Button" BasedOn="{StaticResource BtnBase}">
  <Setter Property="Foreground" Value="White"/><Setter Property="FontWeight" Value="SemiBold"/>
  <Setter Property="Background"><Setter.Value>
    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#EE916C" Offset="0"/><GradientStop Color="#CC5F3F" Offset="1"/></LinearGradientBrush>
  </Setter.Value></Setter>
</Style>
<Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource BtnBase}">
  <Setter Property="Foreground" Value="White"/><Setter Property="FontWeight" Value="SemiBold"/>
  <Setter Property="Background"><Setter.Value>
    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#F2666B" Offset="0"/><GradientStop Color="#C9363C" Offset="1"/></LinearGradientBrush>
  </Setter.Value></Setter>
</Style>
<Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource BtnBase}">
  <Setter Property="Background" Value="{DynamicResource B.ghost}"/><Setter Property="BorderBrush" Value="{DynamicResource B.ghostLine}"/><Setter Property="BorderThickness" Value="1"/>
</Style>
<Style x:Key="Icon" TargetType="Button" BasedOn="{StaticResource BtnBase}">
  <Setter Property="Foreground" Value="{DynamicResource B.icon}"/><Setter Property="FontFamily" Value="$IconFont"/><Setter Property="FontSize" Value="13"/>
  <Setter Property="Width" Value="36"/><Setter Property="Height" Value="36"/><Setter Property="Padding" Value="0"/>
  <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{DynamicResource B.iconHover}"/></Trigger></Style.Triggers>
</Style>
<Style x:Key="Chrome" TargetType="Button" BasedOn="{StaticResource Icon}">
  <Setter Property="Width" Value="40"/><Setter Property="Height" Value="34"/><Setter Property="FontSize" Value="10"/>
</Style>
<Style x:Key="ChromeClose" TargetType="Button" BasedOn="{StaticResource Chrome}">
  <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#E5484D"/><Setter Property="Foreground" Value="White"/></Trigger></Style.Triggers>
</Style>
<Style x:Key="Caption" TargetType="TextBlock">
  <Setter Property="FontSize" Value="10.5"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="{DynamicResource B.caption}"/>
</Style>
<Style x:Key="Input" TargetType="TextBox">
  <Setter Property="Foreground" Value="{DynamicResource B.text}"/><Setter Property="Background" Value="{DynamicResource B.input}"/><Setter Property="BorderBrush" Value="{DynamicResource B.inputLine}"/>
  <Setter Property="CaretBrush" Value="{DynamicResource B.text}"/><Setter Property="SelectionBrush" Value="#D97757"/><Setter Property="FontSize" Value="13"/><Setter Property="Height" Value="40"/>
  <Setter Property="Padding" Value="0"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="TextBox">
      <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="10">
        <Grid Margin="12,0">
          <!-- Padding текст получает от самого TextBox, подсказке задаём его вручную -->
          <TextBlock x:Name="Ph" Text="{TemplateBinding Tag}" Margin="{TemplateBinding Padding}" Foreground="{DynamicResource B.ph}" VerticalAlignment="Center" Visibility="Collapsed" IsHitTestVisible="False" TextTrimming="CharacterEllipsis"/>
          <ScrollViewer x:Name="PART_ContentHost" VerticalAlignment="Center"/>
        </Grid>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="Text" Value=""><Setter TargetName="Ph" Property="Visibility" Value="Visible"/></Trigger>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{DynamicResource B.inputHover}"/></Trigger>
        <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#D97757"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="Toggle" TargetType="CheckBox">
  <Setter Property="Foreground" Value="{DynamicResource B.text2}"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Focusable" Value="False"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="CheckBox">
      <StackPanel Orientation="Horizontal" Background="Transparent">
        <Grid Width="40" Height="22" VerticalAlignment="Center">
          <Border CornerRadius="11" Background="{DynamicResource B.track}"/>
          <Border x:Name="On" CornerRadius="11" Opacity="0">
            <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#EE916C" Offset="0"/><GradientStop Color="#CC5F3F" Offset="1"/></LinearGradientBrush></Border.Background>
          </Border>
          <Ellipse Width="16" Height="16" Fill="White" HorizontalAlignment="Left" Margin="3,0,0,0">
            <Ellipse.RenderTransform><TranslateTransform x:Name="K"/></Ellipse.RenderTransform>
          </Ellipse>
        </Grid>
        <ContentPresenter Margin="11,0,0,0" VerticalAlignment="Center"/>
      </StackPanel>
      <ControlTemplate.Triggers>
        <Trigger Property="IsChecked" Value="True">
          <Trigger.EnterActions><BeginStoryboard><Storyboard>
            <DoubleAnimation Storyboard.TargetName="K" Storyboard.TargetProperty="X" To="18" Duration="0:0:0.18"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
            <DoubleAnimation Storyboard.TargetName="On" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.18"/>
          </Storyboard></BeginStoryboard></Trigger.EnterActions>
          <Trigger.ExitActions><BeginStoryboard><Storyboard>
            <DoubleAnimation Storyboard.TargetName="K" Storyboard.TargetProperty="X" To="0" Duration="0:0:0.18"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
            <DoubleAnimation Storyboard.TargetName="On" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.18"/>
          </Storyboard></BeginStoryboard></Trigger.ExitActions>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="Seg" TargetType="RadioButton">
  <Setter Property="Foreground" Value="{DynamicResource B.segFg}"/><Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="Medium"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Focusable" Value="False"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="RadioButton">
      <Border x:Name="B" CornerRadius="8" Padding="15,8" Background="Transparent"><ContentPresenter HorizontalAlignment="Center"/></Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="{DynamicResource B.segHover}"/><Setter Property="Foreground" Value="{DynamicResource B.text2}"/></Trigger>
        <Trigger Property="IsChecked" Value="True"><Setter TargetName="B" Property="Background" Value="{DynamicResource B.segOn}"/><Setter Property="Foreground" Value="{DynamicResource B.segOnFg}"/></Trigger>
        <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="SegBox" TargetType="Border">
  <Setter Property="Background" Value="{DynamicResource B.seg}"/><Setter Property="BorderBrush" Value="{DynamicResource B.segLine}"/><Setter Property="BorderThickness" Value="1"/>
  <Setter Property="CornerRadius" Value="11"/><Setter Property="Padding" Value="3"/><Setter Property="HorizontalAlignment" Value="Left"/>
</Style>
<Style x:Key="Swatch" TargetType="RadioButton">
  <Setter Property="Cursor" Value="Hand"/><Setter Property="Focusable" Value="False"/><Setter Property="Margin" Value="0,0,8,0"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="RadioButton">
      <Grid Width="34" Height="34" Background="Transparent">
        <Ellipse x:Name="Ring" Stroke="{DynamicResource B.swatchRing}" StrokeThickness="2" Opacity="0"/>
        <Ellipse Margin="5" Fill="{TemplateBinding Background}"/>
      </Grid>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Ring" Property="Opacity" Value="0.35"/></Trigger>
        <Trigger Property="IsChecked" Value="True"><Setter TargetName="Ring" Property="Opacity" Value="1"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="DarkMenu" TargetType="ContextMenu">
  <Setter Property="HasDropShadow" Value="False"/><Setter Property="MinWidth" Value="230"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ContextMenu">
      <Border Background="{DynamicResource B.menu}" BorderBrush="{DynamicResource B.menuLine}" BorderThickness="1" CornerRadius="12" Padding="6"><StackPanel IsItemsHost="True"/></Border>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="DarkItem" TargetType="MenuItem">
  <Setter Property="Foreground" Value="{DynamicResource B.text2}"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="MenuItem">
      <Border x:Name="B" Background="Transparent" CornerRadius="7" Padding="10,8"><ContentPresenter ContentSource="Header"/></Border>
      <ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="B" Property="Background" Value="{DynamicResource B.menuHover}"/></Trigger></ControlTemplate.Triggers>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="DarkSep" TargetType="Separator">
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Separator"><Border Height="1" Margin="8,5" Background="{DynamicResource B.menuLine}"/></ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType="ToolTip">
  <Setter Property="Foreground" Value="{DynamicResource B.text2}"/><Setter Property="FontSize" Value="12"/><Setter Property="HasDropShadow" Value="False"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ToolTip">
      <Border Background="{DynamicResource B.menu}" BorderBrush="{DynamicResource B.menuLine}" BorderThickness="1" CornerRadius="8" Padding="10,6"><ContentPresenter/></Border>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style TargetType="ScrollBar">
  <Setter Property="Width" Value="8"/><Setter Property="MinWidth" Value="8"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ScrollBar">
      <Track x:Name="PART_Track" IsDirectionReversed="True">
        <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="{DynamicResource B.thumb}"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
      </Track>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
"@

$MainXaml = @"
<Window $NS Title="Claude Accounts" Width="1130" Height="680" MinWidth="640" MinHeight="480" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResize" WindowStartupLocation="CenterScreen"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Ideal" AllowDrop="True">
  <WindowChrome.WindowChrome><WindowChrome CaptionHeight="0" ResizeBorderThickness="14" GlassFrameThickness="0" CornerRadius="0"/></WindowChrome.WindowChrome>
  <Window.Resources>$Styles</Window.Resources>
  <Grid>
  <Grid x:Name="Shell" Margin="16" Opacity="0" RenderTransformOrigin="0.5,0.5">
    <Grid.RenderTransform><ScaleTransform x:Name="ShellScale" ScaleX="0.97" ScaleY="0.97"/></Grid.RenderTransform>
    <Border CornerRadius="20" Background="{DynamicResource B.bg0}"><Border.Effect><DropShadowEffect BlurRadius="28" ShadowDepth="4" Opacity="{DynamicResource N.shadow}"/></Border.Effect></Border>
    <Border CornerRadius="20" BorderBrush="{DynamicResource B.line}" BorderThickness="1" Background="{DynamicResource B.shellBg}">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>

        <Grid x:Name="TitleBar" Background="Transparent" Margin="28,22,14,0">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Border Width="44" Height="44" CornerRadius="13">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#F09A76" Offset="0"/><GradientStop Color="#C4533A" Offset="1"/></LinearGradientBrush></Border.Background>
              <Border.Effect><DropShadowEffect Color="#E07A55" BlurRadius="22" ShadowDepth="0" Opacity="0.5"/></Border.Effect>
              <TextBlock Text="&#x2733;" FontFamily="Segoe UI Symbol" FontSize="23" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,0,0,2"/>
            </Border>
            <TextBlock Text="Claude Accounts" FontSize="21" FontWeight="SemiBold" Foreground="{DynamicResource B.text}" Margin="15,0,0,1" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,10,0">
              <Border x:Name="SumOkB" CornerRadius="9" Background="{DynamicResource B.greenBg}" Padding="10,5" Margin="0,0,6,0"><StackPanel Orientation="Horizontal"><Ellipse Width="6" Height="6" Fill="{DynamicResource B.green}" Margin="0,1,7,0" VerticalAlignment="Center"/><TextBlock x:Name="SumOk" FontSize="12" FontWeight="Medium" Foreground="{DynamicResource B.greenText}"/></StackPanel></Border>
              <Border x:Name="SumLimB" CornerRadius="9" Background="{DynamicResource B.redBg}" Padding="10,5"><StackPanel Orientation="Horizontal"><Ellipse Width="6" Height="6" Fill="{DynamicResource B.red}" Margin="0,1,7,0" VerticalAlignment="Center"/><TextBlock x:Name="SumLim" FontSize="12" FontWeight="Medium" Foreground="{DynamicResource B.redText}"/></StackPanel></Border>
            </StackPanel>
            <Button x:Name="BtnRefresh" Style="{StaticResource Chrome}">
              <TextBlock Text="&#xE72C;" FontFamily="$IconFont" FontSize="12.5" RenderTransformOrigin="0.5,0.5"><TextBlock.RenderTransform><RotateTransform x:Name="RefreshRot"/></TextBlock.RenderTransform></TextBlock>
            </Button>
            <Button x:Name="BtnLang" Style="{StaticResource Chrome}" FontSize="11.5" FontWeight="SemiBold" ToolTip="{DynamicResource s.langTip}"/>
            <Button x:Name="BtnTheme" Style="{StaticResource Chrome}" FontSize="13.5" ToolTip="{DynamicResource s.themeTip}"/>
            <Button x:Name="BtnSettings" Style="{StaticResource Chrome}" Content="&#xE713;" FontSize="13" ToolTip="{DynamicResource s.settings}"/>
            <Border Width="1" Height="16" Background="{DynamicResource B.line}" Margin="6,0" VerticalAlignment="Center"/>
            <Button x:Name="BtnMin" Style="{StaticResource Chrome}" Content="&#xE921;" ToolTip="{DynamicResource s.minimize}"/>
            <Button x:Name="BtnClose" Style="{StaticResource ChromeClose}" Content="&#xE8BB;" ToolTip="{DynamicResource s.close}"/>
          </StackPanel>
        </Grid>

        <Border Grid.Row="1" Margin="28,20,28,0" CornerRadius="16" Background="{DynamicResource B.panel}" BorderBrush="{DynamicResource B.panelLine}" BorderThickness="1" Padding="10">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBox x:Name="Folder" Style="{StaticResource Input}" Padding="26,0,0,0" Tag="{DynamicResource s.folderPh}" AllowDrop="True"/>
            <TextBlock Text="&#xE8B7;" FontFamily="$IconFont" FontSize="14" Foreground="{DynamicResource B.muted}" VerticalAlignment="Center" Margin="15,0,0,0" IsHitTestVisible="False"/>
            <Button x:Name="BtnRecent" Grid.Column="1" Style="{StaticResource Ghost}" Width="40" Padding="0" Margin="8,0,0,0" ToolTip="{DynamicResource s.recent}">$(Ico '&#xE81C;' '' 14)</Button>
            <Button x:Name="BtnBrowse" Grid.Column="2" Style="{StaticResource Ghost}" Margin="8,0,0,0" Content="{DynamicResource s.browse}"/>
            <Button x:Name="BtnBest" Grid.Column="3" Style="{StaticResource Accent}" Margin="10,0,0,0" Padding="18,0" ToolTip="{DynamicResource s.bestTip}">$(Ico '&#xE945;' '{DynamicResource s.best}' 13)</Button>
          </Grid>
        </Border>

        <ScrollViewer x:Name="Scroll" Grid.Row="2" Margin="28,20,14,14" Padding="0,0,14,0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <WrapPanel x:Name="Cards"/>
        </ScrollViewer>

        <Border x:Name="Toast" Grid.RowSpan="3" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,28" CornerRadius="12"
                Background="{DynamicResource B.toast}" BorderBrush="{DynamicResource B.toastLine}" BorderThickness="1" Padding="16,11" Opacity="0" IsHitTestVisible="False">
          <Border.Effect><DropShadowEffect BlurRadius="20" ShadowDepth="3" Opacity="{DynamicResource N.shadow}"/></Border.Effect>
          <Border.RenderTransform><TranslateTransform x:Name="ToastY" Y="24"/></Border.RenderTransform>
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="ToastIcon" FontFamily="$IconFont" FontSize="14" VerticalAlignment="Center" Margin="0,0,11,0"/>
            <TextBlock x:Name="ToastText" Foreground="{DynamicResource B.text}" FontSize="13" VerticalAlignment="Center"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>
  </Grid>
  <Image x:Name="Fade" IsHitTestVisible="False" Stretch="Fill" Opacity="0"/>
  </Grid>
</Window>
"@

# полоса лимита: название + время до сброса слева, процент справа, под ними шкала
function LimitBar($p, $label) {
@"
<Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Orientation="Horizontal" VerticalAlignment="Bottom" Margin="0,0,0,2">
    <TextBlock Text="$label" FontSize="12.5" FontWeight="Medium" Foreground="{DynamicResource B.muted}" VerticalAlignment="Center"/>
    <StackPanel x:Name="${p}Reset" Orientation="Horizontal" VerticalAlignment="Center" Margin="10,0,0,0" Background="Transparent">
      <TextBlock Text="&#xE916;" FontFamily="$IconFont" FontSize="10.5" Foreground="{DynamicResource B.faint}" VerticalAlignment="Center" Margin="0,1,5,0"/>
      <TextBlock x:Name="${p}ResetText" FontSize="12" Foreground="{DynamicResource B.faint}" VerticalAlignment="Center"/>
    </StackPanel>
  </StackPanel>
  <TextBlock Grid.Column="1" VerticalAlignment="Bottom"><Run x:Name="${p}Num" FontSize="20" FontWeight="Bold"/><Run x:Name="${p}Unit" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource B.muted}"/></TextBlock>
  <Grid Grid.Row="1" Grid.ColumnSpan="2" Height="8" Margin="0,7,0,0">
    <Border x:Name="${p}Track" CornerRadius="4" Background="{DynamicResource B.gaugeTrack}"/>
    <Border x:Name="${p}Bar" CornerRadius="4" HorizontalAlignment="Left" Width="0">
      <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="0" Opacity="0"/></Border.Effect>
    </Border>
  </Grid>
</Grid>
"@
}

$CardXaml = @"
<Border $NS Width="331" Margin="0,0,16,16" Opacity="0" VerticalAlignment="Top">
  <Border.RenderTransform><TransformGroup><TranslateTransform x:Name="Lift" Y="16"/><TranslateTransform x:Name="Hov"/></TransformGroup></Border.RenderTransform>
  <Border.Triggers>
    <EventTrigger RoutedEvent="MouseEnter"><BeginStoryboard><Storyboard>
      <DoubleAnimation Storyboard.TargetName="Glow" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.22"/>
      <DoubleAnimation Storyboard.TargetName="Hov" Storyboard.TargetProperty="Y" To="-3" Duration="0:0:0.22"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
    </Storyboard></BeginStoryboard></EventTrigger>
    <EventTrigger RoutedEvent="MouseLeave"><BeginStoryboard><Storyboard>
      <DoubleAnimation Storyboard.TargetName="Glow" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.3"/>
      <DoubleAnimation Storyboard.TargetName="Hov" Storyboard.TargetProperty="Y" To="0" Duration="0:0:0.3"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
    </Storyboard></BeginStoryboard></EventTrigger>
  </Border.Triggers>
  <Grid>
    <Border CornerRadius="18" Background="{DynamicResource B.card}" BorderBrush="{DynamicResource B.cardLine}" BorderThickness="1">
      <Border.Effect><DropShadowEffect BlurRadius="22" ShadowDepth="3" Direction="270" Opacity="{DynamicResource N.cardShadow}"/></Border.Effect>
    </Border>
    <Border x:Name="Glow" CornerRadius="18" BorderThickness="1" Opacity="0"/>
    <Grid Margin="20,18,20,20">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Grid x:Name="AvatarWrap" Width="44" Height="44" VerticalAlignment="Center" Background="Transparent">
          <Border x:Name="Avatar" CornerRadius="13">
            <Border.Effect><DropShadowEffect BlurRadius="16" ShadowDepth="0" Opacity="0.4"/></Border.Effect>
            <TextBlock x:Name="Initial" Foreground="White" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <Ellipse x:Name="StatusDot" Width="14" Height="14" StrokeThickness="2.5" Stroke="{DynamicResource B.card}" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,-3,-3"/>
        </Grid>
        <StackPanel Grid.Column="1" Margin="13,0,4,0" VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="AccName" FontSize="15.5" FontWeight="SemiBold" Foreground="{DynamicResource B.text}" TextTrimming="CharacterEllipsis" MaxWidth="150" VerticalAlignment="Center"/>
            <Border x:Name="PlanBadge" CornerRadius="5" Padding="6,1" Margin="8,1,0,0" VerticalAlignment="Center" Background="{DynamicResource B.planBg}">
              <TextBlock x:Name="Plan" FontSize="9.5" FontWeight="Bold" Foreground="{DynamicResource B.planText}"/>
            </Border>
            <TextBlock x:Name="BestStar" Text="&#xE735;" FontFamily="$IconFont" FontSize="12" Foreground="#F0A060" Margin="7,1,0,0" VerticalAlignment="Center" Visibility="Collapsed" ToolTip="{DynamicResource s.bestStar}"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
            <TextBlock x:Name="ProxyIco" Text="&#xE774;" FontFamily="$IconFont" FontSize="11" Foreground="{DynamicResource B.faint}" VerticalAlignment="Center" Margin="0,1,6,0" Visibility="Collapsed"/>
            <TextBlock x:Name="Email" FontSize="12" Foreground="{DynamicResource B.muted}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="190"/>
          </StackPanel>
        </StackPanel>
        <Button x:Name="More" Grid.Column="2" Style="{DynamicResource Icon}" Content="&#xE712;" VerticalAlignment="Top" Margin="0,-4,-8,0" ToolTip="{DynamicResource s.actions}"/>
      </Grid>

      <Grid Grid.Row="1" Margin="0,20,0,0">
        <StackPanel x:Name="Limits" Background="Transparent">
          $(LimitBar 'Five' '{DynamicResource s.five}')
          <Border Height="16"/>
          $(LimitBar 'Week' '{DynamicResource s.week}')
        </StackPanel>
        <Border x:Name="NoLogin" CornerRadius="14" Background="{DynamicResource B.noLogin}" BorderBrush="{DynamicResource B.insetLine}" BorderThickness="1" Padding="16,0" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Border Width="38" Height="38" CornerRadius="19" Background="{DynamicResource B.noLoginIcon}"><TextBlock Text="&#xE77B;" FontFamily="$IconFont" FontSize="15" Foreground="{DynamicResource B.muted}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
            <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
              <TextBlock Text="{DynamicResource s.noLogin}" FontSize="13.5" FontWeight="SemiBold" Foreground="{DynamicResource B.text2}"/>
              <TextBlock Text="{DynamicResource s.noLoginHint}" FontSize="12" Foreground="{DynamicResource B.muted}" Margin="0,2,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </StackPanel>
        </Border>
      </Grid>

      <Border x:Name="Warn" Grid.Row="2" Margin="0,14,0,0" CornerRadius="9" Background="{DynamicResource B.orangeBg}" Padding="10,6" Visibility="Collapsed">
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="&#xE7BA;" FontFamily="$IconFont" FontSize="11.5" Foreground="{DynamicResource B.orange}" VerticalAlignment="Center" Margin="0,1,8,0"/>
          <TextBlock x:Name="WarnText" FontSize="12" Foreground="{DynamicResource B.orange}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
      </Border>

      <Button x:Name="Run" Grid.Row="3" Margin="0,18,0,0" Style="{DynamicResource Accent}" Height="42" FontSize="14">
        <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="RunIcon" Text="&#xE768;" FontFamily="$IconFont" FontSize="13" VerticalAlignment="Center" Margin="0,1,10,0"/>
          <TextBlock x:Name="RunText" VerticalAlignment="Center"/>
        </StackPanel>
      </Button>
    </Grid>
  </Grid>
</Border>
"@

$AddTileXaml = @"
<Border $NS Width="331" Margin="0,0,16,16" Cursor="Hand" Background="Transparent" Opacity="0" VerticalAlignment="Top" MinHeight="200">
  <Border.RenderTransform><TranslateTransform x:Name="Lift" Y="16"/></Border.RenderTransform>
  <Border.Triggers>
    <EventTrigger RoutedEvent="MouseEnter"><BeginStoryboard><Storyboard>
      <DoubleAnimation Storyboard.TargetName="HoverBg" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.2"/>
      <DoubleAnimation Storyboard.TargetName="PlusScale" Storyboard.TargetProperty="ScaleX" To="1.1" Duration="0:0:0.2"/>
      <DoubleAnimation Storyboard.TargetName="PlusScale" Storyboard.TargetProperty="ScaleY" To="1.1" Duration="0:0:0.2"/>
    </Storyboard></BeginStoryboard></EventTrigger>
    <EventTrigger RoutedEvent="MouseLeave"><BeginStoryboard><Storyboard>
      <DoubleAnimation Storyboard.TargetName="HoverBg" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.3"/>
      <DoubleAnimation Storyboard.TargetName="PlusScale" Storyboard.TargetProperty="ScaleX" To="1" Duration="0:0:0.3"/>
      <DoubleAnimation Storyboard.TargetName="PlusScale" Storyboard.TargetProperty="ScaleY" To="1" Duration="0:0:0.3"/>
    </Storyboard></BeginStoryboard></EventTrigger>
  </Border.Triggers>
  <Grid>
    <Rectangle RadiusX="18" RadiusY="18" Stroke="{DynamicResource B.dash}" StrokeThickness="1.5" StrokeDashArray="6 4"/>
    <Border x:Name="HoverBg" CornerRadius="18" Opacity="0">
      <Border.Background><RadialGradientBrush><GradientStop Color="#22D97757" Offset="0"/><GradientStop Color="#08D97757" Offset="1"/></RadialGradientBrush></Border.Background>
    </Border>
    <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
      <Border Width="56" Height="56" CornerRadius="28" HorizontalAlignment="Center" RenderTransformOrigin="0.5,0.5" Background="{DynamicResource B.addBg}">
        <Border.RenderTransform><ScaleTransform x:Name="PlusScale"/></Border.RenderTransform>
        <TextBlock Text="&#xE710;" FontFamily="$IconFont" FontSize="19" Foreground="#E8845F" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <TextBlock Text="{DynamicResource s.addAcc}" FontSize="15" FontWeight="SemiBold" Foreground="{DynamicResource B.text2}" Margin="0,14,0,0" HorizontalAlignment="Center"/>
    </StackPanel>
  </Grid>
</Border>
"@

function Dialog-Shell($width, $body) {
@"
<Window $NS WindowStyle="None" AllowsTransparency="True" Background="Transparent" SizeToContent="Height" Width="$width"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False" ResizeMode="NoResize" TextOptions.TextFormattingMode="Ideal" UseLayoutRounding="True">
  <Window.Resources>$Styles</Window.Resources>
  <Grid>
  <Grid x:Name="Root" Margin="22" Opacity="0" RenderTransformOrigin="0.5,0.5">
    <Grid.RenderTransform><ScaleTransform x:Name="Sc" ScaleX="0.95" ScaleY="0.95"/></Grid.RenderTransform>
    <Border CornerRadius="18" Background="{DynamicResource B.dialog}"><Border.Effect><DropShadowEffect BlurRadius="32" ShadowDepth="5" Opacity="{DynamicResource N.shadow}"/></Border.Effect></Border>
    <Border CornerRadius="18" BorderBrush="{DynamicResource B.dialogLine}" BorderThickness="1" Padding="28,24,28,24" Background="{DynamicResource B.dialogBg}">
      <StackPanel>
        <Grid x:Name="Drag" Background="Transparent">
          <StackPanel Margin="0,0,40,0">
            <TextBlock x:Name="Title" FontSize="20" FontWeight="SemiBold" Foreground="{DynamicResource B.text}"/>
            <TextBlock x:Name="Sub" FontSize="12.5" Foreground="{DynamicResource B.muted}" Margin="0,6,0,0" TextWrapping="Wrap" LineHeight="18"/>
          </StackPanel>
          <Button x:Name="X" Style="{StaticResource Icon}" Content="&#xE8BB;" FontSize="10" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-6,-12,0"/>
        </Grid>
        $body
      </StackPanel>
    </Border>
  </Grid>
  <Image x:Name="Fade" IsHitTestVisible="False" Stretch="Fill" Opacity="0"/>
  </Grid>
</Window>
"@
}

$AccBody = @"
<TextBlock Text="{DynamicResource s.aName}" Style="{StaticResource Caption}" Margin="0,24,0,8"/>
<TextBox x:Name="AName" Style="{StaticResource Input}" Tag="{DynamicResource s.aNamePh}"/>
<TextBlock Text="{DynamicResource s.aColor}" Style="{StaticResource Caption}" Margin="0,18,0,6"/>
<StackPanel x:Name="Swatches" Orientation="Horizontal" Margin="-5,0,0,0"/>

<TextBlock Text="{DynamicResource s.aProxy}" Style="{StaticResource Caption}" Margin="0,18,0,8"/>
<Border Style="{StaticResource SegBox}">
  <StackPanel Orientation="Horizontal">
    <RadioButton x:Name="PxNone" GroupName="px" Style="{StaticResource Seg}" Content="{DynamicResource s.aPxNone}"/>
    <RadioButton x:Name="PxOn" GroupName="px" Style="{StaticResource Seg}" Content="{DynamicResource s.aPxOn}"/>
  </StackPanel>
</Border>
<StackPanel x:Name="PxPanel" Margin="0,10,0,0">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <TextBox x:Name="Proxy" Style="{StaticResource Input}" Tag="{DynamicResource s.aPxPh}"/>
    <Button x:Name="Check" Grid.Column="1" Style="{StaticResource Ghost}" Margin="8,0,0,0" MinWidth="128">$(Ico '&#xE73E;' '{DynamicResource s.aCheck}')</Button>
  </Grid>
  <Border x:Name="PxStatus" CornerRadius="10" Padding="13,10" Margin="0,8,0,0" Visibility="Collapsed">
    <StackPanel Orientation="Horizontal">
      <TextBlock x:Name="PxIcon" FontFamily="$IconFont" FontSize="13" VerticalAlignment="Center" Margin="0,0,10,0" RenderTransformOrigin="0.5,0.5">
        <TextBlock.RenderTransform><RotateTransform x:Name="PxRot"/></TextBlock.RenderTransform>
      </TextBlock>
      <TextBlock x:Name="PxText" FontSize="12.5" VerticalAlignment="Center" TextWrapping="Wrap" MaxWidth="470"/>
    </StackPanel>
  </Border>
</StackPanel>
<TextBlock x:Name="PxNoneHint" Text="{DynamicResource s.aPxNoneHint}" FontSize="12" Foreground="{DynamicResource B.caption}" Margin="2,9,0,0"/>

<TextBlock Text="{DynamicResource s.aLaunch}" Style="{StaticResource Caption}" Margin="0,22,0,10"/>
<CheckBox x:Name="Full" Style="{StaticResource Toggle}" Content="{DynamicResource s.aFull}"/>
<TextBlock Text="{DynamicResource s.aArgs}" FontSize="12" Foreground="{DynamicResource B.muted}" Margin="0,14,0,7"/>
<TextBox x:Name="Args" Style="{StaticResource Input}" Tag="{DynamicResource s.aArgsPh}"/>

<StackPanel x:Name="DirRow" Margin="0,16,0,0">
  <TextBlock Text="{DynamicResource s.aDir}" FontSize="12" Foreground="{DynamicResource B.muted}" Margin="0,0,0,5"/>
  <Grid>
    <TextBlock x:Name="Dir" FontSize="12.5" Foreground="{DynamicResource B.text2}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,44,0"/>
    <Button x:Name="OpenDir" Style="{StaticResource Icon}" Content="&#xE8B7;" HorizontalAlignment="Right" ToolTip="{DynamicResource s.aOpenDir}"/>
  </Grid>
</StackPanel>

<Grid Margin="0,26,0,0">
  <TextBlock x:Name="Hint" Foreground="{DynamicResource B.orange}" FontSize="12" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,270,0"/>
  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
    <Button x:Name="Cancel" Content="{DynamicResource s.cancel}" Style="{StaticResource Ghost}" Width="110" Margin="0,0,10,0" IsCancel="True"/>
    <Button x:Name="Ok" Style="{StaticResource Accent}" MinWidth="150"/>
  </StackPanel>
</Grid>
"@

$SetBody = @"
<TextBlock Text="{DynamicResource s.sAppearance}" Style="{StaticResource Caption}" Margin="0,24,0,10"/>
<Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
  <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
  <TextBlock Text="{DynamicResource s.sTheme}" FontSize="13" Foreground="{DynamicResource B.text2}" VerticalAlignment="Center" Margin="0,0,18,0"/>
  <Border Grid.Column="1" Style="{StaticResource SegBox}">
    <StackPanel Orientation="Horizontal">
      <RadioButton x:Name="ThDark" GroupName="th" Style="{StaticResource Seg}">$(Ico '&#xE708;' '{DynamicResource s.thDark}' 12 7)</RadioButton>
      <RadioButton x:Name="ThLight" GroupName="th" Style="{StaticResource Seg}">$(Ico '&#xE706;' '{DynamicResource s.thLight}' 12 7)</RadioButton>
      <RadioButton x:Name="ThSys" GroupName="th" Style="{StaticResource Seg}">$(Ico '&#xE7F4;' '{DynamicResource s.thSys}' 12 7)</RadioButton>
    </StackPanel>
  </Border>
  <TextBlock Grid.Row="1" Text="{DynamicResource s.sLang}" FontSize="13" Foreground="{DynamicResource B.text2}" VerticalAlignment="Center" Margin="0,10,18,0"/>
  <Border Grid.Row="1" Grid.Column="1" Style="{StaticResource SegBox}" Margin="0,10,0,0">
    <StackPanel Orientation="Horizontal">
      <RadioButton x:Name="LRu" GroupName="lang" Style="{StaticResource Seg}" Content="Русский"/>
      <RadioButton x:Name="LEn" GroupName="lang" Style="{StaticResource Seg}" Content="English"/>
    </StackPanel>
  </Border>
</Grid>
<TextBlock Text="{DynamicResource s.sRefresh}" Style="{StaticResource Caption}" Margin="0,22,0,8"/>
<Border Style="{StaticResource SegBox}">
  <StackPanel x:Name="Intervals" Orientation="Horizontal"/>
</Border>
<TextBlock Text="{DynamicResource s.sTerminal}" Style="{StaticResource Caption}" Margin="0,20,0,8"/>
<Border Style="{StaticResource SegBox}">
  <StackPanel Orientation="Horizontal">
    <RadioButton x:Name="TCmd" GroupName="term" Style="{StaticResource Seg}" Content="{DynamicResource s.sCmd}"/>
    <RadioButton x:Name="TWt" GroupName="term" Style="{StaticResource Seg}" Content="Windows Terminal"/>
  </StackPanel>
</Border>
<TextBlock Text="{DynamicResource s.sBehavior}" Style="{StaticResource Caption}" Margin="0,20,0,10"/>
<CheckBox x:Name="MinLaunch" Style="{StaticResource Toggle}" Content="{DynamicResource s.sMinLaunch}"/>
<TextBlock Text="{DynamicResource s.sTools}" Style="{StaticResource Caption}" Margin="0,22,0,8"/>
<WrapPanel>
  <Button x:Name="Sync" Style="{StaticResource Ghost}" Margin="0,0,8,8">$(Ico '&#xE895;' '{DynamicResource s.sSync}')</Button>
  <Button x:Name="OpenCfg" Style="{StaticResource Ghost}" Margin="0,0,8,8">$(Ico '&#xE8A5;' '{DynamicResource s.sCfg}')</Button>
</WrapPanel>
<TextBlock Text="{DynamicResource s.sSyncHint}" FontSize="11.5" Foreground="{DynamicResource B.caption}" TextWrapping="Wrap" Margin="0,2,0,0"/>
<StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,24,0,0">
  <Button x:Name="Cancel" Content="{DynamicResource s.cancel}" Style="{StaticResource Ghost}" Width="110" Margin="0,0,10,0" IsCancel="True"/>
  <Button x:Name="Ok" Content="{DynamicResource s.save}" Style="{StaticResource Accent}" MinWidth="130"/>
</StackPanel>
"@

$ConfirmBody = @"
<StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,24,0,0">
  <Button x:Name="Cancel" Content="{DynamicResource s.cancel}" Style="{StaticResource Ghost}" Width="110" Margin="0,0,10,0" IsCancel="True"/>
  <Button x:Name="Ok" MinWidth="130" IsDefault="True"/>
</StackPanel>
"@

# ================= dialogs =================
function Open-Dialog($xaml, $names) {
  $d = [Windows.Markup.XamlReader]::Parse($xaml)
  $d.Owner = $win; $d.FontFamily = $UiFont
  if ($IconPath -and $win.Icon) { $d.Icon = $win.Icon }
  $f = @{ D = $d }
  foreach ($n in @('Root', 'Sc', 'Drag', 'Title', 'Sub', 'X', 'Fade') + $names) { $f[$n] = $d.FindName($n) }
  $f.Drag.Add_MouseLeftButtonDown({ param($s, $e) try { [Windows.Window]::GetWindow($s).DragMove() } catch {} })
  $f.X.Add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).Close() })
  $d.Add_Loaded({ param($s, $e)
    $r = $s.FindName('Root'); $sc = $s.FindName('Sc')
    Animate $r 'Opacity' 1 200 0; Animate $sc 'ScaleX' 1 280 0.95; Animate $sc 'ScaleY' 1 280 0.95 })
  $f
}

function Arm-Shot($dlg, $file) {
  $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(3); $t.Tag = @{ D = $dlg; F = $file }
  $t.Add_Tick({ param($s, $e) $s.Stop(); Save-Shot $s.Tag.D $s.Tag.F; $s.Tag.D.Close() }); $t.Start()
}

function Show-Confirm($title, $text, $okText = 'OK', [switch]$Danger, [switch]$Info) {
  $f = Open-Dialog (Dialog-Shell 480 $ConfirmBody) @('Cancel', 'Ok')
  $f.Title.Text = $title; $f.Sub.Text = $text
  $f.Ok.Content = $okText
  $f.Ok.Style = if ($Danger) { $f.D.Resources['Danger'] } else { $f.D.Resources['Accent'] }
  if ($Info) { $f.Cancel.Visibility = 'Collapsed' }
  $f.Ok.Add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).DialogResult = $true })
  [bool]$f.D.ShowDialog()
}

function Set-PxStatus($f, $kind, $text) {
  $f.PxStatus.Visibility = 'Visible'
  $f.PxText.Text = $text
  switch ($kind) {
    'ok'   { $f.PxStatus.Background = $BR.GreenBg;  $f.PxText.Foreground = $BR.Green;  $f.PxIcon.Foreground = $BR.Green;  $f.PxIcon.Text = [string][char]0xE73E; Spin $f.PxRot $false }
    'err'  { $f.PxStatus.Background = $BR.RedBg;    $f.PxText.Foreground = $BR.Red;    $f.PxIcon.Foreground = $BR.Red;    $f.PxIcon.Text = [string][char]0xE783; Spin $f.PxRot $false }
    'busy' { $f.PxStatus.Background = $BR.OrangeBg; $f.PxText.Foreground = $BR.Orange; $f.PxIcon.Foreground = $BR.Orange; $f.PxIcon.Text = [string][char]0xE72C; Spin $f.PxRot $true }
  }
  Animate $f.PxStatus 'Opacity' 1 220 0
}

function Validate-AccDialog($f) {
  $ok = $true; $hint = ''
  if (-not $f.AName.Text.Trim()) { $ok = $false; $hint = T 'vName' }
  elseif ($f.PxOn.IsChecked) {
    $n = Normalize-Proxy $f.Proxy.Text
    if (-not $n.Ok) { $ok = $false; $hint = $n.Err }
    elseif ($f.S.Busy) { $ok = $false; $hint = T 'vBusy' }
    elseif ($f.S.FailedUrl -eq $n.Url) { $ok = $false; $hint = T 'vFailed' }
    elseif ($f.S.CheckedUrl -ne $n.Url) { $ok = $false; $hint = T 'vCheck' }
  }
  $f.Ok.IsEnabled = $ok; $f.Hint.Text = $hint
}

function Run-ProxyCheck($f) {
  $n = Normalize-Proxy $f.Proxy.Text
  if (-not $n.Ok) { Set-PxStatus $f 'err' $n.Err; return }
  $f.S.Busy = $true; $f.Check.IsEnabled = $false
  Set-PxStatus $f 'busy' (TF 'pxChecking' (Proxy-Display $n.Url))
  Validate-AccDialog $f
  Start-Net 'check' $null $n.Url @{ F = $f; Url = $n.Url } {
    param($r, $c)
    $f = $c.F
    $f.S.Busy = $false; $f.Check.IsEnabled = $true
    if (-not $f.D.IsVisible) { return }
    if ((Normalize-Proxy $f.Proxy.Text).Url -ne $c.Url) { $f.PxStatus.Visibility = 'Collapsed'; Validate-AccDialog $f; return }
    if ($r.Ok) {
      $f.S.CheckedUrl = $c.Url; $f.S.FailedUrl = $null
      $loc = ''
      if ($r.Ip) { $loc = ' · IP ' + $r.Ip }
      if ($r.City -or $r.Country) { $loc += ' · ' + ((@($r.City, $r.Country) | Where-Object { $_ }) -join ', ') }
      Set-PxStatus $f 'ok' (TF 'pxOk' $r.Ms $loc)
    } else {
      $f.S.CheckedUrl = $null; $f.S.FailedUrl = $c.Url
      Set-PxStatus $f 'err' (Net-ErrText $r)
    }
    Validate-AccDialog $f
  }
}

function Show-AccountDialog($acc) {
  $isNew = -not $acc
  $f = Open-Dialog (Dialog-Shell 600 $AccBody) @('AName', 'Swatches', 'PxNone', 'PxOn', 'PxPanel', 'Proxy', 'Check', 'PxStatus', 'PxIcon', 'PxRot', 'PxText', 'PxNoneHint', 'Full', 'Args', 'DirRow', 'Dir', 'OpenDir', 'Hint', 'Cancel', 'Ok')
  $f.S = @{ Busy = $false; CheckedUrl = $null; Color = 0 }
  if ($isNew) {
    $f.Title.Text = T 'aNewTitle'
    $f.Sub.Text = T 'aNewSub'
    $f.Ok.Content = T 'aNewOk'
    $f.AName.Text = 'Account ' + ($script:cfg.accounts.Count + 1)
    $f.S.Color = $script:cfg.accounts.Count % $Palette.Count
    $f.Full.IsChecked = $true
    $f.PxNone.IsChecked = $true
    $f.DirRow.Visibility = 'Collapsed'
  } else {
    $f.Title.Text = T 'aEditTitle'
    $f.Sub.Text = T 'aEditSub'
    $f.Ok.Content = T 'save'
    $f.AName.Text = $acc.name
    $f.S.Color = [int]$acc.color
    $f.Full.IsChecked = [bool]$acc.fullAccess
    $f.Args.Text = $acc.args
    $f.Dir.Text = $acc.dir
    $f.OpenDir.Tag = $acc.dir
    $f.OpenDir.Add_Click({ param($s, $e) Start-Process explorer.exe $s.Tag })
    if ($acc.proxy) { $f.PxOn.IsChecked = $true; $f.Proxy.Text = $acc.proxy; $f.S.CheckedUrl = (Normalize-Proxy $acc.proxy).Url }
    else { $f.PxNone.IsChecked = $true }
  }

  for ($i = 0; $i -lt $Palette.Count; $i++) {
    $rb = New-Object Windows.Controls.RadioButton
    $rb.Style = $f.D.Resources['Swatch']; $rb.GroupName = 'sw'; $rb.Tag = @{ I = $i; F = $f }
    $rb.Background = Grad $Palette[$i][0] $Palette[$i][1] 45
    $rb.IsChecked = ($i -eq $f.S.Color)
    $rb.Add_Checked({ param($s, $e) $s.Tag.F.S.Color = $s.Tag.I })
    [void]$f.Swatches.Children.Add($rb)
  }

  $f.D.Tag = $f
  $pxMode = { param($s, $e)
    $f = [Windows.Window]::GetWindow($s).Tag
    $on = [bool]$f.PxOn.IsChecked
    $f.PxPanel.Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
    $f.PxNoneHint.Visibility = if ($on) { 'Collapsed' } else { 'Visible' }
    if ($on) { Animate $f.PxPanel 'Opacity' 1 220 0; [void]$f.Proxy.Focus() }
    Validate-AccDialog $f }
  $f.PxNone.Add_Checked($pxMode); $f.PxOn.Add_Checked($pxMode)
  $f.PxPanel.Visibility = if ($f.PxOn.IsChecked) { 'Visible' } else { 'Collapsed' }
  $f.PxNoneHint.Visibility = if ($f.PxOn.IsChecked) { 'Collapsed' } else { 'Visible' }

  $f.AName.Add_TextChanged({ param($s, $e) Validate-AccDialog ([Windows.Window]::GetWindow($s).Tag) })
  $f.Proxy.Add_TextChanged({ param($s, $e)
    $f = [Windows.Window]::GetWindow($s).Tag
    if ($f.S.CheckedUrl -ne (Normalize-Proxy $f.Proxy.Text).Url) { $f.PxStatus.Visibility = 'Collapsed' }
    Validate-AccDialog $f })
  $f.Proxy.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Run-ProxyCheck ([Windows.Window]::GetWindow($s).Tag); $e.Handled = $true } })
  $f.Check.Add_Click({ param($s, $e) Run-ProxyCheck ([Windows.Window]::GetWindow($s).Tag) })
  $f.Ok.Add_Click({ param($s, $e)
    $w = [Windows.Window]::GetWindow($s); Validate-AccDialog $w.Tag
    if ($w.Tag.Ok.IsEnabled) { $w.DialogResult = $true } })
  $f.D.Add_ContentRendered({ param($s, $e)
    $f = $s.Tag; [void]$f.AName.Focus(); $f.AName.SelectAll()
    if ($f.PxOn.IsChecked -and $f.Proxy.Text) { Run-ProxyCheck $f } })
  Validate-AccDialog $f

  if ($env:CA_SHOT_DIALOG) {
    if ($env:CA_DIALOG_PROXY) { $f.PxOn.IsChecked = $true; $f.Proxy.Text = $env:CA_DIALOG_PROXY }
    $f.D.Add_ContentRendered({ param($s, $e) if ($env:CA_DIALOG_PROXY) { Run-ProxyCheck $s.Tag } })
    Arm-Shot $f.D $env:CA_SHOT_DIALOG
  }

  if (-not $f.D.ShowDialog()) { return $null }
  $proxy = if ($f.PxOn.IsChecked) { (Normalize-Proxy $f.Proxy.Text).Url } else { '' }
  @{ name = $f.AName.Text.Trim(); color = $f.S.Color; proxy = $proxy; fullAccess = [bool]$f.Full.IsChecked; args = $f.Args.Text.Trim() }
}

function Show-Settings {
  $f = Open-Dialog (Dialog-Shell 580 $SetBody) @('ThDark', 'ThLight', 'ThSys', 'LRu', 'LEn', 'Intervals', 'TCmd', 'TWt', 'MinLaunch', 'Sync', 'OpenCfg', 'Cancel', 'Ok')
  # заголовок через ресурсы — чтобы он переводился на лету при смене языка прямо в диалоге
  $f.Title.SetResourceReference([Windows.Controls.TextBlock]::TextProperty, 's.setTitle')
  $f.Sub.SetResourceReference([Windows.Controls.TextBlock]::TextProperty, 's.setSub')
  $f.S = @{ Interval = $script:cfg.refreshSec }
  foreach ($opt in @(@(300, 'iv300'), @(600, 'iv600'), @(900, 'iv900'), @(1800, 'iv1800'))) {
    $rb = New-Object Windows.Controls.RadioButton
    $rb.Style = $f.D.Resources['Seg']; $rb.GroupName = 'iv'; $rb.Tag = @{ V = $opt[0]; F = $f }
    $rb.SetResourceReference([Windows.Controls.ContentControl]::ContentProperty, 's.' + $opt[1])
    $rb.IsChecked = ($opt[0] -eq $script:cfg.refreshSec)
    $rb.Add_Checked({ param($s, $e) $s.Tag.F.S.Interval = $s.Tag.V })
    [void]$f.Intervals.Children.Add($rb)
  }
  if (-not $HasWt) { $f.TWt.IsEnabled = $false; $f.TWt.SetResourceReference([Windows.FrameworkElement]::ToolTipProperty, 's.noWt') }
  if ($script:cfg.terminal -eq 'wt' -and $HasWt) { $f.TWt.IsChecked = $true } else { $f.TCmd.IsChecked = $true }
  $f.MinLaunch.IsChecked = [bool]$script:cfg.minimizeOnLaunch

  # тема и язык применяются сразу (превью), «Отмена» возвращает как было
  $orig = @{ Theme = $script:cfg.theme; Lang = $script:cfg.lang }
  switch ($script:cfg.theme) { 'dark' { $f.ThDark.IsChecked = $true } 'light' { $f.ThLight.IsChecked = $true } default { $f.ThSys.IsChecked = $true } }
  if ($script:cfg.lang -eq 'en') { $f.LEn.IsChecked = $true } else { $f.LRu.IsChecked = $true }
  $f.ThDark.Add_Checked({ Set-Theme 'dark' }); $f.ThLight.Add_Checked({ Set-Theme 'light' }); $f.ThSys.Add_Checked({ Set-Theme 'system' })
  $f.LRu.Add_Checked({ Set-Lang 'ru' }); $f.LEn.Add_Checked({ Set-Lang 'en' })

  $f.Sync.Add_Click({ Sync-Settings })
  $f.OpenCfg.Add_Click({ Start-Process notepad.exe $CfgPath })
  $f.Ok.Add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).DialogResult = $true })
  if ($env:CA_SHOT_SETTINGS) { Arm-Shot $f.D $env:CA_SHOT_SETTINGS }
  $script:DlgFade = @{ Win = $f.D; Img = $f.Fade }
  $ok = $f.D.ShowDialog()
  $script:DlgFade = $null
  if (-not $ok) { Set-Theme $orig.Theme; Set-Lang $orig.Lang; return }
  $script:cfg.refreshSec = [int]$f.S.Interval
  $script:cfg.terminal = if ($f.TWt.IsChecked) { 'wt' } else { 'cmd' }
  $script:cfg.minimizeOnLaunch = [bool]$f.MinLaunch.IsChecked
  Save-Cfg; Update-All
  Show-Toast (T 'tSaved') 'ok'
}

# ================= theme / language switching =================
function Apply-Theme([switch]$Fade) {
  $name = Get-EffTheme
  if ($name -eq $script:CurTheme -and $Fade) { return }
  if ($Fade) { Start-Crossfade }
  Set-ThemeResources $name
  $btnTheme.Content = [string][char]$(if ($name -eq 'dark') { 0xE706 } else { 0xE708 })
  Update-All
  foreach ($st in $script:States) { foreach ($p in 'Five', 'Week') { Draw-Gauge $st $p } }
}
function Apply-Lang([switch]$Fade) {
  if ($Fade) { Start-Crossfade }
  Set-LangResources
  $btnLang.Content = if ($script:LangIdx) { 'EN' } else { 'RU' }
  Update-All
}
function Set-Theme($t) { if ($script:cfg.theme -eq $t) { return }; $script:cfg.theme = $t; Save-Cfg; Apply-Theme -Fade }
function Set-Lang($l) { if ($script:cfg.lang -eq $l) { return }; $script:cfg.lang = $l; Save-Cfg; Apply-Lang -Fade }

# ================= actions =================
function Copy-Settings($src, $dst) {
  if (Test-Path -LiteralPath (Join-Path $src 'settings.json')) { Copy-Item -LiteralPath (Join-Path $src 'settings.json') -Destination $dst -Force }
  foreach ($sub in 'skills', 'plugins') {
    $s = Join-Path $src $sub
    if (Test-Path -LiteralPath $s) { & robocopy.exe $s (Join-Path $dst $sub) /E /R:0 /W:0 /NFL /NDL /NJH /NJS /NP | Out-Null }
  }
}

function Add-Account {
  $r = Show-AccountDialog $null
  if (-not $r) { return }
  $i = 2
  while ((Test-Path -LiteralPath (Join-Path $UserHome ".claude-acc$i")) -or ($script:cfg.accounts | Where-Object { $_.dir -ieq (Join-Path $UserHome ".claude-acc$i") })) { $i++ }
  $dir = Join-Path $UserHome ".claude-acc$i"
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  Copy-Settings $script:cfg.accounts[0].dir $dir
  try {
    $main = Read-Shared (Get-GlobalJson $script:cfg.accounts[0].dir) | ConvertFrom-Json
    $o = [ordered]@{ hasCompletedOnboarding = $true; lastOnboardingVersion = $main.lastOnboardingVersion; mcpServers = $main.mcpServers }
    [IO.File]::WriteAllText((Join-Path $dir '.claude.json'), (ConvertTo-Json -InputObject $o -Depth 50), $Utf8NoBom)
  } catch {}
  $script:cfg.accounts += @{ name = $r.name; dir = $dir; color = $r.color; proxy = $r.proxy; fullAccess = $r.fullAccess; args = $r.args }
  Save-Cfg; Build-Cards; Refresh-All
  Show-Toast (TF 'tAdded' $r.name) 'ok'
}

function Edit-Account($st) {
  $r = Show-AccountDialog $st.Acc
  if (-not $r) { return }
  foreach ($k in 'name', 'color', 'proxy', 'fullAccess', 'args') { $st.Acc[$k] = $r[$k] }
  Save-Cfg; Build-Cards; Refresh-All
  Show-Toast (T 'tAccSaved') 'ok'
}

function Sync-Settings {
  if ($script:cfg.accounts.Count -lt 2) { [void](Show-Confirm (T 'syncTitle') (T 'syncNeed2') (T 'gotIt') -Info); return }
  $src = $script:cfg.accounts[0]
  if (-not (Show-Confirm (T 'syncAsk') (TF 'syncText' $src.name) (T 'syncOk'))) { return }
  foreach ($a in $script:cfg.accounts | Select-Object -Skip 1) { Copy-Settings $src.dir $a.dir }
  Show-Toast (T 'tSynced') 'ok'
}

function Get-Folder {
  $f = $tbFolder.Text.Trim().Trim('"')
  if (-not $f) { return $UserHome }
  if (Test-Path -LiteralPath $f -PathType Container) { return (Resolve-Path -LiteralPath $f).Path }
  if (Test-Path -LiteralPath $f -PathType Leaf) { return Split-Path -LiteralPath $f -Parent }
  $null
}

function Start-Claude($st) {
  $acc = $st.Acc
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { [void](Show-Confirm (T 'noClaude') (T 'noClaudeText') (T 'gotIt') -Info); return }
  $folder = Get-Folder
  if (-not $folder) { Show-Toast (TF 'noFolder' $tbFolder.Text) 'err'; return }
  $script:cfg.recent = @(@($folder) + @($script:cfg.recent | Where-Object { $_ -ine $folder }) | Select-Object -First 12)
  $tbFolder.Text = $folder
  Save-Cfg

  # окружение передаём явно в команде — так оно не зависит от того, как терминал наследует переменные
  $sets = @()
  if (Is-DefaultDir $acc.dir) { $sets += 'set "CLAUDE_CONFIG_DIR="' } else { $sets += "set `"CLAUDE_CONFIG_DIR=$($acc.dir)`"" }
  if ($acc.proxy) { $sets += "set `"HTTPS_PROXY=$($acc.proxy)`""; $sets += "set `"HTTP_PROXY=$($acc.proxy)`"" }
  else { $sets += 'set "HTTPS_PROXY="'; $sets += 'set "HTTP_PROXY="' }
  $title = 'Claude - ' + ($acc.name -replace '[^\w\s\-\.#]', '')
  $cmdLine = 'claude'
  if ($acc.fullAccess) { $cmdLine += ' --dangerously-skip-permissions' }
  if ($acc.args) { $cmdLine += ' ' + $acc.args }
  $inner = (@($sets) + "title $title" + $cmdLine) -join ' && '

  if ($script:cfg.terminal -eq 'wt' -and $HasWt) {
    $wtInner = $inner -replace ';', '\;'
    Start-Process wt.exe -ArgumentList "-w new -d `"$folder`" --title `"$title`" cmd /k `"$wtInner`""
  } else {
    Start-Process cmd.exe -ArgumentList "/k `"$inner`"" -WorkingDirectory $folder
  }
  $key = if ($st.LoggedIn) { 'tLaunched' } else { 'tLoginOpen' }
  Show-Toast (TF $key $acc.name (Split-Path $folder -Leaf)) 'ok'
  if ($script:cfg.minimizeOnLaunch) { $win.WindowState = 'Minimized' }
}

function Start-Best {
  $ready = @($script:States | Where-Object { $null -ne $_.Score -and $_.Score -lt 100 } | Sort-Object { $_.Score })
  if ($ready.Count) { Start-Claude $ready[0]; return }
  $logged = @($script:States | Where-Object { $_.LoggedIn })
  if (-not $logged.Count) { Show-Toast (T 'noLogged') 'err'; return }
  $next = $null; $nextSt = $null
  foreach ($st in $logged) {
    $eff = Get-Effective $st; if (-not $eff) { continue }
    foreach ($l in @($eff.Data.Five, $eff.Data.Week)) { if ($l -and $l.Reset -and $l.Pct -ge 100 -and (-not $next -or $l.Reset -lt $next)) { $next = $l.Reset; $nextSt = $st } }
  }
  if ($nextSt) { Show-Toast (TF 'allLimited' $nextSt.Acc.name (Fmt-Until $next)) 'err' }
  else { Start-Claude $logged[0] }
}

function Logout-Account($st) {
  $warn = if (Is-DefaultDir $st.Acc.dir) { T 'logoutMain' } else { '' }
  if (-not (Show-Confirm (TF 'logoutTitle' $st.Acc.name) (TF 'logoutText' $warn) (T 'logoutOk') -Danger)) { return }
  Remove-Item -LiteralPath (Join-Path $st.Acc.dir '.credentials.json') -Force -ErrorAction SilentlyContinue
  $st.Live = $null; $st.LiveAt = $null
  Refresh-All
  Show-Toast (TF 'tLoggedOut' $st.Acc.name) 'ok'
}

function Move-Account($st, $delta) {
  $list = [Collections.ArrayList]@($script:cfg.accounts)
  $i = $list.IndexOf($st.Acc); $j = $i + $delta
  if ($i -lt 0 -or $j -lt 0 -or $j -ge $list.Count) { return }
  $list.RemoveAt($i); $list.Insert($j, $st.Acc)
  $script:cfg.accounts = @($list)
  Save-Cfg; Build-Cards; Update-All
}

function Remove-Account($st) {
  if ($script:cfg.accounts.Count -le 1) { Show-Toast (T 'keepOne') 'err'; return }
  if (-not (Show-Confirm (TF 'removeTitle' $st.Acc.name) (TF 'removeText' $st.Acc.dir) (T 'removeOk') -Danger)) { return }
  $script:cfg.accounts = @($script:cfg.accounts | Where-Object { -not [object]::ReferenceEquals($_, $st.Acc) })
  Save-Cfg; Build-Cards; Update-All
}

function New-Menu($items) {
  $m = New-Object Windows.Controls.ContextMenu
  $m.Style = $win.Resources['DarkMenu']; $m.FontFamily = $UiFont
  foreach ($it in $items) {
    if ($it -eq '-') {
      $sep = New-Object Windows.Controls.Separator; $sep.Style = $win.Resources['DarkSep']
      [void]$m.Items.Add($sep); continue
    }
    $mi = New-Object Windows.Controls.MenuItem
    $mi.Style = $win.Resources['DarkItem']
    $hdr = New-Object Windows.Controls.StackPanel; $hdr.Orientation = 'Horizontal'
    $ic = New-Object Windows.Controls.TextBlock; $ic.Text = $it.Icon; $ic.FontFamily = $IconFont; $ic.FontSize = 12; $ic.Width = 26; $ic.VerticalAlignment = 'Center'
    $tx = New-Object Windows.Controls.TextBlock; $tx.Text = $it.Text; $tx.VerticalAlignment = 'Center'
    if ($it.Color) { $ic.Foreground = $it.Color; $tx.Foreground = $it.Color } else { $ic.Foreground = $BR.Muted }
    [void]$hdr.Children.Add($ic); [void]$hdr.Children.Add($tx)
    $mi.Header = $hdr; $mi.Tag = $it.Tag
    $mi.Add_Click($it.Click)
    [void]$m.Items.Add($mi)
  }
  $m
}

function Show-AccMenu($btn, $st) {
  $menu = New-Menu @(
    @{ Icon = [string][char]0xE713; Text = (T 'mSettings'); Tag = $st; Click = { param($s, $e) Edit-Account $s.Tag } }
    @{ Icon = [string][char]0xE72C; Text = (T 'mRefresh'); Tag = $st; Click = { param($s, $e) Read-Local $s.Tag; Start-Fetch $s.Tag; Update-All; Update-Spinner } }
    @{ Icon = [string][char]0xE8B7; Text = (T 'mDir'); Tag = $st; Click = { param($s, $e) Start-Process explorer.exe $s.Tag.Acc.dir } }
    '-'
    @{ Icon = [string][char]0xE70E; Text = (T 'mUp'); Tag = $st; Click = { param($s, $e) Move-Account $s.Tag -1 } }
    @{ Icon = [string][char]0xE70D; Text = (T 'mDown'); Tag = $st; Click = { param($s, $e) Move-Account $s.Tag 1 } }
    '-'
    @{ Icon = [string][char]0xE7E8; Text = (T 'mLogout'); Tag = $st; Click = { param($s, $e) Logout-Account $s.Tag } }
    @{ Icon = [string][char]0xE74D; Text = (T 'mRemove'); Tag = $st; Color = $BR.Red; Click = { param($s, $e) Remove-Account $s.Tag } }
  )
  $menu.PlacementTarget = $btn; $menu.Placement = 'Bottom'; $menu.HorizontalOffset = -190; $menu.IsOpen = $true
}

# ================= cards / limit bars =================
$script:States = @()
$CardParts = 'Glow', 'Lift', 'AvatarWrap', 'Avatar', 'Initial', 'StatusDot', 'AccName', 'PlanBadge', 'Plan', 'BestStar', 'ProxyIco', 'Email', 'More',
             'Limits', 'NoLogin', 'Warn', 'WarnText', 'Run', 'RunIcon', 'RunText',
             'FiveReset', 'FiveResetText', 'FiveNum', 'FiveUnit', 'FiveTrack', 'FiveBar',
             'WeekReset', 'WeekResetText', 'WeekNum', 'WeekUnit', 'WeekTrack', 'WeekBar'

# ширина карточек подстраивается под окно: столько колонок, сколько влезает при ширине от 300
function Layout-Cards {
  $W = $cardsPanel.ActualWidth
  if ($W -lt 50) { return }
  $cols = [math]::Max(1, [math]::Floor($W / 316))
  $w = [math]::Floor($W / $cols) - 16
  foreach ($c in $cardsPanel.Children) { $c.Width = $w }
}

function Build-Cards {
  $cardsPanel.Children.Clear()
  $old = @{}; foreach ($st in $script:States) { $old[$st.Acc.dir] = $st }
  $script:States = @()
  $idx = 0
  foreach ($a in $script:cfg.accounts) {
    $card = [Windows.Markup.XamlReader]::Parse($CardXaml)
    $ui = @{}; foreach ($n in $CardParts) { $ui[$n] = $card.FindName($n) }
    $st = @{ Acc = $a; Ui = $ui; Card = $card; Live = $null; LiveAt = $null; Cache = $null; CacheAt = $null; Err = $null; Fetching = $false; RunStyle = 'Accent'
             G = @{ Five = @{ Cur = 0.0; Target = 0.0; Kind = 'Gray'; NoData = $true }; Week = @{ Cur = 0.0; Target = 0.0; Kind = 'Gray'; NoData = $true } } }
    if ($old.ContainsKey($a.dir)) {
      $o = $old[$a.dir]; $st.Live = $o.Live; $st.LiveAt = $o.LiveAt; $st.Err = $o.Err; $st.WasLimited = $o.WasLimited
      foreach ($p in 'Five', 'Week') { $st.G[$p].Cur = $o.G[$p].Cur }
    }
    $c = $Palette[[int]$a.color % $Palette.Count]
    $ui.Avatar.Background = Grad $c[0] $c[1] 45
    $ui.Avatar.Effect.Color = Col $c[0]
    $ui.Glow.BorderBrush = Grad ($c[0] -replace '#', '#AA') '#2025252C' 90
    $ui.Glow.Background = New-Object Windows.Media.LinearGradientBrush ((Col ($c[0] -replace '#', '#14'))), ((Col '#00000000')), 90
    $card.Tag = $st
    $ui.Run.Tag = $st; $ui.Run.Add_Click({ param($s, $e) Start-Claude $s.Tag })
    $ui.More.Tag = $st; $ui.More.Add_Click({ param($s, $e) Show-AccMenu $s $s.Tag })
    # ширина шкалы известна только после раскладки
    foreach ($p in 'Five', 'Week') {
      $ui["${p}Track"].Tag = @{ St = $st; P = $p }
      $ui["${p}Track"].Add_SizeChanged({ param($s, $e) Draw-Gauge $s.Tag.St $s.Tag.P })
    }
    Read-Local $st
    [void]$cardsPanel.Children.Add($card)
    Animate $card 'Opacity' 1 360 0 ($idx * 70)
    Animate $ui.Lift 'Y' 0 460 16 ($idx * 70)
    $script:States += $st
    $idx++
  }
  $tile = [Windows.Markup.XamlReader]::Parse($AddTileXaml)
  $tile.Add_MouseLeftButtonUp({ Add-Account })
  [void]$cardsPanel.Children.Add($tile)
  Animate $tile 'Opacity' 1 360 0 ($idx * 70)
  Animate $tile.FindName('Lift') 'Y' 0 460 16 ($idx * 70)
  # плитка «добавить» по высоте равна самой низкой карточке (без строки предупреждения)
  $fit = { $h = @($script:States | ForEach-Object { $_.Card.ActualHeight } | Where-Object { $_ -gt 0 } | Measure-Object -Minimum).Minimum; if ($h) { $tile.Height = $h } }.GetNewClosure()
  foreach ($st in $script:States) { $st.Card.Add_SizeChanged($fit) }
  Layout-Cards
  foreach ($st in $script:States) { Update-Card $st; foreach ($p in 'Five', 'Week') { Draw-Gauge $st $p } }
  Update-All
  $script:AnimTimer.Start()
}

function Draw-Gauge($st, $p) {
  $g = $st.G[$p]; $ui = $st.Ui
  $bar = $ui["${p}Bar"]; $W = $ui["${p}Track"].ActualWidth
  $pct = [math]::Max(0, [math]::Min(100, $g.Cur))
  # не уже высоты шкалы, чтобы скругления не ломались
  $bar.Width = if ($pct -lt 0.4 -or $W -lt 1) { 0 } else { [math]::Max(8, $W * $pct / 100) }
  $bar.Background = $BR["Ring$($g.Kind)"]
  $bar.Effect.Color = $GlowCol[$g.Kind]
  $bar.Effect.Opacity = if ($g.Kind -eq 'Gray') { 0 } else { $script:Th.glow * 0.8 }
  $ui["${p}Num"].Foreground = $BR["Num$($g.Kind)"]
  if ($g.NoData) { $ui["${p}Num"].Text = '—'; $ui["${p}Unit"].Text = '' }
  else { $ui["${p}Num"].Text = [string][int][math]::Round($g.Cur); $ui["${p}Unit"].Text = '%' }
}

function Set-Gauge($st, $p, $lim) {
  $g = $st.G[$p]; $ui = $st.Ui
  if (-not $lim) { $g.NoData = $true; $g.Target = 0.0; $g.Kind = 'Gray' }
  else {
    $v = [double](Eff-Pct $lim)
    $g.NoData = $false; $g.Target = $v
    $g.Kind = if ($v -ge 90) { 'Red' } elseif ($v -ge 70) { 'Orange' } else { 'Green' }
  }
  if ([math]::Abs($g.Cur - $g.Target) -gt 0.01) { $script:AnimTimer.Start() } else { Draw-Gauge $st $p }
  # время до сброса — только когда лимит реально тратится
  if ($lim -and $lim.Reset -and $lim.Reset -gt (Get-Date) -and (Eff-Pct $lim) -gt 0) {
    $ui["${p}ResetText"].Text = Fmt-Until $lim.Reset
    Set-Tip $ui["${p}Reset"] (TF 'resetTip' (Fmt-At $lim.Reset))
    $ui["${p}Reset"].Visibility = 'Visible'
  } else { $ui["${p}Reset"].Visibility = 'Collapsed' }
}

function Anim-Tick {
  $active = $false
  foreach ($st in $script:States) {
    foreach ($p in 'Five', 'Week') {
      $g = $st.G[$p]
      $d = $g.Target - $g.Cur
      if ([math]::Abs($d) -lt 0.01) { continue }
      if ([math]::Abs($d) -lt 0.3) { $g.Cur = $g.Target } else { $g.Cur += $d * 0.13; $active = $true }
      Draw-Gauge $st $p
    }
  }
  if (-not $active) { $script:AnimTimer.Stop() }
}

# подсказки обновляем только при изменении, иначе открытый tooltip мигает
function Set-Tip($el, $text) { if ([string]$el.ToolTip -ne $text) { $el.ToolTip = $text } }
function Set-Status($ui, $text, $kind) { $ui.StatusDot.Fill = $BR[$kind]; Set-Tip $ui.AvatarWrap $text }
# стиль кнопки меняем только при смене — пересоздание шаблона каждую секунду сбивает hover
function Set-RunStyle($st, $style) {
  if ($st.RunStyle -eq $style) { return }
  $st.RunStyle = $style
  $st.Ui.Run.SetResourceReference([Windows.FrameworkElement]::StyleProperty, $style)
}

function Update-Card($st) {
  $ui = $st.Ui; $a = $st.Acc
  $ui.AccName.Text = $a.name
  $ui.Initial.Text = if ($a.name -match '(\d+)\s*$') { $matches[1] } elseif ($a.name) { $a.name.Substring(0, 1).ToUpper() } else { '?' }
  if ($st.Plan) { $ui.Plan.Text = ([string]$st.Plan).ToUpper(); $ui.PlanBadge.Visibility = 'Visible' } else { $ui.PlanBadge.Visibility = 'Collapsed' }
  if ($a.proxy) {
    $ui.ProxyIco.Visibility = 'Visible'
    Set-Tip $ui.ProxyIco (TF 'proxyTip' $(if ($env:CA_DEMO) { 'proxy.example.com:8080' } else { Proxy-Display $a.proxy }))
  } else { $ui.ProxyIco.Visibility = 'Collapsed' }
  $st.Score = $null

  if (-not $st.LoggedIn) {
    $ui.Email.Text = T 'notSignedIn'
    $ui.Limits.Visibility = 'Hidden'; $ui.NoLogin.Visibility = 'Visible'; $ui.Warn.Visibility = 'Collapsed'
    Set-Status $ui (T 'stNoLogin') 'Gray'
    $ui.RunText.Text = T 'signIn'; $ui.RunIcon.Text = [string][char]0xE77B
    return
  }
  $ui.RunText.Text = T 'run'; $ui.RunIcon.Text = [string][char]0xE768
  $ui.Email.Text = if ($st.Email) { $st.Email } else { T 'signedIn' }
  if ($env:CA_DEMO) { $ui.Email.Text = 'you@example.com' }
  $ui.NoLogin.Visibility = 'Collapsed'; $ui.Limits.Visibility = 'Visible'
  $eff = Get-Effective $st
  if ($eff) {
    Set-Gauge $st 'Five' $eff.Data.Five
    Set-Gauge $st 'Week' $eff.Data.Week
    $mx = [math]::Max((Eff-Pct $eff.Data.Five), (Eff-Pct $eff.Data.Week))
    $st.Score = $mx
    if ($mx -ge 100) { Set-Status $ui (T 'stLim') 'Red' }
    elseif ($mx -ge 80) { Set-Status $ui (T 'stNear') 'Orange' }
    else { Set-Status $ui (T 'stOk') 'Green' }
    if ($st.WasLimited -and $mx -lt 100) { Show-Toast (TF 'backOnline' $a.name) 'ok' }
    $st.WasLimited = ($mx -ge 100)
  } else {
    Set-Gauge $st 'Five' $null; Set-Gauge $st 'Week' $null
    Set-Status $ui (T 'stNoData') 'Gray'
  }

  # свежесть данных — в подсказке к лимитам; на карточке только если что-то не так
  $why = $null
  if ($eff -and $eff.Src -eq 'live' -and -not $st.Err) { $tip = TF 'liveUpd' (Fmt-Ago $eff.At) }
  elseif ($st.Fetching -and -not $eff) { $tip = T 'loading' }
  else {
    $tip = T 'noData'
    if ($eff) { $tip = if ($eff.Src -eq 'live') { TF 'liveAgo' (Fmt-Ago $eff.At) } else { TF 'fromCache' (Fmt-Ago $eff.At) } }
    if ($st.TokenExpired -or $st.Err -eq 'token') { $why = T 'whyToken' }
    elseif ($st.Err -eq 'rate') { $why = T 'whyRate' }
    elseif ($st.Err -eq 'net') { $why = if ($a.proxy) { T 'whyNetPx' } else { T 'whyNet' } }
  }
  Set-Tip $ui.Limits $tip
  if ($why) {
    $ui.WarnText.Text = $why; Set-Tip $ui.Warn "$tip · $why"
    $ui.Warn.Visibility = 'Visible'
  } else { $ui.Warn.Visibility = 'Collapsed' }
}

function Update-All {
  foreach ($st in $script:States) { Update-Card $st }
  $cand = @($script:States | Where-Object { $null -ne $_.Score -and $_.Score -lt 100 } | Sort-Object { $_.Score })
  $best = if ($cand.Count) { $cand[0] } else { $null }
  # яркая кнопка — у лучшего аккаунта и у тех, где нужно войти; остальные спокойные
  foreach ($st in $script:States) {
    $isBest = $best -and [object]::ReferenceEquals($st, $best)
    Set-RunStyle $st $(if ($isBest -or -not $st.LoggedIn -or ($cand.Count -eq 0 -and $null -eq $st.Score)) { 'Accent' } else { 'Ghost' })
    $st.Ui.BestStar.Visibility = if ($isBest -and $cand.Count -ge 2) { 'Visible' } else { 'Collapsed' }
  }
  $okN = $cand.Count
  $limN = @($script:States | Where-Object { $null -ne $_.Score -and $_.Score -ge 100 }).Count
  $sumOk.Text = TF 'sumOk' $okN; $sumOkB.Visibility = if ($okN) { 'Visible' } else { 'Collapsed' }
  $sumLim.Text = TF 'sumLim' $limN; $sumLimB.Visibility = if ($limN) { 'Visible' } else { 'Collapsed' }
  $tip = T 'refreshTip'
  if (@($script:States | Where-Object { $_.Fetching }).Count) { $tip += "`n" + (T 'refreshing') }
  elseif ($script:LastRefresh) {
    $left = [int]($script:cfg.refreshSec - ((Get-Date) - $script:LastRefresh).TotalSeconds)
    $tip += "`n" + (TF 'checkedAt' (Fmt-Ago $script:LastRefresh) ([math]::Max(0, $left)))
  }
  $refreshTipText.Text = $tip
}

function Update-Spinner {
  $busy = @($script:States | Where-Object { $_.Fetching }).Count -gt 0
  if ($busy -and -not $script:Spinning) { Spin $refreshRot $true; $script:Spinning = $true }
  elseif (-not $busy -and $script:Spinning) { Spin $refreshRot $false; $script:Spinning = $false }
}

function Show-Toast($text, $kind = 'ok') {
  $toastText.Text = $text
  if ($kind -eq 'err') { $toastIcon.Text = [string][char]0xE783; $toastIcon.Foreground = $BR.Red }
  else { $toastIcon.Text = [string][char]0xE73E; $toastIcon.Foreground = $BR.Green }
  Animate $toast 'Opacity' 1 220; Animate $toastY 'Y' 0 320
  $script:ToastUntil = (Get-Date).AddSeconds(3.5)
}

function Save-Shot($w, $file) {
  $sc = [Windows.PresentationSource]::FromVisual($w).CompositionTarget.TransformToDevice.M11
  $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($w.ActualWidth * $sc)), ([int]($w.ActualHeight * $sc)), (96 * $sc), (96 * $sc), ([Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($w)
  $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
  $fs = [IO.File]::Create($file); $enc.Save($fs); $fs.Close()
}

# ================= window =================
$win = [Windows.Markup.XamlReader]::Parse($MainXaml)
if (Test-Path -LiteralPath $IconPath) { try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $IconPath)) } catch {} }
foreach ($n in 'Shell', 'ShellScale', 'Folder', 'Cards', 'SumOk', 'SumOkB', 'SumLim', 'SumLimB', 'RefreshRot', 'Toast', 'ToastY', 'ToastIcon', 'ToastText', 'BtnLang', 'BtnTheme', 'BtnRefresh') {
  Set-Variable -Name ($n.Substring(0, 1).ToLower() + $n.Substring(1)) -Value $win.FindName($n) -Scope Script
}
$tbFolder = $folder; $cardsPanel = $cards; $fadeImg = $win.FindName('Fade')
# шрифт задаётся кодом: через DynamicResource WPF его не принимает
$win.FontFamily = $UiFont; $btnLang.FontFamily = $UiFont

# подсказка у кнопки обновления — живой объект, текст меняется без пересоздания (не мигает)
$refreshTipText = New-Object Windows.Controls.TextBlock
$btnRefresh.ToolTip = New-Object Windows.Controls.ToolTip -Property @{ Content = $refreshTipText }

$script:AnimTimer = New-Object Windows.Threading.DispatcherTimer
$script:AnimTimer.Interval = [TimeSpan]::FromMilliseconds(16)
$script:AnimTimer.Add_Tick({ Anim-Tick })

$tbFolder.Text = if ($script:cfg.recent.Count) { $script:cfg.recent[0] } else { $PSScriptRoot }
if ($env:CA_DEMO) { $tbFolder.Text = 'C:\Projects\my-app' }

# окно тянется за любое пустое место; кнопки, поля, полоса прокрутки и всё кликабельное (Cursor=Hand) клик забирают себе
$win.Add_MouseLeftButtonDown({ param($s, $e)
  if ($e.ClickCount -ne 1) { return }
  $v = $e.OriginalSource
  while ($v) {
    if ($v -is [Windows.Controls.Primitives.ButtonBase] -or $v -is [Windows.Controls.Primitives.TextBoxBase] -or $v -is [Windows.Controls.Primitives.ScrollBar]) { return }
    if ($v -is [Windows.FrameworkElement] -and $v.Cursor -eq [Windows.Input.Cursors]::Hand) { return }
    $v = if ($v -is [Windows.Media.Visual]) { [Windows.Media.VisualTreeHelper]::GetParent($v) } else { $v.Parent }
  }
  try { $win.DragMove() } catch {}
})
$win.FindName('BtnMin').Add_Click({ $win.WindowState = 'Minimized' })
$win.FindName('BtnClose').Add_Click({ $win.Close() })
$win.FindName('BtnSettings').Add_Click({ Show-Settings })
$btnRefresh.Add_Click({ Refresh-All })
$btnTheme.Add_Click({ Set-Theme $(if ($script:CurTheme -eq 'dark') { 'light' } else { 'dark' }) })
$btnLang.Add_Click({ Set-Lang $(if ($script:LangIdx) { 'ru' } else { 'en' }) })
$win.FindName('BtnBest').Add_Click({ Start-Best })
$win.FindName('BtnBrowse').Add_Click({
  $d = New-Object Windows.Forms.FolderBrowserDialog
  $d.Description = T 'browseTitle'; $cur = Get-Folder; if ($cur) { $d.SelectedPath = $cur }
  if ($d.ShowDialog() -eq 'OK') { $tbFolder.Text = $d.SelectedPath }
})
$win.FindName('BtnRecent').Add_Click({ param($s, $e)
  $items = @($script:cfg.recent | ForEach-Object { @{ Icon = [string][char]0xE8B7; Text = $_; Tag = $_; Click = { param($x, $y) $tbFolder.Text = $x.Tag } } })
  if (-not $items.Count) { $items = @(@{ Icon = [string][char]0xE946; Text = (T 'recentEmpty'); Tag = $null; Click = {} }) }
  $m = New-Menu $items; $m.PlacementTarget = $s; $m.Placement = 'Bottom'; $m.IsOpen = $true
})
$win.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'F5') { Refresh-All; $e.Handled = $true } })
$cardsPanel.Add_SizeChanged({ param($s, $e) if ($e.WidthChanged) { Layout-Cards } })

$onDragOver = { param($s, $e)
  if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { $e.Effects = 'Copy' } else { $e.Effects = 'None' }
  $e.Handled = $true }
$onDrop = { param($s, $e)
  $p = @($e.Data.GetData([Windows.DataFormats]::FileDrop))[0]
  if ($p) { if (Test-Path -LiteralPath $p -PathType Leaf) { $p = Split-Path -LiteralPath $p -Parent }; $tbFolder.Text = $p; Show-Toast (TF 'folderPicked' (Split-Path $p -Leaf)) 'ok' }
  $e.Handled = $true }
$win.Add_PreviewDragOver($onDragOver); $win.Add_PreviewDrop($onDrop)
$tbFolder.Add_PreviewDragOver($onDragOver); $tbFolder.Add_PreviewDrop($onDrop)

$tick = New-Object Windows.Threading.DispatcherTimer
$tick.Interval = [TimeSpan]::FromSeconds(1)
$tick.Add_Tick({
  Update-All
  if (-not $script:LastRefresh -or ((Get-Date) - $script:LastRefresh).TotalSeconds -ge $script:cfg.refreshSec) { Refresh-All }
  if ($script:ToastUntil -and (Get-Date) -gt $script:ToastUntil) { $script:ToastUntil = $null; Animate $toast 'Opacity' 0 300; Animate $toastY 'Y' 24 300 }
  # тема «как в системе» следит за переключением Windows
  if ($script:cfg.theme -eq 'system' -and (Get-Date).Second % 3 -eq 0) { Apply-Theme -Fade }
})
$poll = New-Object Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromMilliseconds(200)
$poll.Add_Tick({ Collect-Jobs })
# при активации окна перечитываем только локальные файлы: лишние запросы лимитов упираются в 429
$win.Add_Activated({ foreach ($st in $script:States) { Read-Local $st }; Update-All })
$win.Add_ContentRendered({ Animate $shell 'Opacity' 1 280 0; Animate $shellScale 'ScaleX' 1 380 0.97; Animate $shellScale 'ScaleY' 1 380 0.97 })
$win.Add_Closing({ $tick.Stop(); $poll.Stop(); Save-Cfg; try { $script:Pool.Close() } catch {} })

# режим скриншота для проверки (CA_SHOT=путь.png, CA_SHOT_DIALOG / CA_SHOT_SETTINGS=путь.png, CA_THEME, CA_LANG)
if ($env:CA_SHOT) {
  $shot = New-Object Windows.Threading.DispatcherTimer; $shot.Interval = [TimeSpan]::FromSeconds(6)
  $shot.Add_Tick({
    $shot.Stop(); Save-Shot $win $env:CA_SHOT
    if ($env:CA_SHOT_DIALOG) { Add-Account }
    if ($env:CA_SHOT_SETTINGS) { Show-Settings }
    $win.Close() })
  $shot.Start()
}

Apply-Theme
Apply-Lang
Build-Cards
Refresh-All
$tick.Start(); $poll.Start()
[void]$win.ShowDialog()
