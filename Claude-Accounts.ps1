# Claude Accounts v3 - менеджер аккаунтов Claude Code с живыми лимитами (WPF)
# Каждый аккаунт = своя папка конфига (CLAUDE_CONFIG_DIR) + свой прокси. Account 1 = стандартная ~/.claude

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$UserHome   = $env:USERPROFILE
$DefaultDir = Join-Path $UserHome '.claude'
$CfgPath    = Join-Path $UserHome '.claude-switcher.json'
$IconPath   = Join-Path $PSScriptRoot 'claude-accounts.ico'
$Utf8NoBom  = New-Object Text.UTF8Encoding $false
$IconFont   = 'Segoe Fluent Icons, Segoe MDL2 Assets'
$HasWt      = [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)

# цвета аккаунтов: [светлый, тёмный]
$Palette = @(
  @('#F09A76', '#C9553A'), @('#7FA8FF', '#4769D6'), @('#5FD891', '#259A57'), @('#C79BFF', '#8853DB'),
  @('#F7C76A', '#C98B22'), @('#FF8FB8', '#D24A7E'), @('#5ED6D6', '#1F9A9E'), @('#A9B1C2', '#5E6678')
)

# ================= config =================
function Load-Cfg {
  $c = @{ version = 3; accounts = @(); recent = @(); refreshSec = 60; terminal = 'cmd'; minimizeOnLaunch = $false }
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
      if ($j.refreshSec) { $c.refreshSec = [int]$j.refreshSec }
      if ($j.terminal) { $c.terminal = [string]$j.terminal }
      if ($null -ne $j.minimizeOnLaunch) { $c.minimizeOnLaunch = [bool]$j.minimizeOnLaunch }
    } catch {}
  }
  if ($c.accounts.Count -eq 0) {
    $c.accounts = @(@{ name = 'Account 1'; dir = $DefaultDir; color = 0; proxy = ''; fullAccess = $true; args = '' })
  }
  $c
}
function Save-Cfg { [IO.File]::WriteAllText($CfgPath, (ConvertTo-Json -InputObject $script:cfg -Depth 6), $Utf8NoBom) }
$script:cfg = Load-Cfg

