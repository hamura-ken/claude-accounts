<script lang="ts">
  let { checked = $bindable(false), label }: { checked: boolean; label: string } = $props()
</script>

<label class="toggle">
  <input type="checkbox" bind:checked />
  <span class="sw"><i></i></span>
  <span class="txt">{label}</span>
</label>

<style>
  .toggle { display: inline-flex; align-items: center; gap: 11px; cursor: pointer; color: var(--text2); }
  input { position: absolute; opacity: 0; pointer-events: none; }
  .sw { position: relative; width: 40px; height: 22px; border-radius: 11px; background: var(--track); flex-shrink: 0; transition: background .18s; }
  .sw i { position: absolute; top: 3px; left: 3px; width: 16px; height: 16px; border-radius: 50%; background: #fff; box-shadow: 0 1px 3px rgba(0, 0, 0, .25); transition: transform .2s var(--ease); }
  input:checked + .sw { background: var(--accent); }
  input:checked + .sw i { transform: translateX(18px); }
</style>
