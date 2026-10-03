<script lang="ts">
  import { app } from '../lib/store.svelte'

  let el: HTMLDivElement | undefined = $state()
  let h = $state(0)
  // если снизу не хватает места — открываемся вверх от кнопки
  const top = $derived(app.menu ? Math.min(app.menu.y, window.innerHeight - h - 8) : 0)

  function close() {
    app.menu = null
  }
  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') close()
  }
</script>

<svelte:window onkeydown={onKey} onblur={close} onresize={close} />

{#if app.menu}
  <!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
  <div class="scrim" onmousedown={close}></div>
  <div bind:this={el} bind:offsetHeight={h} class="menu" style:left="{app.menu.x}px" style:top="{top}px" style:width="{app.menu.width}px">
    {#each app.menu.items as it}
      {#if it === '-'}
        <div class="sep"></div>
      {:else}
        <button class="item" class:danger={it.danger} disabled={it.disabled} onclick={() => { close(); it.action() }}>
          <it.icon size={15} strokeWidth={1.9} />
          <span>{it.text}</span>
        </button>
      {/if}
    {/each}
  </div>
{/if}

<style>
  .scrim { position: fixed; inset: 0; z-index: 70; }
  .menu {
    position: fixed; z-index: 71; padding: 6px; border-radius: 12px; max-width: calc(100vw - 16px);
    background: var(--menu); border: 1px solid var(--menu-line); box-shadow: var(--shadow);
    animation: pop .16s var(--ease); transform-origin: top right;
  }
  @keyframes pop { from { opacity: 0; transform: scale(.96) translateY(-4px); } }
  .item {
    width: 100%; display: flex; align-items: center; gap: 11px; padding: 8px 10px; border: 0; border-radius: 7px;
    background: transparent; color: var(--text2); font-size: 13px; text-align: left; cursor: pointer;
  }
  .item :global(svg) { flex-shrink: 0; color: var(--muted); }
  .item span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .item:hover { background: var(--menu-hover); }
  .item:disabled { opacity: .4; pointer-events: none; }
  .danger, .danger :global(svg) { color: var(--red); }
  .sep { height: 1px; margin: 5px 8px; background: var(--menu-line); }
</style>
