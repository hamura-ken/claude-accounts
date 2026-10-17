<script lang="ts">
  import { onMount, tick } from 'svelte'
  import { Folder, FolderX, Search, X, Info } from '@lucide/svelte'
  import { app, removeRecent, clearRecent, toast } from '../lib/store.svelte'
  import { api } from '../lib/api'
  import { t } from '../lib/i18n.svelte'
  import { tip } from '../lib/tip.svelte'
  import { fmtWhen } from '../lib/format'

  let q = $state('')
  let sel = $state(0)
  /** пути (в нижнем регистре), которых нет на диске; проверка идёт в фоне после открытия */
  let missing = $state(new Set<string>())
  let input: HTMLInputElement | undefined = $state()
  let list: HTMLDivElement | undefined = $state()
  let winH = $state(window.innerHeight)

  const all = $derived(app.cfg?.recent ?? [])
  // несколько слов через пробел — все должны встретиться в пути
  const items = $derived.by(() => {
    const words = q.toLowerCase().split(/\s+/).filter(Boolean)
    return words.length ? all.filter((p) => words.every((w) => p.toLowerCase().includes(w))) : all
  })
  const gone = $derived(all.filter((p) => missing.has(p.toLowerCase())))
  // всегда под строкой с папкой, чтобы её не закрывать; на низком окне панель просто ниже ростом
  const maxH = $derived(app.recent ? Math.max(200, Math.min(560, winH - app.recent.y - 12)) : 0)

  const leaf = (p: string) => p.split('\\').filter(Boolean).pop() ?? p
  const parent = (p: string) => {
    const i = p.replace(/\\+$/, '').lastIndexOf('\\')
    return i > 0 ? p.slice(0, i + 1) : ''
  }

  onMount(() => {
    input?.focus()
    const paths = [...all]
    api
      .pathsExist(paths)
      .then((ex) => (missing = new Set(paths.filter((_, i) => !ex[i]).map((p) => p.toLowerCase()))))
      .catch(() => {})
  })

  function close() {
    app.recent = null
  }

  function pick(p: string) {
    if (missing.has(p.toLowerCase())) return toast(t('noFolder', p), 'err')
    app.folder = p
    close()
  }

  function remove(p: string) {
    removeRecent([p])
    sel = Math.min(sel, items.length - 1)
  }

  async function move(d: number) {
    if (!items.length) return
    sel = (sel + d + items.length) % items.length
    await tick()
    list?.querySelector('.row.on')?.scrollIntoView({ block: 'nearest' })
  }

  function onKey(e: KeyboardEvent) {
    // пока открыт диалог подтверждения, клавиши его
    if (app.confirm) return
    if (e.key === 'Escape') close()
    else if (e.key === 'ArrowDown') (e.preventDefault(), move(1))
    else if (e.key === 'ArrowUp') (e.preventDefault(), move(-1))
    else if (e.key === 'Enter' && items[sel]) (e.preventDefault(), pick(items[sel]))
    else if (e.key === 'Delete' && e.shiftKey && items[sel]) (e.preventDefault(), remove(items[sel]))
  }

  $effect(() => {
    q
    sel = 0
  })
</script>

