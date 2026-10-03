<script lang="ts">
  import { open } from '@tauri-apps/plugin-dialog'
  import { Folder, History, Zap, Info } from '@lucide/svelte'
  import { app, launchBest, openMenu, type MenuItem } from '../lib/store.svelte'
  import { api } from '../lib/api'
  import { t } from '../lib/i18n.svelte'
  import { tip } from '../lib/tip.svelte'

  async function browse() {
    const cur = await api.resolveFolder(app.folder)
    const r = await open({ directory: true, title: t('browseTitle'), defaultPath: cur ?? undefined })
    if (typeof r === 'string') app.folder = r
  }

  function recent(e: MouseEvent) {
    const list = app.cfg?.recent ?? []
    const items: MenuItem[] = list.length
      ? list.map((r) => ({ icon: Folder, text: r, action: () => (app.folder = r) }))
      : [{ icon: Info, text: t('recentEmpty'), disabled: true, action: () => {} }]
    openMenu(e.currentTarget as HTMLElement, items, 'left', 460)
  }
</script>

<div class="bar">
  <label class="field">
    <Folder size={16} strokeWidth={1.8} />
    <input class="input" bind:value={app.folder} placeholder={t('folderPh')} spellcheck="false" />
  </label>
  <button class="btn ghost square" onclick={recent} use:tip={t('recent')}><History size={16} /></button>
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
  .best { margin-left: 2px; padding: 0 18px; }
</style>
