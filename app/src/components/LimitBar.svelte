<script lang="ts">
  import { Tween } from 'svelte/motion'
  import { cubicOut } from 'svelte/easing'
  import { Clock } from '@lucide/svelte'
  import type { Limit } from '../lib/api'
  import { app, effPct } from '../lib/store.svelte'
  import { t } from '../lib/i18n.svelte'
  import { fmtAt, fmtUntil } from '../lib/format'
  import { tip } from '../lib/tip.svelte'

  let { label, lim }: { label: string; lim: Limit | null | undefined } = $props()

  const pct = $derived(Math.max(0, Math.min(100, effPct(lim))))
  // число и полоса плавно доезжают до нового значения
  const shown = new Tween(0, { duration: 900, easing: cubicOut })
  $effect(() => {
    shown.target = pct
  })
  const kind = $derived(!lim ? 'none' : pct >= 90 ? 'red' : pct >= 70 ? 'orange' : 'green')
  // таймер сброса — только когда лимит реально тратится
  const reset = $derived(lim?.reset && lim.reset > app.now && pct > 0 ? lim.reset : null)
</script>

<div class="limit {kind}">
  <div class="head">
    <span class="label">{label}</span>
    {#if reset}
      <span class="reset" use:tip={t('resetTip', fmtAt(reset, app.now))}><Clock size={11.5} strokeWidth={2.2} />{fmtUntil(reset, app.now)}</span>
    {/if}
    <span class="num">
      {#if lim}{Math.round(shown.current)}<small>%</small>{:else}—{/if}
    </span>
  </div>
  <div class="track">
    <div class="fill" style:width="{lim && shown.current >= 0.4 ? `max(8px, ${shown.current}%)` : '0'}"></div>
  </div>
</div>

<style>
  .head { display: flex; align-items: baseline; gap: 10px; margin-bottom: 8px; }
  .label { font-size: 12.5px; font-weight: 500; color: var(--muted); }
  .reset { display: inline-flex; align-items: center; gap: 5px; font-size: 12px; color: var(--faint); align-self: center; }
  .num { margin-left: auto; font-size: 20px; font-weight: 700; line-height: 1; font-variant-numeric: tabular-nums; letter-spacing: -.02em; }
  .num small { font-size: 12px; font-weight: 600; color: var(--muted); margin-left: 1px; }
  .none .num { color: var(--faint); font-weight: 500; }
  .orange .num { color: var(--orange); }
  .red .num { color: var(--red); }
  .track { height: 8px; border-radius: 4px; background: var(--bar-track); position: relative; }
  .fill { position: absolute; inset: 0 auto 0 0; border-radius: 4px; transition: background .4s; }
  .green .fill { background: linear-gradient(90deg, #2fbf62, #7bf0a2); box-shadow: 0 0 calc(12px * var(--glow-k)) rgba(63, 217, 122, calc(.55 * var(--glow-k))); }
  .orange .fill { background: linear-gradient(90deg, #e08e1e, #ffcb6b); box-shadow: 0 0 calc(12px * var(--glow-k)) rgba(240, 168, 58, calc(.55 * var(--glow-k))); }
  .red .fill { background: linear-gradient(90deg, #e3393f, #ff8a8d); box-shadow: 0 0 calc(12px * var(--glow-k)) rgba(255, 90, 96, calc(.55 * var(--glow-k))); }
</style>