# ================= proxy helpers =================
# принимает host:port, host:port:user:pass, user:pass@host:port, http://user:pass@host:port
function Normalize-Proxy([string]$s) {
  $s = ([string]$s).Trim()
  if (-not $s) { return @{ Ok = $false; Err = 'Введи адрес прокси' } }
  if ($s -match '^socks') { return @{ Ok = $false; Err = 'SOCKS не поддерживается Claude Code — нужен HTTP-прокси' } }
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
  @{ Ok = $false; Err = 'Не понял формат. Пример: 1.2.3.4:8080:логин:пароль' }
}
function Proxy-Display($url) {
  if (-not $url) { return 'напрямую' }
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
  [DateTimeOffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime
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
    $req.Timeout = $timeout; $req.ReadWriteTimeout = $timeout; $req.UserAgent = 'claude-accounts/3.0'
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

  # mode = check: проверка прокси
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try { $r = (New-Req 'https://api.anthropic.com/v1/models' $proxy 12000 -Fresh).GetResponse(); $r.Close() }
  catch {
    $em = $_.Exception.Message
    $w = Get-WebEx $_.Exception
    if ($w -and $w.Response) {
      $code = [int]$w.Response.StatusCode
      if ($code -eq 407) { return @{ Ok = $false; Err = 'Прокси отклонил логин/пароль (407)' } }
      if ($code -ne 401 -and $code -ne 403 -and $code -ne 404) { return @{ Ok = $false; Err = "Прокси не смог достучаться до Anthropic (код $code)" } }
    } else {
      $status = if ($w) { [string]$w.Status } else { '' }
      $msg = switch ($status) {
        'Timeout'                    { 'Прокси не отвечает (таймаут 12 сек)' }
        'ConnectFailure'             { 'Не удалось подключиться к прокси — проверь host и порт' }
        'ProxyNameResolutionFailure' { 'Хост прокси не найден' }
        'NameResolutionFailure'      { 'Не удалось найти api.anthropic.com через прокси' }
        'ReceiveFailure'             { 'Прокси оборвал соединение' }
        'SecureChannelFailure'       { 'Ошибка TLS через прокси' }
        default                      { $em }
      }
      if ($em -match '407') { $msg = 'Прокси отклонил логин/пароль (407)' }
      return @{ Ok = $false; Err = $msg }
    }
  }
  $ms = $sw.ElapsedMilliseconds
  $ip = $null; $country = $null; $city = $null
  try { $j = (Read-Body ((New-Req 'https://ipinfo.io/json' $proxy 8000 -Fresh).GetResponse())) | ConvertFrom-Json; $ip = $j.ip; $country = $j.country; $city = $j.city } catch {}
  @{ Ok = $true; Ms = $ms; Ip = $ip; Country = $country; City = $city }
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
function Fmt-Time($dt) { if (-not $dt) { '?' } elseif ($dt.Date -eq (Get-Date).Date) { $dt.ToString('HH:mm') } else { $dt.ToString('dd.MM HH:mm') } }
function Fmt-At($dt) {
  $today = (Get-Date).Date
  if ($dt.Date -eq $today) { return 'сегодня в ' + $dt.ToString('HH:mm') }
  if ($dt.Date -eq $today.AddDays(1)) { return 'завтра в ' + $dt.ToString('HH:mm') }
  $dt.ToString('dd.MM') + ' в ' + $dt.ToString('HH:mm')
}
function Fmt-Until($dt) {
  $d = $dt - (Get-Date)
  if ($d.TotalMinutes -lt 1) { return 'меньше минуты' }
  if ($d.TotalDays -ge 1) { return '{0} д {1} ч' -f [int][math]::Floor($d.TotalDays), $d.Hours }
  if ($d.TotalHours -ge 1) { return '{0} ч {1:00} мин' -f [int][math]::Floor($d.TotalHours), $d.Minutes }
  '{0} мин' -f $d.Minutes
}
function Fmt-Ago($dt) {
  $s = ((Get-Date) - $dt).TotalSeconds
  if ($s -lt 10) { return 'только что' }
  if ($s -lt 60) { return ('{0} сек назад' -f [int]$s) }
  if ($s -lt 3600) { return ('{0} мин назад' -f [int]($s / 60)) }
  'в ' + (Fmt-Time $dt)
}
function Plural($n, $one, $few, $many) {
  $m10 = $n % 10; $m100 = $n % 100
  if ($m10 -eq 1 -and $m100 -ne 11) { return "$n $one" }
  if ($m10 -ge 2 -and $m10 -le 4 -and ($m100 -lt 12 -or $m100 -gt 14)) { return "$n $few" }
  "$n $many"
}

# ================= brushes / animation =================
function Col($hex) { [Windows.Media.ColorConverter]::ConvertFromString($hex) }
function Br($hex) { $b = New-Object Windows.Media.SolidColorBrush (Col $hex); $b.Freeze(); $b }
function Grad($a, $b, $angle = 0) { $g = New-Object Windows.Media.LinearGradientBrush (Col $a), (Col $b), $angle; $g.Freeze(); $g }
$BR = @{
  Text = Br '#F4F4F5'; Muted = Br '#8E8E96'; Faint = Br '#64646C'
  Green = Br '#4CD97B'; Orange = Br '#F0B44C'; Red = Br '#FF6B6F'; Gray = Br '#8E8E96'
  GreenBg = Br '#1C4CD97B'; OrangeBg = Br '#1EF0B44C'; RedBg = Br '#22FF6B6F'; GrayBg = Br '#22262630'
  RingGreen = Grad '#2FBF62' '#7BF0A2' 45; RingOrange = Grad '#E08E1E' '#FFCB6B' 45; RingRed = Grad '#E3393F' '#FF8A8D' 45; RingGray = Br '#3A3A44'
}
$GlowCol = @{ Green = Col '#3FD97A'; Orange = Col '#F0A83A'; Red = Col '#FF5A60'; Gray = Col '#000000' }

function Animate($target, $prop, $to, $ms = 220, $from = $null, $delay = 0) {
  $a = New-Object Windows.Media.Animation.DoubleAnimation
  $a.To = [double]$to
  if ($null -ne $from) { $a.From = [double]$from }
  $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms))
  $a.BeginTime = [TimeSpan]::FromMilliseconds($delay)
  $e = New-Object Windows.Media.Animation.CubicEase; $e.EasingMode = 'EaseOut'; $a.EasingFunction = $e
  $dp = switch ($prop) {
    'Opacity' { [Windows.UIElement]::OpacityProperty }
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
      <Border x:Name="H" Background="White" Opacity="0" CornerRadius="10"/>
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
  <Setter Property="Foreground" Value="#ECECEE"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
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
  <Setter Property="Background" Value="#1D1D22"/><Setter Property="BorderBrush" Value="#2E2E36"/><Setter Property="BorderThickness" Value="1"/>
</Style>
<Style x:Key="Icon" TargetType="Button" BasedOn="{StaticResource BtnBase}">
  <Setter Property="Foreground" Value="#8E8E96"/><Setter Property="FontFamily" Value="$IconFont"/><Setter Property="FontSize" Value="13"/>
  <Setter Property="Width" Value="36"/><Setter Property="Height" Value="36"/><Setter Property="Padding" Value="0"/>
  <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="#F4F4F5"/></Trigger></Style.Triggers>
</Style>
<Style x:Key="Chrome" TargetType="Button" BasedOn="{StaticResource Icon}">
  <Setter Property="Width" Value="42"/><Setter Property="Height" Value="34"/><Setter Property="FontSize" Value="10"/>
</Style>
<Style x:Key="ChromeClose" TargetType="Button" BasedOn="{StaticResource Chrome}">
  <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#E5484D"/><Setter Property="Foreground" Value="White"/></Trigger></Style.Triggers>
</Style>
<Style x:Key="Caption" TargetType="TextBlock">
  <Setter Property="FontSize" Value="11"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="#6A6A73"/>
</Style>
<Style x:Key="Input" TargetType="TextBox">
  <Setter Property="Foreground" Value="#F4F4F5"/><Setter Property="Background" Value="#141418"/><Setter Property="BorderBrush" Value="#2C2C34"/>
  <Setter Property="CaretBrush" Value="#F4F4F5"/><Setter Property="SelectionBrush" Value="#D97757"/><Setter Property="FontSize" Value="13"/><Setter Property="Height" Value="40"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="TextBox">
      <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="10">
        <Grid Margin="12,0">
          <TextBlock x:Name="Ph" Text="{TemplateBinding Tag}" Foreground="#55555E" VerticalAlignment="Center" Visibility="Collapsed" IsHitTestVisible="False" TextTrimming="CharacterEllipsis"/>
          <ScrollViewer x:Name="PART_ContentHost" VerticalAlignment="Center"/>
        </Grid>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="Text" Value=""><Setter TargetName="Ph" Property="Visibility" Value="Visible"/></Trigger>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#3C3C46"/></Trigger>
        <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#D97757"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="Toggle" TargetType="CheckBox">
  <Setter Property="Foreground" Value="#E6E6E9"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Focusable" Value="False"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="CheckBox">
      <StackPanel Orientation="Horizontal" Background="Transparent">
        <Grid Width="40" Height="22" VerticalAlignment="Center">
          <Border CornerRadius="11" Background="#30303A"/>
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
  <Setter Property="Foreground" Value="#9A9AA3"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Focusable" Value="False"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="RadioButton">
      <Border x:Name="B" CornerRadius="8" Padding="16,8" Background="Transparent"><ContentPresenter HorizontalAlignment="Center"/></Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#202027"/><Setter Property="Foreground" Value="#E6E6E9"/></Trigger>
        <Trigger Property="IsChecked" Value="True"><Setter TargetName="B" Property="Background" Value="#30303A"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
        <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="Swatch" TargetType="RadioButton">
  <Setter Property="Cursor" Value="Hand"/><Setter Property="Focusable" Value="False"/><Setter Property="Margin" Value="0,0,8,0"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="RadioButton">
      <Grid Width="34" Height="34" Background="Transparent">
        <Ellipse x:Name="Ring" Stroke="#F4F4F5" StrokeThickness="2" Opacity="0"/>
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
      <Border Background="#1F1F25" BorderBrush="#34343D" BorderThickness="1" CornerRadius="12" Padding="6"><StackPanel IsItemsHost="True"/></Border>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="DarkItem" TargetType="MenuItem">
  <Setter Property="Foreground" Value="#E6E6E9"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="MenuItem">
      <Border x:Name="B" Background="Transparent" CornerRadius="7" Padding="10,8"><ContentPresenter ContentSource="Header"/></Border>
      <ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="B" Property="Background" Value="#2D2D35"/></Trigger></ControlTemplate.Triggers>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
<Style x:Key="DarkSep" TargetType="Separator">
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Separator"><Border Height="1" Margin="8,5" Background="#2E2E36"/></ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType="ScrollBar">
  <Setter Property="Width" Value="8"/><Setter Property="MinWidth" Value="8"/>
  <Setter Property="Template"><Setter.Value>
    <ControlTemplate TargetType="ScrollBar">
      <Track x:Name="PART_Track" IsDirectionReversed="True">
        <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="#34343D"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
      </Track>
    </ControlTemplate>
  </Setter.Value></Setter>
</Style>
"@

$PulseTrigger = '<Ellipse.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True"><DoubleAnimation Storyboard.TargetProperty="Opacity" From="1" To="0.25" Duration="0:0:1.1"/></Storyboard></BeginStoryboard></EventTrigger></Ellipse.Triggers>'

$MainXaml = @"
<Window $NS Title="Claude Accounts" Width="1130" Height="830" MinWidth="640" MinHeight="560" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResize" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display" AllowDrop="True">
  <WindowChrome.WindowChrome><WindowChrome CaptionHeight="0" ResizeBorderThickness="14" GlassFrameThickness="0" CornerRadius="0"/></WindowChrome.WindowChrome>
  <Window.Resources>$Styles</Window.Resources>
  <Grid x:Name="Shell" Margin="16" Opacity="0" RenderTransformOrigin="0.5,0.5">
    <Grid.RenderTransform><ScaleTransform x:Name="ShellScale" ScaleX="0.97" ScaleY="0.97"/></Grid.RenderTransform>
    <Border CornerRadius="20" Background="#101013"><Border.Effect><DropShadowEffect BlurRadius="28" ShadowDepth="4" Opacity="0.6"/></Border.Effect></Border>
    <Border CornerRadius="20" BorderBrush="#25252C" BorderThickness="1">
      <Border.Background>
        <RadialGradientBrush Center="0.08,0" GradientOrigin="0.08,0" RadiusX="0.75" RadiusY="0.65">
          <GradientStop Color="#2B1C17" Offset="0"/><GradientStop Color="#101013" Offset="1"/>
        </RadialGradientBrush>
      </Border.Background>
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

        <Grid x:Name="TitleBar" Background="Transparent" Margin="28,22,14,0">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Border Width="46" Height="46" CornerRadius="13">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#F09A76" Offset="0"/><GradientStop Color="#C4533A" Offset="1"/></LinearGradientBrush></Border.Background>
              <Border.Effect><DropShadowEffect Color="#E07A55" BlurRadius="22" ShadowDepth="0" Opacity="0.55"/></Border.Effect>
              <TextBlock Text="&#x2733;" FontFamily="Segoe UI Symbol" FontSize="24" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,0,0,2"/>
            </Border>
            <StackPanel Margin="15,0,0,0" VerticalAlignment="Center">
              <TextBlock Text="Claude Accounts" FontSize="22" FontWeight="SemiBold" Foreground="#F4F4F5"/>
              <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
                <Ellipse Width="7" Height="7" Fill="#4CD97B" Margin="0,1,8,0" VerticalAlignment="Center">$PulseTrigger</Ellipse>
                <TextBlock x:Name="SubText" FontSize="12.5" Foreground="#8E8E96"/>
              </StackPanel>
            </StackPanel>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
            <StackPanel x:Name="Summary" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,4,14,0">
              <Border CornerRadius="9" Background="#1A1A1F" BorderBrush="#26262D" BorderThickness="1" Padding="10,5" Margin="0,0,6,0"><TextBlock x:Name="SumTotal" FontSize="12" Foreground="#C9C9CF"/></Border>
              <Border x:Name="SumOkB" CornerRadius="9" Background="#1C4CD97B" Padding="10,5" Margin="0,0,6,0"><StackPanel Orientation="Horizontal"><Ellipse Width="6" Height="6" Fill="#4CD97B" Margin="0,1,7,0" VerticalAlignment="Center"/><TextBlock x:Name="SumOk" FontSize="12" Foreground="#7BE8A0"/></StackPanel></Border>
              <Border x:Name="SumLimB" CornerRadius="9" Background="#22FF6B6F" Padding="10,5"><StackPanel Orientation="Horizontal"><Ellipse Width="6" Height="6" Fill="#FF6B6F" Margin="0,1,7,0" VerticalAlignment="Center"/><TextBlock x:Name="SumLim" FontSize="12" Foreground="#FF9A9D"/></StackPanel></Border>
            </StackPanel>
            <Button x:Name="BtnSettings" Style="{StaticResource Chrome}" Content="&#xE713;" FontSize="13" ToolTip="Настройки"/>
            <Button x:Name="BtnMin" Style="{StaticResource Chrome}" Content="&#xE921;" ToolTip="Свернуть"/>
            <Button x:Name="BtnClose" Style="{StaticResource ChromeClose}" Content="&#xE8BB;" ToolTip="Закрыть"/>
          </StackPanel>
        </Grid>

        <Border Grid.Row="1" Margin="28,22,28,0" CornerRadius="16" Background="#16161A" BorderBrush="#24242B" BorderThickness="1" Padding="16,14">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock Text="ПАПКА ПРОЕКТА" Style="{StaticResource Caption}" Margin="2,0,0,7"/>
              <TextBox x:Name="Folder" Style="{StaticResource Input}" Tag="Перетащи папку на окно или выбери через «Обзор»" AllowDrop="True"/>
            </StackPanel>
            <Button x:Name="BtnRecent" Grid.Column="1" Style="{StaticResource Ghost}" Width="42" Padding="0" Margin="8,0,0,0" VerticalAlignment="Bottom" ToolTip="Недавние папки">$(Ico '&#xE81C;' '' 14)</Button>
            <Button x:Name="BtnBrowse" Grid.Column="2" Style="{StaticResource Ghost}" Margin="8,0,0,0" VerticalAlignment="Bottom">$(Ico '&#xE8B7;' 'Обзор')</Button>
            <Button x:Name="BtnBest" Grid.Column="3" Style="{StaticResource Accent}" Margin="14,0,0,0" Padding="20,0" Height="40" VerticalAlignment="Bottom" ToolTip="Запустить аккаунт с самым большим запасом лимитов">$(Ico '&#xE945;' 'Запустить лучший' 13)</Button>
          </Grid>
        </Border>

        <ScrollViewer Grid.Row="2" Margin="28,20,14,0" Padding="0,0,14,0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <WrapPanel x:Name="Cards"/>
        </ScrollViewer>

        <Grid Grid.Row="3" Margin="28,6,28,18">
          <TextBlock x:Name="StatusText" FontSize="12" Foreground="#6A6A73" VerticalAlignment="Center"/>
          <Button x:Name="BtnRefresh" Style="{StaticResource Ghost}" Height="34" HorizontalAlignment="Right">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="$IconFont" FontSize="12" VerticalAlignment="Center" Margin="0,1,8,0" RenderTransformOrigin="0.5,0.5">
                <TextBlock.RenderTransform><RotateTransform x:Name="RefreshRot"/></TextBlock.RenderTransform>
              </TextBlock>
              <TextBlock Text="Обновить лимиты" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
        </Grid>

        <Border x:Name="Toast" Grid.RowSpan="4" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,70" CornerRadius="12"
                Background="#25252C" BorderBrush="#3A3A44" BorderThickness="1" Padding="16,11" Opacity="0" IsHitTestVisible="False">
          <Border.Effect><DropShadowEffect BlurRadius="20" ShadowDepth="3" Opacity="0.5"/></Border.Effect>
          <Border.RenderTransform><TranslateTransform x:Name="ToastY" Y="24"/></Border.RenderTransform>
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="ToastIcon" FontFamily="$IconFont" FontSize="14" VerticalAlignment="Center" Margin="0,0,11,0"/>
            <TextBlock x:Name="ToastText" Foreground="#F4F4F5" FontSize="13" VerticalAlignment="Center"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

function Gauge($p, $label) {
@"
<Grid Width="100" Height="100" Margin="0,0,14,0">
  <Ellipse Stroke="#22222A" StrokeThickness="10"/>
  <Path x:Name="${p}Arc" StrokeThickness="10" StrokeStartLineCap="Round" StrokeEndLineCap="Round">
    <Path.Effect><DropShadowEffect BlurRadius="16" ShadowDepth="0" Opacity="0.55"/></Path.Effect>
  </Path>
  <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
    <TextBlock HorizontalAlignment="Center" Foreground="#F4F4F5"><Run x:Name="${p}Num" FontSize="24" FontWeight="Bold"/><Run x:Name="${p}Unit" Text="%" FontSize="13" Foreground="#9A9AA3"/></TextBlock>
    <TextBlock Text="$label" FontSize="10.5" Foreground="#8E8E96" HorizontalAlignment="Center" Margin="0,-3,0,0"/>
  </StackPanel>
</Grid>
"@
}
function Chip($name, $glyph) {
  "<Border x:Name=`"${name}Chip`" CornerRadius=`"8`" Background=`"#1E1E24`" Padding=`"8,3,9,4`" Margin=`"0,0,6,6`"><StackPanel Orientation=`"Horizontal`"><TextBlock Text=`"$glyph`" FontFamily=`"$IconFont`" FontSize=`"11`" Foreground=`"#8E8E96`" VerticalAlignment=`"Center`" Margin=`"0,1,6,0`"/><TextBlock x:Name=`"${name}Text`" FontSize=`"11.5`" Foreground=`"#B4B4BC`" VerticalAlignment=`"Center`"/></StackPanel></Border>"
}

$CardXaml = @"
<Border $NS Width="500" Margin="0,0,16,16" Opacity="0">
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
    <Border CornerRadius="18" Background="#17171B" BorderBrush="#25252C" BorderThickness="1"/>
    <Border x:Name="Glow" CornerRadius="18" BorderThickness="1" Opacity="0"/>
    <Grid Margin="22,20,22,20">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border x:Name="Avatar" Width="50" Height="50" CornerRadius="15" VerticalAlignment="Center">
          <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="0" Opacity="0.45"/></Border.Effect>
          <TextBlock x:Name="Initial" Foreground="White" FontSize="20" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel Grid.Column="1" Margin="15,0,10,0" VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="AccName" FontSize="17" FontWeight="SemiBold" Foreground="#F4F4F5" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="250"/>
            <Border x:Name="PlanBadge" CornerRadius="6" Padding="7,1,7,2" Margin="9,1,0,0" VerticalAlignment="Center">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#3A2C26" Offset="0"/><GradientStop Color="#2A2A31" Offset="1"/></LinearGradientBrush></Border.Background>
              <TextBlock x:Name="Plan" FontSize="10" FontWeight="Bold" Foreground="#F3B79E"/>
            </Border>
          </StackPanel>
          <TextBlock x:Name="Email" FontSize="12.5" Foreground="#8E8E96" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
        <Button x:Name="More" Grid.Column="2" Style="{DynamicResource Icon}" Content="&#xE712;" VerticalAlignment="Top" ToolTip="Действия"/>
      </Grid>

      <WrapPanel Grid.Row="1" Margin="0,14,0,0">
        <Border x:Name="StatusPill" CornerRadius="8" Padding="8,3,9,4" Margin="0,0,6,6">
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="StatusDot" Width="6" Height="6" Margin="0,1,7,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="Status" FontSize="11.5" FontWeight="SemiBold" VerticalAlignment="Center"/>
          </StackPanel>
        </Border>
        <Border x:Name="BestBadge" CornerRadius="8" Padding="8,3,9,4" Margin="0,0,6,6" Visibility="Collapsed">
          <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#3AD97757" Offset="0"/><GradientStop Color="#1AD97757" Offset="1"/></LinearGradientBrush></Border.Background>
          <TextBlock Text="&#x2605; лучший выбор" FontSize="11.5" FontWeight="SemiBold" Foreground="#F6B096"/>
        </Border>
        $(Chip 'Proxy' '&#xE774;')
        $(Chip 'Full' '&#xE8D7;')
        $(Chip 'Args' '&#xE756;')
      </WrapPanel>

      <Grid Grid.Row="2" Margin="0,10,0,0" Height="104">
        <Grid x:Name="Usage">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          $(Gauge 'Five' '5 часов')
          <Grid Grid.Column="1">$(Gauge 'Week' 'неделя')</Grid>
          <StackPanel Grid.Column="2" VerticalAlignment="Center" Margin="6,0,0,0">
            <TextBlock Text="СБРОС 5 ЧАСОВ" Style="{DynamicResource Caption}"/>
            <TextBlock x:Name="FiveIn" FontSize="14" FontWeight="SemiBold" Foreground="#E6E6E9" Margin="0,3,0,0"/>
            <TextBlock x:Name="FiveAt" FontSize="11.5" Foreground="#7A7A83"/>
            <TextBlock Text="СБРОС НЕДЕЛИ" Style="{DynamicResource Caption}" Margin="0,10,0,0"/>
            <TextBlock x:Name="WeekIn" FontSize="14" FontWeight="SemiBold" Foreground="#E6E6E9" Margin="0,3,0,0"/>
            <TextBlock x:Name="WeekAt" FontSize="11.5" Foreground="#7A7A83"/>
          </StackPanel>
        </Grid>
        <Border x:Name="NoLogin" CornerRadius="14" Background="#121216" BorderBrush="#24242B" BorderThickness="1" Padding="18,0" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Border Width="44" Height="44" CornerRadius="22" Background="#1E1E24"><TextBlock Text="&#xE77B;" FontFamily="$IconFont" FontSize="17" Foreground="#9A9AA3" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
            <StackPanel Margin="14,0,0,0" VerticalAlignment="Center">
              <TextBlock x:Name="NoLoginTitle" Text="Вход не выполнен" FontSize="14" FontWeight="SemiBold" Foreground="#E6E6E9"/>
              <TextBlock x:Name="NoLoginText" Text="Нажми «Войти» — откроется Claude, залогинься в нужный аккаунт." FontSize="12" Foreground="#7A7A83" Margin="0,3,0,0" TextWrapping="Wrap" MaxWidth="330"/>
            </StackPanel>
          </StackPanel>
        </Border>
      </Grid>

      <StackPanel Grid.Row="3" Margin="0,16,0,0">
        <StackPanel Orientation="Horizontal" Margin="2,0,0,11">
          <Ellipse x:Name="SrcDot" Width="6" Height="6" Margin="0,1,8,0" VerticalAlignment="Center">$PulseTrigger</Ellipse>
          <TextBlock x:Name="Src" FontSize="11.5" Foreground="#6A6A73" TextTrimming="CharacterEllipsis" MaxWidth="430"/>
        </StackPanel>
        <Button x:Name="Run" Style="{DynamicResource Accent}" Height="46" FontSize="14">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="RunIcon" Text="&#xE768;" FontFamily="$IconFont" FontSize="13" VerticalAlignment="Center" Margin="0,1,10,0"/>
            <TextBlock x:Name="RunText" Text="Запустить" VerticalAlignment="Center"/>
          </StackPanel>
        </Button>
      </StackPanel>
    </Grid>
  </Grid>
</Border>
"@

$AddTileXaml = @"
<Border $NS Width="500" Margin="0,0,16,16" Cursor="Hand" Background="Transparent" Opacity="0">
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
    <Rectangle RadiusX="18" RadiusY="18" Stroke="#33333C" StrokeThickness="1.5" StrokeDashArray="6 4"/>
    <Border x:Name="HoverBg" CornerRadius="18" Opacity="0">
      <Border.Background><RadialGradientBrush><GradientStop Color="#22D97757" Offset="0"/><GradientStop Color="#08D97757" Offset="1"/></RadialGradientBrush></Border.Background>
    </Border>
    <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
      <Border Width="58" Height="58" CornerRadius="29" HorizontalAlignment="Center" RenderTransformOrigin="0.5,0.5">
        <Border.RenderTransform><ScaleTransform x:Name="PlusScale"/></Border.RenderTransform>
        <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#2A2025" Offset="0"/><GradientStop Color="#1E1E24" Offset="1"/></LinearGradientBrush></Border.Background>
        <TextBlock Text="&#xE710;" FontFamily="$IconFont" FontSize="20" Foreground="#EE916C" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <TextBlock Text="Добавить аккаунт" FontSize="16" FontWeight="SemiBold" Foreground="#E6E6E9" Margin="0,14,0,0" HorizontalAlignment="Center"/>
      <TextBlock Text="Название, свой прокси с проверкой, настройки запуска" FontSize="12" Foreground="#75757E" Margin="0,5,0,0" HorizontalAlignment="Center"/>
    </StackPanel>
  </Grid>
</Border>
"@

function Dialog-Shell($width, $body) {
@"
<Window $NS WindowStyle="None" AllowsTransparency="True" Background="Transparent" SizeToContent="Height" Width="$width"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False" ResizeMode="NoResize" FontFamily="Segoe UI" TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>$Styles</Window.Resources>
  <Grid x:Name="Root" Margin="22" Opacity="0" RenderTransformOrigin="0.5,0.5">
    <Grid.RenderTransform><ScaleTransform x:Name="Sc" ScaleX="0.95" ScaleY="0.95"/></Grid.RenderTransform>
    <Border CornerRadius="18" Background="#17171B"><Border.Effect><DropShadowEffect BlurRadius="32" ShadowDepth="5" Opacity="0.65"/></Border.Effect></Border>
    <Border CornerRadius="18" BorderBrush="#30303A" BorderThickness="1" Padding="28,24,28,24">
      <Border.Background>
        <RadialGradientBrush Center="0,0" GradientOrigin="0,0" RadiusX="0.9" RadiusY="0.6"><GradientStop Color="#231A17" Offset="0"/><GradientStop Color="#17171B" Offset="1"/></RadialGradientBrush>
      </Border.Background>
      <StackPanel>
        <Grid x:Name="Drag" Background="Transparent">
          <StackPanel Margin="0,0,40,0">
            <TextBlock x:Name="Title" FontSize="21" FontWeight="SemiBold" Foreground="#F4F4F5"/>
            <TextBlock x:Name="Sub" FontSize="12.5" Foreground="#8E8E96" Margin="0,5,0,0" TextWrapping="Wrap"/>
          </StackPanel>
          <Button x:Name="X" Style="{StaticResource Icon}" Content="&#xE8BB;" FontSize="10" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-6,-12,0"/>
        </Grid>
        $body
      </StackPanel>
    </Border>
  </Grid>
</Window>
"@
}

$AccBody = @"
<TextBlock Text="НАЗВАНИЕ" Style="{StaticResource Caption}" Margin="0,24,0,8"/>
<TextBox x:Name="AName" Style="{StaticResource Input}" Tag="Например: Основной, Рабочий, Max #2"/>
<TextBlock Text="ЦВЕТ" Style="{StaticResource Caption}" Margin="0,18,0,6"/>
<StackPanel x:Name="Swatches" Orientation="Horizontal" Margin="-5,0,0,0"/>

<TextBlock Text="ПРОКСИ" Style="{StaticResource Caption}" Margin="0,18,0,8"/>
<Border Background="#111114" CornerRadius="11" Padding="3" HorizontalAlignment="Left" BorderBrush="#24242B" BorderThickness="1">
  <StackPanel Orientation="Horizontal">
    <RadioButton x:Name="PxNone" GroupName="px" Style="{StaticResource Seg}" Content="Без прокси"/>
    <RadioButton x:Name="PxOn" GroupName="px" Style="{StaticResource Seg}" Content="Через прокси"/>
  </StackPanel>
</Border>
<StackPanel x:Name="PxPanel" Margin="0,10,0,0">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <TextBox x:Name="Proxy" Style="{StaticResource Input}" Tag="host:port:логин:пароль  или  http://логин:пароль@host:port"/>
    <Button x:Name="Check" Grid.Column="1" Style="{StaticResource Ghost}" Margin="8,0,0,0" MinWidth="128">$(Ico '&#xE73E;' 'Проверить')</Button>
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
<TextBlock x:Name="PxNoneHint" Text="Claude будет подключаться напрямую, без прокси." FontSize="12" Foreground="#6A6A73" Margin="2,9,0,0"/>

<TextBlock Text="ЗАПУСК" Style="{StaticResource Caption}" Margin="0,22,0,10"/>
<CheckBox x:Name="Full" Style="{StaticResource Toggle}" Content="Полный доступ — Claude не спрашивает подтверждений"/>
<TextBlock Text="Дополнительные аргументы claude" FontSize="12" Foreground="#8E8E96" Margin="0,14,0,7"/>
<TextBox x:Name="Args" Style="{StaticResource Input}" Tag="необязательно, например: --model opus"/>

<StackPanel x:Name="DirRow" Margin="0,16,0,0">
  <TextBlock Text="Папка с логином" FontSize="12" Foreground="#8E8E96" Margin="0,0,0,5"/>
  <Grid>
    <TextBlock x:Name="Dir" FontSize="12.5" Foreground="#B4B4BC" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,44,0"/>
    <Button x:Name="OpenDir" Style="{StaticResource Icon}" Content="&#xE8B7;" HorizontalAlignment="Right" ToolTip="Открыть папку"/>
  </Grid>
</StackPanel>

<Grid Margin="0,26,0,0">
  <TextBlock x:Name="Hint" Foreground="#F0B44C" FontSize="12" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,270,0"/>
  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
    <Button x:Name="Cancel" Content="Отмена" Style="{StaticResource Ghost}" Width="110" Margin="0,0,10,0" IsCancel="True"/>
    <Button x:Name="Ok" Style="{StaticResource Accent}" MinWidth="150"/>
  </StackPanel>
</Grid>
"@

$SetBody = @"
<TextBlock Text="ОБНОВЛЕНИЕ ЛИМИТОВ" Style="{StaticResource Caption}" Margin="0,24,0,8"/>
<Border Background="#111114" CornerRadius="11" Padding="3" HorizontalAlignment="Left" BorderBrush="#24242B" BorderThickness="1">
  <StackPanel x:Name="Intervals" Orientation="Horizontal"/>
</Border>
<TextBlock Text="ТЕРМИНАЛ" Style="{StaticResource Caption}" Margin="0,20,0,8"/>
<Border Background="#111114" CornerRadius="11" Padding="3" HorizontalAlignment="Left" BorderBrush="#24242B" BorderThickness="1">
  <StackPanel Orientation="Horizontal">
    <RadioButton x:Name="TCmd" GroupName="term" Style="{StaticResource Seg}" Content="Командная строка"/>
    <RadioButton x:Name="TWt" GroupName="term" Style="{StaticResource Seg}" Content="Windows Terminal"/>
  </StackPanel>
</Border>
<TextBlock Text="ПОВЕДЕНИЕ" Style="{StaticResource Caption}" Margin="0,20,0,10"/>
<CheckBox x:Name="MinLaunch" Style="{StaticResource Toggle}" Content="Сворачивать окно после запуска Claude"/>
<TextBlock Text="ИНСТРУМЕНТЫ" Style="{StaticResource Caption}" Margin="0,22,0,8"/>
<WrapPanel>
  <Button x:Name="Sync" Style="{StaticResource Ghost}" Margin="0,0,8,8">$(Ico '&#xE895;' 'Синхронизировать настройки Claude')</Button>
  <Button x:Name="OpenCfg" Style="{StaticResource Ghost}" Margin="0,0,8,8">$(Ico '&#xE8A5;' 'Файл конфигурации')</Button>
</WrapPanel>
<TextBlock Text="Синхронизация копирует settings.json, skills и плагины из первого аккаунта во все остальные. Логины не затрагиваются." FontSize="11.5" Foreground="#6A6A73" TextWrapping="Wrap" Margin="0,2,0,0"/>
<StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,24,0,0">
  <Button x:Name="Cancel" Content="Отмена" Style="{StaticResource Ghost}" Width="110" Margin="0,0,10,0" IsCancel="True"/>
  <Button x:Name="Ok" Content="Сохранить" Style="{StaticResource Accent}" MinWidth="130"/>
</StackPanel>
"@

$ConfirmBody = @"
<StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,24,0,0">
  <Button x:Name="Cancel" Content="Отмена" Style="{StaticResource Ghost}" Width="110" Margin="0,0,10,0" IsCancel="True"/>
  <Button x:Name="Ok" MinWidth="130" IsDefault="True"/>
</StackPanel>
"@

# ================= dialogs =================
function Open-Dialog($xaml, $names) {
  $d = [Windows.Markup.XamlReader]::Parse($xaml)
  $d.Owner = $win
  if ($IconPath -and $win.Icon) { $d.Icon = $win.Icon }
  $f = @{ D = $d }
  foreach ($n in @('Root', 'Sc', 'Drag', 'Title', 'Sub', 'X') + $names) { $f[$n] = $d.FindName($n) }
  $f.Drag.Add_MouseLeftButtonDown({ param($s, $e) try { [Windows.Window]::GetWindow($s).DragMove() } catch {} })
  $f.X.Add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).Close() })
  $d.Add_Loaded({ param($s, $e)
    $r = $s.FindName('Root'); $sc = $s.FindName('Sc')
    Animate $r 'Opacity' 1 200 0; Animate $sc 'ScaleX' 1 280 0.95; Animate $sc 'ScaleY' 1 280 0.95 })
  $f
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
  if (-not $f.AName.Text.Trim()) { $ok = $false; $hint = 'Укажи название аккаунта' }
  elseif ($f.PxOn.IsChecked) {
    $n = Normalize-Proxy $f.Proxy.Text
    if (-not $n.Ok) { $ok = $false; $hint = $n.Err }
    elseif ($f.S.Busy) { $ok = $false; $hint = 'Идёт проверка прокси…' }
    elseif ($f.S.FailedUrl -eq $n.Url) { $ok = $false; $hint = 'Прокси не работает — исправь данные или выбери «Без прокси»' }
    elseif ($f.S.CheckedUrl -ne $n.Url) { $ok = $false; $hint = 'Нажми «Проверить» — без рабочего прокси аккаунт не сохранить' }
  }
  $f.Ok.IsEnabled = $ok; $f.Hint.Text = $hint
}

