<script lang="ts">
  import { onMount, tick } from 'svelte'
  import { getCurrentWindow } from '@tauri-apps/api/window'
  import { getCurrentWebview } from '@tauri-apps/api/webview'
  import { FolderDown } from '@lucide/svelte'
  import { app, init, refreshAll, pickFolderFromPath } from './lib/store.svelte'
  import { t } from './lib/i18n.svelte'
  import TitleBar from './components/TitleBar.svelte'
  import FolderBar from './components/FolderBar.svelte'
  import AccountCard from './components/AccountCard.svelte'
  import AddTile from './components/AddTile.svelte'
  import Toast from './components/Toast.svelte'
  import Menu from './components/Menu.svelte'
  import Tooltip from './components/Tooltip.svelte'
  import ConfirmDialog from './components/ConfirmDialog.svelte'
  import AccountDialog from './components/AccountDialog.svelte'
  import SettingsDialog from './components/SettingsDialog.svelte'

  let ready = $state(false)
  let dropping = $state(false)

  onMount(async () => {
    try {
      await init()
    } finally {
      ready = true
      await tick()
      // окно показываем после первой отрисовки — без белой вспышки
      requestAnimationFrame(() => getCurrentWindow().show())
    }
    getCurrentWebview().onDragDropEvent((e) => {
      const p = e.payload
      if (p.type === 'enter' || p.type === 'over') dropping = true
      else if (p.type === 'leave') dropping = false
      else if (p.type === 'drop') {
        dropping = false
        if (p.paths[0]) pickFolderFromPath(p.paths[0])
      }
    })
  })

  // окно тянется за любое пустое место; всё интерактивное клик забирает себе
  function onMouseDown(e: MouseEvent) {
    if (e.button !== 0 || e.detail > 1) return
    const el = e.target as HTMLElement
    if (el.closest('button, input, textarea, a, [role="button"], .no-drag, .modal, .menu')) return
    getCurrentWindow().startDragging()
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'F5') {
      e.preventDefault()
      refreshAll(true)
    }
  }
</script>

<svelte:window onkeydown={onKey} />

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<main class:ready onmousedown={onMouseDown}>
  <TitleBar />
  <FolderBar />
  <section class="scroll">
    <div class="grid">
      {#each app.accs as st, i (st.acc.dir)}
        <AccountCard {st} index={i} />
      {/each}
      <AddTile index={app.accs.length} />
    </div>
  </section>

  {#if dropping}
    <div class="drop">
      <div class="drop-box"><FolderDown size={28} strokeWidth={1.75} /><span>{t('dropHere')}</span></div>
    </div>
  {/if}
</main>

<Toast />
<Menu />
<Tooltip />
{#if app.confirm}<ConfirmDialog req={app.confirm} />{/if}
{#if app.accDialog}<AccountDialog req={app.accDialog} />{/if}
{#if app.settingsOpen}<SettingsDialog />{/if}

<style>
  main {
    height: 100%; display: flex; flex-direction: column;
    opacity: 0; transform: scale(.985); transition: opacity .35s ease, transform .45s var(--ease);
  }
  main.ready { opacity: 1; transform: none; }
  .scroll { flex: 1; min-height: 0; overflow-y: auto; padding: 20px 20px 24px 28px; scrollbar-gutter: stable; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 16px; align-items: stretch; }
  .drop { position: fixed; inset: 0; z-index: 50; padding: 14px; pointer-events: none; animation: fade .15s ease; }
  .drop-box {
    height: 100%; border-radius: 18px; border: 2px dashed #d97757; background: rgba(217, 119, 87, .08);
    display: flex; flex-direction: column; gap: 12px; align-items: center; justify-content: center;
    color: #e8845f; font-size: 15px; font-weight: 600;
  }
  @keyframes fade { from { opacity: 0; } }
</style>
