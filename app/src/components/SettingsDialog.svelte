<script lang="ts">
  import { Moon, Sun, Monitor, RefreshCcw, FileText } from '@lucide/svelte'
  import { app, setTheme, setLang, saveCfg, syncSettings, toast } from '../lib/store.svelte'
  import { api, type Config } from '../lib/api'
  import { t } from '../lib/i18n.svelte'
  import { tip } from '../lib/tip.svelte'
  import Modal from './Modal.svelte'
  import Toggle from './Toggle.svelte'

  const cfg = app.cfg!
  // тема и язык применяются сразу (превью), «Отмена» возвращает как было
  const orig = { theme: cfg.theme, lang: cfg.lang as 'ru' | 'en' }
  let interval = $state(cfg.refreshSec)
  let terminal = $state(cfg.terminal === 'wt' && app.hasWt ? 'wt' : 'cmd')
  let minimize = $state(cfg.minimizeOnLaunch)

  const themes: [Config['theme'], any, string][] = [['dark', Moon, 'thDark'], ['light', Sun, 'thLight'], ['system', Monitor, 'thSys']]
  const intervals: [number, string][] = [[300, 'iv5'], [600, 'iv10'], [900, 'iv15'], [1800, 'iv30']]

  function close(save: boolean) {
    app.settingsOpen = false
    if (!save) {
      setTheme(orig.theme)
      setLang(orig.lang)
      return
    }
    cfg.refreshSec = interval
    cfg.terminal = terminal
    cfg.minimizeOnLaunch = minimize
    saveCfg()
    toast(t('tSaved'))
  }
</script>

<Modal title={t('setTitle')} sub={t('setSub')} width={580} onclose={() => close(false)}>
  <p class="caption">{t('sAppearance')}</p>
  <div class="grid">
    <span>{t('sTheme')}</span>
    <div class="seg">
      {#each themes as [v, Icon, k]}
        <button class:on={cfg.theme === v} onclick={() => setTheme(v)}><Icon size={14} />{t(k)}</button>
      {/each}
    </div>
    <span>{t('sLang')}</span>
    <div class="seg">
      <button class:on={cfg.lang === 'ru'} onclick={() => setLang('ru')}>Русский</button>
      <button class:on={cfg.lang === 'en'} onclick={() => setLang('en')}>English</button>
    </div>
  </div>

  <p class="caption">{t('sRefresh')}</p>
  <div class="seg">
    {#each intervals as [v, k]}
      <button class:on={interval === v} onclick={() => (interval = v)}>{t(k)}</button>
    {/each}
  </div>
  <p class="hint">{t('sRefreshHint')}</p>

  <p class="caption">{t('sTerminal')}</p>
  <div class="seg">
    <button class:on={terminal === 'cmd'} onclick={() => (terminal = 'cmd')}>{t('sCmd')}</button>
    <span use:tip={app.hasWt ? null : t('noWt')}>
      <button class:on={terminal === 'wt'} disabled={!app.hasWt} onclick={() => (terminal = 'wt')}>Windows Terminal</button>
    </span>
  </div>

  <p class="caption">{t('sBehavior')}</p>
  <Toggle bind:checked={minimize} label={t('sMinLaunch')} />

  <p class="caption">{t('sTools')}</p>
  <div class="tools">
    <button class="btn ghost" onclick={syncSettings}><RefreshCcw size={15} />{t('sSync')}</button>
    <button class="btn ghost" onclick={() => api.openConfig()}><FileText size={15} />{t('sCfg')}</button>
  </div>
  <p class="hint">{t('sSyncHint')}</p>

  <div class="foot">
    <button class="btn ghost" onclick={() => close(false)}>{t('cancel')}</button>
    <button class="btn accent" onclick={() => close(true)}>{t('save')}</button>
  </div>
</Modal>

<style>
  .caption { margin-top: 18px; }
  .grid { display: grid; grid-template-columns: auto 1fr; gap: 8px 18px; align-items: center; justify-items: start; color: var(--text2); }
  .seg span { display: inline-flex; }
  .tools { display: flex; flex-wrap: wrap; gap: 8px; }
  .hint { margin: 10px 0 0; font-size: 11.5px; line-height: 1.45; color: var(--caption); }
  .foot { display: flex; justify-content: flex-end; gap: 10px; margin-top: 20px; }
  .foot .btn { min-width: 120px; }
</style>