function Run-ProxyCheck($f) {
  $n = Normalize-Proxy $f.Proxy.Text
  if (-not $n.Ok) { Set-PxStatus $f 'err' $n.Err; return }
  $f.S.Busy = $true; $f.Check.IsEnabled = $false
  Set-PxStatus $f 'busy' ('Проверяю соединение через ' + (Proxy-Display $n.Url) + '…')
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
      Set-PxStatus $f 'ok' ("Прокси работает · {0} мс{1}" -f $r.Ms, $loc)
    } else {
      $f.S.CheckedUrl = $null; $f.S.FailedUrl = $c.Url
      Set-PxStatus $f 'err' $r.Err
    }
    Validate-AccDialog $f
  }
}

function Show-AccountDialog($acc) {
  $isNew = -not $acc
  $f = Open-Dialog (Dialog-Shell 600 $AccBody) @('AName', 'Swatches', 'PxNone', 'PxOn', 'PxPanel', 'Proxy', 'Check', 'PxStatus', 'PxIcon', 'PxRot', 'PxText', 'PxNoneHint', 'Full', 'Args', 'DirRow', 'Dir', 'OpenDir', 'Hint', 'Cancel', 'Ok')
  $f.S = @{ Busy = $false; CheckedUrl = $null; Color = 0 }
  if ($isNew) {
    $f.Title.Text = 'Новый аккаунт'
    $f.Sub.Text = 'Логин аккаунта хранится в отдельной папке. Если указан прокси — он проверяется до добавления, через него же идут Claude и запрос лимитов.'
    $f.Ok.Content = 'Добавить аккаунт'
    $f.AName.Text = 'Account ' + ($script:cfg.accounts.Count + 1)
    $f.S.Color = $script:cfg.accounts.Count % $Palette.Count
    $f.Full.IsChecked = $true
    $f.PxNone.IsChecked = $true
    $f.DirRow.Visibility = 'Collapsed'
  } else {
    $f.Title.Text = 'Настройки аккаунта'
    $f.Sub.Text = 'Изменения применятся при следующем запуске Claude на этом аккаунте.'
    $f.Ok.Content = 'Сохранить'
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
    $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(5); $t.Tag = $f.D
    $t.Add_Tick({ param($s, $e) $s.Stop(); Save-Shot $s.Tag $env:CA_SHOT_DIALOG; $s.Tag.Close() }); $t.Start()
  }

  if (-not $f.D.ShowDialog()) { return $null }
  $proxy = if ($f.PxOn.IsChecked) { (Normalize-Proxy $f.Proxy.Text).Url } else { '' }
  @{ name = $f.AName.Text.Trim(); color = $f.S.Color; proxy = $proxy; fullAccess = [bool]$f.Full.IsChecked; args = $f.Args.Text.Trim() }
}