<svelte:window onkeydown={onKey} onblur={close} onresize={close} bind:innerHeight={winH} />

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="scrim" onmousedown={close}></div>
<div class="panel no-drag" style:left="{app.recent?.x}px" style:top="{app.recent?.y}px" style:width="{app.recent?.w}px" style:max-height="{maxH}px">
  <label class="search">
    <Search size={15} strokeWidth={1.9} />
    <input bind:this={input} bind:value={q} placeholder={t('rcSearch')} spellcheck="false" />
  </label>

  <div class="list" bind:this={list} role="listbox">
    {#if !all.length}
      <div class="empty"><Info size={15} />{t('recentEmpty')}</div>
    {:else if !items.length}
      <div class="empty"><Search size={15} />{t('rcNoMatch')}</div>
    {/if}
    {#each items as p, i (p)}
      {@const lost = missing.has(p.toLowerCase())}
      {@const at = app.cfg?.recentAt[p]}
      {@const Icon = lost ? FolderX : Folder}
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <div
        class="row"
        class:on={i === sel}
        class:lost
        class:cur={p.toLowerCase() === app.folder.toLowerCase()}
        role="option"
        tabindex="-1"
        aria-selected={i === sel}
        onmousemove={() => (sel = i)}
        onclick={() => pick(p)}
      >
        <Icon size={17} strokeWidth={1.8} />
        <div class="txt">
          <div class="name">{leaf(p)}</div>
          <div class="path">{#if parent(p)}{parent(p)}<b>{leaf(p)}</b>{:else}{p}{/if}</div>
        </div>
        {#if lost}
          <span class="tag">{t('rcMissing')}</span>
        {:else if at}
          <span class="when">{fmtWhen(at, app.now)}</span>
        {/if}
        <button class="rm" onclick={(e) => (e.stopPropagation(), remove(p))} use:tip={t('rcRemove')}><X size={14} /></button>
      </div>
    {/each}
  </div>

  {#if all.length}
    <div class="foot">
      <span class="count">{items.length === all.length ? t('rcTotal', all.length) : t('rcFound', items.length, all.length)}</span>
      <span class="keys">{t('rcKeys')}</span>
      {#if gone.length}
        <button class="btn ghost sm" onclick={() => removeRecent(gone)}>{t('rcPrune', gone.length)}</button>
      {/if}
      <button class="btn ghost sm danger-text" onclick={clearRecent}>{t('rcClear')}</button>
    </div>
  {/if}
</div>

<style>
  .scrim { position: fixed; inset: 0; z-index: 70; }
  .panel {
    position: fixed; z-index: 71; display: flex; flex-direction: column; max-width: calc(100vw - 16px);
    border-radius: 14px; overflow: hidden;
    background: var(--menu); border: 1px solid var(--menu-line); box-shadow: var(--shadow);
    animation: pop .16s var(--ease); transform-origin: top center;
  }
  @keyframes pop { from { opacity: 0; transform: scale(.98) translateY(-4px); } }

  .search { display: flex; align-items: center; gap: 10px; padding: 0 14px; border-bottom: 1px solid var(--menu-line); color: var(--muted); flex-shrink: 0; }
  .search input { flex: 1; height: 44px; border: 0; outline: none; background: transparent; color: var(--text); user-select: text; }
  .search input::placeholder { color: var(--ph); }

  .list { flex: 1; min-height: 0; overflow-y: auto; padding: 6px; }
  .list::-webkit-scrollbar-track { margin: 6px 0; }
  .empty { display: flex; align-items: center; gap: 10px; padding: 14px 12px; color: var(--muted); }

  .row {
    position: relative; display: flex; align-items: center; gap: 12px; padding: 8px 8px 8px 12px; border-radius: 9px;
    cursor: pointer; color: var(--text2);
  }
  .row > :global(svg) { flex-shrink: 0; color: var(--muted); }
  .row.on { background: var(--menu-hover); }
  .row.cur::before { content: ''; position: absolute; left: 3px; top: 10px; bottom: 10px; width: 3px; border-radius: 2px; background: #d97757; }
  .row.lost { color: var(--faint); }
  .row.lost > :global(svg) { color: var(--red); opacity: .8; }
  .txt { flex: 1; min-width: 0; }
  .name { font-weight: 600; font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  /* полный путь всегда виден целиком: длинный переносится, а не обрезается */
  .path { margin-top: 2px; font-size: 12px; line-height: 1.4; color: var(--muted); overflow-wrap: anywhere; user-select: text; }
  .path b { font-weight: 500; color: var(--text2); }
  .lost .path b { color: inherit; }
  .when, .tag { flex-shrink: 0; font-size: 11.5px; color: var(--faint); white-space: nowrap; }
  .tag { padding: 2px 7px; border-radius: 6px; background: var(--red-bg); color: var(--red-text); font-weight: 500; }
  .rm {
    flex-shrink: 0; display: grid; place-items: center; width: 26px; height: 26px; border: 0; border-radius: 7px;
    background: transparent; color: var(--muted); cursor: pointer; opacity: 0; transition: opacity .12s, background-color .12s;
  }
  .row.on .rm { opacity: 1; }
  .rm:hover { background: var(--hover); color: var(--red); }

  .foot { display: flex; align-items: center; gap: 8px; padding: 8px 10px 8px 16px; border-top: 1px solid var(--menu-line); flex-shrink: 0; }
  .count { color: var(--muted); font-size: 12px; white-space: nowrap; }
  .keys { flex: 1; min-width: 0; color: var(--faint); font-size: 11.5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sm { height: 30px; padding: 0 12px; font-size: 12px; border-radius: 8px; }
  .danger-text { color: var(--red); }
</style>
