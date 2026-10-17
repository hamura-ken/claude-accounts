<script lang="ts">
  import { tick } from 'svelte'
  import { open } from '@tauri-apps/plugin-dialog'
  import { Folder, History, Zap } from '@lucide/svelte'
  import { app, launchBest, openRecent } from '../lib/store.svelte'
  import { api } from '../lib/api'
  import { t } from '../lib/i18n.svelte'
  import { tip } from '../lib/tip.svelte'

  let bar: HTMLDivElement | undefined = $state()
  let input: HTMLInputElement | undefined = $state()

  async function browse() {
    const cur = await api.resolveFolder(app.folder).catch(() => null)
    const r = await open({ directory: true, title: t('browseTitle'), defaultPath: cur ?? undefined })
    if (typeof r === 'string') app.folder = r
  }

  /** длинный путь, который не влез в поле, — целиком в подсказке */
  let full: string | null = $state(null)

  // путь выбран из истории, «Обзора» или перетаскиванием — показываем его конец (имя папки), а не начало диска
  function showEnd() {
    if (!input) return
    if (document.activeElement !== input) input.scrollLeft = input.scrollWidth
    full = app.folder && input.scrollWidth > input.clientWidth ? app.folder : null
  }
  $effect(() => {
    app.folder
    tick().then(showEnd)
  })
  // то же при изменении ширины окна и после загрузки шрифта
  $effect(() => {
    if (!input) return
    // через кадр: прокрутку, выставленную прямо в колбэке, браузер сбрасывает при раскладке
    const ro = new ResizeObserver(() => requestAnimationFrame(showEnd))
    ro.observe(input)
    return () => ro.disconnect()
  })
</script>

<div class="bar" bind:this={bar}>
  <label class="field">
    <Folder size={16} strokeWidth={1.8} />
    <input class="input" bind:this={input} bind:value={app.folder} placeholder={t('folderPh')} spellcheck="false" use:tip={full} />
  </label>
  <button class="btn ghost square" class:on={app.recent} onclick={() => bar && openRecent(bar)} use:tip={t('recent')}><History size={16} /></button>
  <button class="btn ghost" onclick={browse}>{t('browse')}</button>
  <button class="btn accent best" onclick={launchBest} use:tip={t('bestTip')}><Zap size={15} fill="currentColor" strokeWidth={1.5} />{t('best')}</button>
</div>

<style>
  .bar {
    display: flex; gap: 8px; align-items: center; margin: 18px 28px 0; padding: 10px; flex-shrink: 0;
    background: var(--panel); border: 1px solid var(--panel-line); border-radius: 16px;
  }
  .field { position: relative; flex: 1; min-width: 0; display: flex; align-items: center; color: var(--muted); }
  .field :global(svg) { position: absolute; left: 13px; pointer-events: none; }
  .field .input { padding-left: 38px; }
  .square { width: 40px; padding: 0; }
  .square.on { border-color: #d97757; color: #e8845f; }
  .best { margin-left: 2px; padding: 0 18px; }
</style>