function Show-Settings {
  $f = Open-Dialog (Dialog-Shell 560 $SetBody) @('Intervals', 'TCmd', 'TWt', 'MinLaunch', 'Sync', 'OpenCfg', 'Cancel', 'Ok')
  $f.Title.Text = 'Настройки'
  $f.Sub.Text = 'Общие параметры приложения. Прокси, цвет и параметры запуска задаются у каждого аккаунта через «⋯ → Настройки аккаунта».'
  $f.S = @{ Interval = $script:cfg.refreshSec }
  foreach ($opt in @(@(30, '30 сек'), @(60, '1 мин'), @(120, '2 мин'), @(300, '5 мин'))) {
    $rb = New-Object Windows.Controls.RadioButton
    $rb.Style = $f.D.Resources['Seg']; $rb.GroupName = 'iv'; $rb.Content = $opt[1]; $rb.Tag = @{ V = $opt[0]; F = $f }
    $rb.IsChecked = ($opt[0] -eq $script:cfg.refreshSec)
    $rb.Add_Checked({ param($s, $e) $s.Tag.F.S.Interval = $s.Tag.V })
    [void]$f.Intervals.Children.Add($rb)
  }
  if (-not $HasWt) { $f.TWt.IsEnabled = $false; $f.TWt.ToolTip = 'Windows Terminal не установлен' }
  if ($script:cfg.terminal -eq 'wt' -and $HasWt) { $f.TWt.IsChecked = $true } else { $f.TCmd.IsChecked = $true }
  $f.MinLaunch.IsChecked = [bool]$script:cfg.minimizeOnLaunch
  $f.Sync.Add_Click({ Sync-Settings })
  $f.OpenCfg.Add_Click({ Start-Process notepad.exe $CfgPath })
  $f.Ok.Add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).DialogResult = $true })
  if (-not $f.D.ShowDialog()) { return }
  $script:cfg.refreshSec = [int]$f.S.Interval
  $script:cfg.terminal = if ($f.TWt.IsChecked) { 'wt' } else { 'cmd' }
  $script:cfg.minimizeOnLaunch = [bool]$f.MinLaunch.IsChecked
  Save-Cfg; Update-All
  Show-Toast 'Настройки сохранены' 'ok'
}

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
  Show-Toast "Аккаунт «$($r.name)» добавлен — нажми «Войти» на его карточке" 'ok'
}

