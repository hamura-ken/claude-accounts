<script lang="ts">
  import { Plus } from '@lucide/svelte'
  import { addAccount } from '../lib/store.svelte'
  import { t } from '../lib/i18n.svelte'

  let { index }: { index: number } = $props()
</script>

<button class="tile" style:--delay="{index * 60}ms" onclick={addAccount}>
  <span class="plus"><Plus size={20} /></span>
  <span class="label">{t('addAcc')}</span>
</button>

<style>
  .tile {
    min-height: 200px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 14px;
    border-radius: 18px; border: 1.5px dashed var(--dash); background: transparent; cursor: pointer;
    transition: background .2s, border-color .2s; animation: rise .5s var(--ease) both; animation-delay: var(--delay);
  }
  .tile:hover { background: radial-gradient(closest-side, rgba(217, 119, 87, .13), rgba(217, 119, 87, .03)); border-color: rgba(217, 119, 87, .5); }
  .plus { width: 54px; height: 54px; border-radius: 50%; display: grid; place-items: center; background: var(--add-bg); color: #e8845f; transition: transform .2s var(--ease); }
  .tile:hover .plus { transform: scale(1.1); }
  .tile:active .plus { transform: scale(.95); }
  .label { font-size: 15px; font-weight: 600; color: var(--text2); }
  @keyframes rise { from { opacity: 0; transform: translateY(14px); } }
</style>
