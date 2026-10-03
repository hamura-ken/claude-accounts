<script lang="ts">
  import type { Snippet } from 'svelte'
  import { fade, scale } from 'svelte/transition'
  import { cubicOut } from 'svelte/easing'
  import { X } from '@lucide/svelte'

  let { title, sub = '', width = 560, onclose, children }: { title: string; sub?: string; width?: number; onclose: () => void; children: Snippet } = $props()

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') onclose()
  }
</script>

<svelte:window onkeydown={onKey} />

<div class="scrim" transition:fade|global={{ duration: 180 }}></div>
<div class="wrap">
  <div class="modal" style:width="{width}px" role="dialog" aria-modal="true" transition:scale|global={{ start: 0.95, duration: 260, easing: cubicOut }}>
    <button class="btn icon x" onclick={onclose}><X size={16} /></button>
    <h2>{title}</h2>
    {#if sub}<p class="sub">{sub}</p>{/if}
    {@render children()}
  </div>
</div>

<style>
  .scrim { position: fixed; inset: 0; z-index: 80; background: var(--scrim); }
  .wrap { position: fixed; inset: 0; z-index: 81; display: grid; place-items: center; padding: 20px; pointer-events: none; }
  .modal {
    position: relative; max-width: 100%; max-height: calc(100vh - 40px); overflow-y: auto; pointer-events: auto;
    padding: 24px 28px; border-radius: 18px; border: 1px solid var(--dialog-line); box-shadow: var(--shadow);
    background: radial-gradient(90% 60% at 0% 0%, var(--dlg-glow), var(--dialog)); background-color: var(--dialog);
  }
  h2 { margin: 0 40px 0 0; font-size: 20px; font-weight: 600; }
  .sub { margin: 6px 40px 0 0; font-size: 12.5px; line-height: 1.45; color: var(--muted); }
  .modal::-webkit-scrollbar-track { margin: 16px 0; }
  .x { position: absolute; top: 16px; right: 16px; }
</style>