function Edit-Account($st) {
  $r = Show-AccountDialog $st.Acc
  if (-not $r) { return }
  foreach ($k in 'name', 'color', 'proxy', 'fullAccess', 'args') { $st.Acc[$k] = $r[$k] }
  Save-Cfg; Build-Cards; Refresh-All
  Show-Toast 'Настройки аккаунта сохранены' 'ok'
}

function Sync-Settings {
  if ($script:cfg.accounts.Count -lt 2) { [void](Show-Confirm 'Синхронизация' 'Нужно хотя бы два аккаунта.' 'Понятно' -Info); return }
  $src = $script:cfg.accounts[0]
  if (-not (Show-Confirm 'Синхронизировать настройки?' "settings.json, skills и плагины из «$($src.name)» будут скопированы во все остальные аккаунты. Логины не затрагиваются." 'Синхронизировать')) { return }
  foreach ($a in $script:cfg.accounts | Select-Object -Skip 1) { Copy-Settings $src.dir $a.dir }
  Show-Toast 'Настройки синхронизированы' 'ok'
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
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { [void](Show-Confirm 'Claude не найден' 'Команда claude не найдена в PATH. Установи Claude Code CLI.' 'Понятно' -Info); return }
  $folder = Get-Folder
  if (-not $folder) { Show-Toast ('Папка не найдена: ' + $tbFolder.Text) 'err'; return }
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
  $verb = if ($st.LoggedIn) { 'Запущен' } else { 'Открыт вход в' }
  Show-Toast "$verb «$($acc.name)» · $(Split-Path $folder -Leaf)" 'ok'
  if ($script:cfg.minimizeOnLaunch) { $win.WindowState = 'Minimized' }
}

