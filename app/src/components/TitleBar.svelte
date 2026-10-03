<script lang="ts">
  import { getCurrentWindow } from '@tauri-apps/api/window'
  import { RefreshCw, Sun, Moon, Settings, Minus, X } from '@lucide/svelte'
  import { app, score, refreshAll, setTheme, setLang } from '../lib/store.svelte'
  import { t, lang } from '../lib/i18n.svelte'
  import { fmtAgo } from '../lib/format'
  import { tip } from '../lib/tip.svelte'

  const scores = $derived(app.accs.map(score).filter((s): s is number => s !== null))
  const okN = $derived(scores.filter((s) => s < 100).length)
  const limN = $derived(scores.filter((s) => s >= 100).length)
  const busy = $derived(app.accs.some((s) => s.fetching))
  const refreshTip = $derived.by(() => {
    let s = t('refreshTip')
    if (busy) s += '\n' + t('refreshing')
    else if (app.lastRefresh && app.cfg) {
      const left = Math.max(0, Math.round(app.cfg.refreshSec - (app.now - app.lastRefresh) / 1000))
      s += '\n' + t('checkedAt', fmtAgo(app.lastRefresh, app.now), left)
    }
    return s
  })
  const win = getCurrentWindow()
</script>

<header>
  <div class="brand">
    <div class="logo">
      <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
        <g stroke="#fff" stroke-width="2.4" stroke-linecap="round">
          <path d="M12 4.5v15M4.5 12h15M6.7 6.7l10.6 10.6M17.3 6.7 6.7 17.3" />
        </g>
      </svg>
    </div>
    <h1>Claude Accounts</h1>
  </div>

  <div class="right">
    {#if okN}<span class="pill ok"><i></i>{t('sumOk', okN)}</span>{/if}
    {#if limN}<span class="pill lim"><i></i>{t('sumLim', limN)}</span>{/if}
    <span class="gap"></span>
    <button class="btn icon" class:spin={busy} onclick={() => refreshAll(true)} use:tip={refreshTip}><RefreshCw size={15} /></button>
    <button class="btn icon lang" onclick={() => setLang(lang.idx ? 'ru' : 'en')} use:tip={t('langTip')}>{lang.idx ? 'EN' : 'RU'}</button>
    <button class="btn icon" onclick={() => setTheme(app.theme === 'dark' ? 'light' : 'dark')} use:tip={t('themeTip')}>
      {#if app.theme === 'dark'}<Sun size={16} />{:else}<Moon size={15} />{/if}
    </button>
    <button class="btn icon" onclick={() => (app.settingsOpen = true)} use:tip={t('settings')}><Settings size={16} /></button>
    <span class="sep"></span>
    <button class="btn icon" onclick={() => win.minimize()} use:tip={t('minimize')}><Minus size={16} /></button>
    <button class="btn icon close" onclick={() => win.close()} use:tip={t('close')}><X size={16} /></button>
  </div>
</header>

<style>
  header { display: flex; align-items: center; justify-content: space-between; padding: 18px 14px 0 28px; flex-shrink: 0; }
  .brand { display: flex; align-items: center; gap: 14px; pointer-events: none; }
  .logo {
    width: 40px; height: 40px; border-radius: 12px; display: grid; place-items: center;
    background: linear-gradient(135deg, #f09a76, #c4533a); box-shadow: 0 6px 22px -4px rgba(224, 122, 85, .6);
  }
  h1 { margin: 0; font-size: 19px; font-weight: 600; letter-spacing: -.01em; }
  .right { display: flex; align-items: center; gap: 2px; }
  .gap { width: 8px; }
  .pill { display: inline-flex; align-items: center; gap: 7px; padding: 5px 10px; margin-left: 6px; border-radius: 9px; font-size: 12px; font-weight: 500; }
  .pill i { width: 6px; height: 6px; border-radius: 50%; }
  .pill.ok { background: var(--green-bg); color: var(--green-text); }
  .pill.ok i { background: var(--green); box-shadow: 0 0 8px var(--green); }
  .pill.lim { background: var(--red-bg); color: var(--red-text); }
  .pill.lim i { background: var(--red); }
  .btn.icon { width: 38px; height: 34px; }
  .lang { font-size: 11.5px; font-weight: 600; }
  .close:hover { background: #e5484d; color: #fff; }
  .close:hover::after { opacity: 0; }
  .sep { width: 1px; height: 16px; background: var(--line); margin: 0 6px; }
  .spin :global(svg) { animation: spin .9s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
