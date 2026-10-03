<script lang="ts">
  import { tipState } from '../lib/tip.svelte'

  let el: HTMLDivElement | undefined = $state()
  let w = $state(0)
  // не даём подсказке вылезти за края окна
  const left = $derived(Math.min(Math.max(8, tipState.x - w / 2), window.innerWidth - w - 8))
</script>

<div
  bind:this={el}
  bind:offsetWidth={w}
  class="tip"
  class:show={tipState.show}
  class:below={tipState.below}
  style:left="{left}px"
  style:top="{tipState.y}px"
>
  {tipState.text}
</div>

<style>
  .tip {
    position: fixed; z-index: 100; max-width: 340px; padding: 6px 10px; border-radius: 8px;
    background: var(--menu); border: 1px solid var(--menu-line); color: var(--text2); font-size: 12px; line-height: 1.45;
    white-space: pre-line; pointer-events: none; box-shadow: 0 8px 24px rgba(0, 0, 0, .25);
    translate: 0 -100%; opacity: 0; transform: translateY(3px); transition: opacity .12s, transform .12s;
  }
  .tip.below { translate: 0 0; transform: translateY(-3px); }
  .tip.show { opacity: 1; transform: none; }
</style>