function Start-Best {
  $ready = @($script:States | Where-Object { $null -ne $_.Score -and $_.Score -lt 100 } | Sort-Object { $_.Score })
  if ($ready.Count) { Start-Claude $ready[0]; return }
  $logged = @($script:States | Where-Object { $_.LoggedIn })
  if (-not $logged.Count) { Show-Toast 'Нет залогиненных аккаунтов — нажми «Войти» на карточке' 'err'; return }
  $next = $null; $nextSt = $null
  foreach ($st in $logged) {
    $eff = Get-Effective $st; if (-not $eff) { continue }
    foreach ($l in @($eff.Data.Five, $eff.Data.Week)) { if ($l -and $l.Reset -and $l.Pct -ge 100 -and (-not $next -or $l.Reset -lt $next)) { $next = $l.Reset; $nextSt = $st } }
  }
  if ($nextSt) { Show-Toast "Все аккаунты в лимите. Ближе всего «$($nextSt.Acc.name)» — через $(Fmt-Until $next)" 'err' }
  else { Start-Claude $logged[0] }
}

function Logout-Account($st) {
  $warn = if (Is-DefaultDir $st.Acc.dir) { ' Это основной логин Claude Code на компьютере.' } else { '' }
  if (-not (Show-Confirm "Выйти из «$($st.Acc.name)»?" "Логин будет удалён из этой папки, настройки останутся. Потом можно нажать «Войти» и залогиниться в другой аккаунт.$warn" 'Выйти' -Danger)) { return }
  Remove-Item -LiteralPath (Join-Path $st.Acc.dir '.credentials.json') -Force -ErrorAction SilentlyContinue
  $st.Live = $null; $st.LiveAt = $null
  Refresh-All
  Show-Toast "Вы вышли из «$($st.Acc.name)»" 'ok'
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
  if ($script:cfg.accounts.Count -le 1) { Show-Toast 'Должен остаться хотя бы один аккаунт' 'err'; return }
  if (-not (Show-Confirm "Убрать «$($st.Acc.name)»?" "Аккаунт исчезнет из списка. Папка $($st.Acc.dir) с логином останется на диске — её можно удалить вручную." 'Убрать' -Danger)) { return }
  $script:cfg.accounts = @($script:cfg.accounts | Where-Object { -not [object]::ReferenceEquals($_, $st.Acc) })
  Save-Cfg; Build-Cards; Update-All
}

function New-Menu($items) {
  $m = New-Object Windows.Controls.ContextMenu
  $m.Style = $win.Resources['DarkMenu']
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
    @{ Icon = [string][char]0xE713; Text = 'Настройки аккаунта…'; Tag = $st; Click = { param($s, $e) Edit-Account $s.Tag } }
    @{ Icon = [string][char]0xE72C; Text = 'Обновить лимиты'; Tag = $st; Click = { param($s, $e) Read-Local $s.Tag; Start-Fetch $s.Tag; Update-All; Update-Spinner } }
    @{ Icon = [string][char]0xE8B7; Text = 'Открыть папку с логином'; Tag = $st; Click = { param($s, $e) Start-Process explorer.exe $s.Tag.Acc.dir } }
    '-'
    @{ Icon = [string][char]0xE70E; Text = 'Переместить выше'; Tag = $st; Click = { param($s, $e) Move-Account $s.Tag -1 } }
    @{ Icon = [string][char]0xE70D; Text = 'Переместить ниже'; Tag = $st; Click = { param($s, $e) Move-Account $s.Tag 1 } }
    '-'
    @{ Icon = [string][char]0xE7E8; Text = 'Выйти из аккаунта'; Tag = $st; Click = { param($s, $e) Logout-Account $s.Tag } }
    @{ Icon = [string][char]0xE74D; Text = 'Убрать из списка'; Tag = $st; Color = $BR.Red; Click = { param($s, $e) Remove-Account $s.Tag } }
  )
  $menu.PlacementTarget = $btn; $menu.Placement = 'Bottom'; $menu.HorizontalOffset = -190; $menu.IsOpen = $true
}

