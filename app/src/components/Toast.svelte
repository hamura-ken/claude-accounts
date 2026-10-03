<script lang="ts">
  import { fly } from 'svelte/transition'
  import { cubicOut } from 'svelte/easing'
  import { CircleCheck, CircleAlert } from '@lucide/svelte'
  import { app } from '../lib/store.svelte'
</script>

{#if app.toast}
  {#key app.toast.id}
    <div class="toast {app.toast.kind}" in:fly={{ y: 24, duration: 320, easing: cubicOut }} out:fly={{ y: 16, duration: 220 }}>
      {#if app.toast.kind === 'err'}<CircleAlert size={16} />{:else}<CircleCheck size={16} />{/if}
      <span>{app.toast.text}</span>
    </div>
  {/key}
{/if}

<style>
  .toast {
    position: fixed; left: 50%; bottom: 26px; translate: -50% 0; z-index: 60; max-width: calc(100% - 60px);
    display: flex; align-items: center; gap: 11px; padding: 11px 16px; border-radius: 12px;
    background: var(--toast); border: 1px solid var(--toast-line); box-shadow: var(--shadow); pointer-events: none;
  }
  .toast :global(svg) { flex-shrink: 0; }
  .ok :global(svg) { color: var(--green); }
  .err :global(svg) { color: var(--red); }
</style>