# ================= cards / gauges =================
$script:States = @()
$CardParts = 'Glow', 'Lift', 'Avatar', 'Initial', 'AccName', 'PlanBadge', 'Plan', 'Email', 'More', 'StatusPill', 'StatusDot', 'Status', 'BestBadge',
             'ProxyChip', 'ProxyText', 'FullChip', 'FullText', 'ArgsChip', 'ArgsText', 'Usage', 'NoLogin', 'NoLoginTitle', 'NoLoginText', 'SrcDot', 'Src', 'Run', 'RunIcon', 'RunText',
             'FiveArc', 'FiveNum', 'FiveUnit', 'FiveIn', 'FiveAt', 'WeekArc', 'WeekNum', 'WeekUnit', 'WeekIn', 'WeekAt'

function Build-Cards {
  $cardsPanel.Children.Clear()
  $old = @{}; foreach ($st in $script:States) { $old[$st.Acc.dir] = $st }
  $script:States = @()
  $idx = 0
  foreach ($a in $script:cfg.accounts) {
    $card = [Windows.Markup.XamlReader]::Parse($CardXaml)
    $ui = @{}; foreach ($n in $CardParts) { $ui[$n] = $card.FindName($n) }
    $st = @{ Acc = $a; Ui = $ui; Card = $card; Live = $null; LiveAt = $null; Cache = $null; CacheAt = $null; Err = $null; Fetching = $false
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
    $ui.Run.Tag = $st; $ui.Run.Add_Click({ param($s, $e) Start-Claude $s.Tag })
    $ui.More.Tag = $st; $ui.More.Add_Click({ param($s, $e) Show-AccMenu $s $s.Tag })
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
  if ($script:States.Count) {
    $first = $script:States[0].Card
    $first.Add_SizeChanged({ param($s, $e) $tile.Height = $s.ActualHeight }.GetNewClosure())
  }
  foreach ($st in $script:States) { Update-Card $st; foreach ($p in 'Five', 'Week') { Draw-Gauge $st $p } }
  $script:AnimTimer.Start()
}

function Draw-Gauge($st, $p) {
  $g = $st.G[$p]; $ui = $st.Ui
  $path = $ui["${p}Arc"]
  $size = 100; $t = 10; $r = ($size - $t) / 2; $c = $size / 2
  $pct = [math]::Max(0, [math]::Min(100, $g.Cur))
  if ($pct -lt 0.4) { $path.Data = $null }
  else {
    $a = [math]::Min($pct, 99.95) / 100 * 2 * [math]::PI
    $fig = New-Object Windows.Media.PathFigure
    $fig.StartPoint = New-Object Windows.Point($c, ($c - $r))
    $end = New-Object Windows.Point(($c + $r * [math]::Sin($a)), ($c - $r * [math]::Cos($a)))
    $seg = New-Object Windows.Media.ArcSegment($end, (New-Object Windows.Size($r, $r)), 0.0, ($a -gt [math]::PI), [Windows.Media.SweepDirection]::Clockwise, $true)
    [void]$fig.Segments.Add($seg)
    $geo = New-Object Windows.Media.PathGeometry; [void]$geo.Figures.Add($fig)
    $path.Data = $geo
  }
  $path.Stroke = $BR["Ring$($g.Kind)"]
  $path.Effect.Color = $GlowCol[$g.Kind]
  $path.Effect.Opacity = if ($g.Kind -eq 'Gray') { 0 } else { 0.55 }
  if ($g.NoData) { $ui["${p}Num"].Text = '—'; $ui["${p}Unit"].Text = '' }
  else { $ui["${p}Num"].Text = [string][int][math]::Round($g.Cur); $ui["${p}Unit"].Text = '%' }
}

function Set-Gauge($st, $p, $lim) {
  $g = $st.G[$p]
  if (-not $lim) { $g.NoData = $true; $g.Target = 0.0; $g.Kind = 'Gray' }
  else {
    $v = [double](Eff-Pct $lim)
    $g.NoData = $false; $g.Target = $v
    $g.Kind = if ($v -ge 90) { 'Red' } elseif ($v -ge 70) { 'Orange' } else { 'Green' }
  }
  if ([math]::Abs($g.Cur - $g.Target) -gt 0.01) { $script:AnimTimer.Start() } else { Draw-Gauge $st $p }
  $in = $st.Ui["${p}In"]; $at = $st.Ui["${p}At"]
  if (-not $lim -or -not $lim.Reset) { $in.Text = '—'; $at.Text = '' }
  elseif ($lim.Reset -lt (Get-Date)) { $in.Text = 'уже сброшено'; $at.Text = '' }
  else { $in.Text = 'через ' + (Fmt-Until $lim.Reset); $at.Text = Fmt-At $lim.Reset }
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

function Set-Status($ui, $text, $fg, $bg) { $ui.Status.Text = $text; $ui.Status.Foreground = $fg; $ui.StatusDot.Fill = $fg; $ui.StatusPill.Background = $bg }

function Update-Card($st) {
  $ui = $st.Ui; $a = $st.Acc
  $ui.AccName.Text = $a.name
  $ui.Initial.Text = if ($a.name -match '(\d+)\s*$') { $matches[1] } elseif ($a.name) { $a.name.Substring(0, 1).ToUpper() } else { '?' }
  if ($st.Plan) { $ui.Plan.Text = ([string]$st.Plan).ToUpper(); $ui.PlanBadge.Visibility = 'Visible' } else { $ui.PlanBadge.Visibility = 'Collapsed' }
  $ui.ProxyText.Text = Proxy-Display $a.proxy
  if ($env:CA_DEMO -and $a.proxy) { $ui.ProxyText.Text = 'proxy.example.com:8080' }
  $ui.FullChip.Visibility = if ($a.fullAccess) { 'Visible' } else { 'Collapsed' }; $ui.FullText.Text = 'полный доступ'
  $ui.ArgsChip.Visibility = if ($a.args) { 'Visible' } else { 'Collapsed' }; $ui.ArgsText.Text = $a.args
  $ui.BestBadge.Visibility = 'Collapsed'
  $st.Score = $null

  if (-not $st.LoggedIn) {
    $ui.Email.Text = 'не авторизован'
    $ui.Usage.Visibility = 'Collapsed'; $ui.NoLogin.Visibility = 'Visible'
    Set-Status $ui 'Нет входа' $BR.Gray $BR.GrayBg
    $ui.SrcDot.Visibility = 'Collapsed'; $ui.Src.Text = 'Лимиты появятся после входа'
    $ui.RunText.Text = 'Войти в аккаунт'; $ui.RunIcon.Text = [string][char]0xE77B
    return
  }
  $ui.RunText.Text = 'Запустить'; $ui.RunIcon.Text = [string][char]0xE768
  $ui.Email.Text = if ($st.Email) { $st.Email } else { 'вход выполнен' }
  if ($env:CA_DEMO) { $ui.Email.Text = 'you@example.com' }
  $ui.NoLogin.Visibility = 'Collapsed'; $ui.Usage.Visibility = 'Visible'
  $eff = Get-Effective $st
  if ($eff) {
    Set-Gauge $st 'Five' $eff.Data.Five
    Set-Gauge $st 'Week' $eff.Data.Week
    $mx = [math]::Max((Eff-Pct $eff.Data.Five), (Eff-Pct $eff.Data.Week))
    $st.Score = $mx
    if ($mx -ge 100) { Set-Status $ui 'Лимит исчерпан' $BR.Red $BR.RedBg }
    elseif ($mx -ge 80) { Set-Status $ui 'Почти лимит' $BR.Orange $BR.OrangeBg }
    else { Set-Status $ui 'Доступен' $BR.Green $BR.GreenBg }
    if ($st.WasLimited -and $mx -lt 100) { Show-Toast "«$($a.name)» снова доступен — лимит сбросился" 'ok' }
    $st.WasLimited = ($mx -ge 100)
  } else {
    Set-Gauge $st 'Five' $null; Set-Gauge $st 'Week' $null
    Set-Status $ui 'Вход выполнен' $BR.Gray $BR.GrayBg
  }

  $ui.SrcDot.Visibility = 'Visible'
  if ($eff -and $eff.Src -eq 'live' -and -not $st.Err) {
    $ui.SrcDot.Fill = $BR.Green; $ui.Src.Foreground = $BR.Muted
    $ui.Src.Text = 'Live · обновлено ' + (Fmt-Ago $eff.At)
  } elseif ($st.Fetching -and -not $eff) {
    $ui.SrcDot.Fill = $BR.Orange; $ui.Src.Foreground = $BR.Muted; $ui.Src.Text = 'Загружаю лимиты…'
  } else {
    $ui.SrcDot.Fill = $BR.Faint; $ui.Src.Foreground = $BR.Faint
    $base = 'Нет данных'
    if ($eff) { $base = $(if ($eff.Src -eq 'live') { 'Live' } else { 'Из кэша' }) + ' · ' + (Fmt-Ago $eff.At) }
    $why = ''
    if ($st.TokenExpired -or $st.Err -eq 'token') { $why = ' · токен истёк — запусти аккаунт, чтобы включить live' }
    elseif ($st.Err -eq 'rate') { $why = ' · сервер просит подождать' }
    elseif ($st.Err -eq 'net') { $why = ' · нет связи' + $(if ($a.proxy) { ' (проверь прокси)' } else { '' }) }
    $ui.Src.Text = $base + $why
  }
}

function Update-All {
  foreach ($st in $script:States) { Update-Card $st }
  $cand = @($script:States | Where-Object { $null -ne $_.Score -and $_.Score -lt 100 } | Sort-Object { $_.Score })
  if ($cand.Count -ge 2) { $cand[0].Ui.BestBadge.Visibility = 'Visible' }
  $n = $script:States.Count
  $okN = @($script:States | Where-Object { $null -ne $_.Score -and $_.Score -lt 100 }).Count
  $limN = @($script:States | Where-Object { $null -ne $_.Score -and $_.Score -ge 100 }).Count
  $sumTotal.Text = Plural $n 'аккаунт' 'аккаунта' 'аккаунтов'
  $sumOk.Text = "$okN доступно"; $sumOkB.Visibility = if ($okN) { 'Visible' } else { 'Collapsed' }
  $sumLim.Text = "$limN в лимите"; $sumLimB.Visibility = if ($limN) { 'Visible' } else { 'Collapsed' }
  $iv = $script:cfg.refreshSec
  $ivText = if ($iv -lt 60) { "$iv сек" } elseif ($iv -eq 60) { 'минуту' } else { "$([int]($iv / 60)) мин" }
  $subText.Text = "Live-лимиты · обновление каждые $ivText"
  if ($iv -eq 60) { $subText.Text = 'Live-лимиты · обновление каждую минуту' }
  if (@($script:States | Where-Object { $_.Fetching }).Count) { $statusText.Text = 'Обновляю лимиты…' }
  elseif ($script:LastRefresh) {
    $left = [int]($iv - ((Get-Date) - $script:LastRefresh).TotalSeconds)
    $statusText.Text = 'Проверено ' + (Fmt-Ago $script:LastRefresh) + ' · следующее обновление через ' + [math]::Max(0, $left) + ' сек'
  }
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
foreach ($n in 'Shell', 'ShellScale', 'Folder', 'Cards', 'SubText', 'SumTotal', 'SumOk', 'SumOkB', 'SumLim', 'SumLimB', 'StatusText', 'RefreshRot', 'Toast', 'ToastY', 'ToastIcon', 'ToastText') {
  Set-Variable -Name ($n.Substring(0, 1).ToLower() + $n.Substring(1)) -Value $win.FindName($n) -Scope Script
}
$tbFolder = $folder; $cardsPanel = $cards

$script:AnimTimer = New-Object Windows.Threading.DispatcherTimer
$script:AnimTimer.Interval = [TimeSpan]::FromMilliseconds(16)
$script:AnimTimer.Add_Tick({ Anim-Tick })

$tbFolder.Text = if ($script:cfg.recent.Count) { $script:cfg.recent[0] } else { $PSScriptRoot }
if ($env:CA_DEMO) { $tbFolder.Text = 'C:\Projects\my-app' }

$win.FindName('TitleBar').Add_MouseLeftButtonDown({ param($s, $e) if ($e.ClickCount -eq 1) { try { $win.DragMove() } catch {} } })
$win.FindName('BtnMin').Add_Click({ $win.WindowState = 'Minimized' })
$win.FindName('BtnClose').Add_Click({ $win.Close() })
$win.FindName('BtnSettings').Add_Click({ Show-Settings })
$win.FindName('BtnRefresh').Add_Click({ Refresh-All })
$win.FindName('BtnBest').Add_Click({ Start-Best })
$win.FindName('BtnBrowse').Add_Click({
  $d = New-Object Windows.Forms.FolderBrowserDialog
  $d.Description = 'Папка проекта'; $cur = Get-Folder; if ($cur) { $d.SelectedPath = $cur }
  if ($d.ShowDialog() -eq 'OK') { $tbFolder.Text = $d.SelectedPath }
})
$win.FindName('BtnRecent').Add_Click({ param($s, $e)
  $items = @($script:cfg.recent | ForEach-Object { @{ Icon = [string][char]0xE8B7; Text = $_; Tag = $_; Click = { param($x, $y) $tbFolder.Text = $x.Tag } } })
  if (-not $items.Count) { $items = @(@{ Icon = [string][char]0xE946; Text = 'Пока пусто — папки появятся после запуска'; Tag = $null; Click = {} }) }
  $m = New-Menu $items; $m.PlacementTarget = $s; $m.Placement = 'Bottom'; $m.IsOpen = $true
})

$onDragOver = { param($s, $e)
  if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { $e.Effects = 'Copy' } else { $e.Effects = 'None' }
  $e.Handled = $true }
$onDrop = { param($s, $e)
  $p = @($e.Data.GetData([Windows.DataFormats]::FileDrop))[0]
  if ($p) { if (Test-Path -LiteralPath $p -PathType Leaf) { $p = Split-Path -LiteralPath $p -Parent }; $tbFolder.Text = $p; Show-Toast ('Папка: ' + (Split-Path $p -Leaf)) 'ok' }
  $e.Handled = $true }
$win.Add_PreviewDragOver($onDragOver); $win.Add_PreviewDrop($onDrop)
$tbFolder.Add_PreviewDragOver($onDragOver); $tbFolder.Add_PreviewDrop($onDrop)

$tick = New-Object Windows.Threading.DispatcherTimer
$tick.Interval = [TimeSpan]::FromSeconds(1)
$tick.Add_Tick({
  Update-All
  if (-not $script:LastRefresh -or ((Get-Date) - $script:LastRefresh).TotalSeconds -ge $script:cfg.refreshSec) { Refresh-All }
  if ($script:ToastUntil -and (Get-Date) -gt $script:ToastUntil) { $script:ToastUntil = $null; Animate $toast 'Opacity' 0 300; Animate $toastY 'Y' 24 300 }
})
$poll = New-Object Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromMilliseconds(200)
$poll.Add_Tick({ Collect-Jobs })
$win.Add_Activated({ if ($script:LastRefresh -and ((Get-Date) - $script:LastRefresh).TotalSeconds -ge 15) { Refresh-All } })
$win.Add_ContentRendered({ Animate $shell 'Opacity' 1 280 0; Animate $shellScale 'ScaleX' 1 380 0.97; Animate $shellScale 'ScaleY' 1 380 0.97 })
$win.Add_Closing({ $tick.Stop(); $poll.Stop(); Save-Cfg; try { $script:Pool.Close() } catch {} })

# режим скриншота для проверки (CA_SHOT=путь.png, CA_SHOT_DIALOG=путь.png)
if ($env:CA_SHOT) {
  $shot = New-Object Windows.Threading.DispatcherTimer; $shot.Interval = [TimeSpan]::FromSeconds(6)
  $shot.Add_Tick({
    $shot.Stop(); Save-Shot $win $env:CA_SHOT
    if ($env:CA_SHOT_DIALOG) { Add-Account }
    $win.Close() })
  $shot.Start()
}

Build-Cards
Refresh-All
$tick.Start(); $poll.Start()
[void]$win.ShowDialog()
