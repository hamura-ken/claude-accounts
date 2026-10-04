<script lang="ts">
  import { onMount, untrack } from 'svelte'
  import { slide } from 'svelte/transition'
  import { Check, CircleCheck, CircleAlert, LoaderCircle, FolderOpen } from '@lucide/svelte'
  import { app, PALETTE } from '../lib/store.svelte'
  import { api, type ProxyCheck } from '../lib/api'
  import { normalizeProxy, proxyHost } from '../lib/proxy'
  import { t } from '../lib/i18n.svelte'
  import { tip } from '../lib/tip.svelte'
  import Modal from './Modal.svelte'
  import Toggle from './Toggle.svelte'

  let { req }: { req: NonNullable<typeof app.accDialog> } = $props()
  // диалог создаётся заново на каждый запрос, поэтому берём значения один раз:
  // после закрытия (app.accDialog = null) prop req тоже станет null
  const { acc, resolve } = untrack(() => req)
  const isNew = !acc
  const count = app.cfg?.accounts.length ?? 0

  let name = $state(acc?.name ?? `Account ${count + 1}`)
  let color = $state(acc ? acc.color : count % PALETTE.length)
  let pxOn = $state(!!acc?.proxy)
  let proxy = $state(acc?.proxy ?? '')
  let full = $state(acc ? acc.fullAccess : true)
  let args = $state(acc?.args ?? '')
  // сохранённый прокси считаем проверенным и при открытии не перепроверяем (лишний запрос);
  // проверка нужна только новому или изменённому адресу
  const savedUrl = acc?.proxy || null
  let checkedUrl = $state<string | null>(savedUrl)
  let failedUrl = $state<string | null>(null)
  let busy = $state(false)
  let px = $state<{ kind: 'ok' | 'err' | 'busy'; text: string } | null>(null)
  let nameEl: HTMLInputElement | undefined = $state()
  let proxyEl: HTMLInputElement | undefined = $state()

  const norm = $derived(normalizeProxy(proxy))

  const hint = $derived.by(() => {
    if (!name.trim()) return t('vName')
    if (!pxOn) return ''
    if (!norm.ok) return t(norm.err)
    if (norm.url === savedUrl) return ''
    if (busy) return t('vBusy')
    if (failedUrl === norm.url) return t('vFailed')
    if (checkedUrl !== norm.url) return t('vCheck')
    return ''
  })

  // при правке адреса старый результат проверки больше не относится к делу
  $effect(() => {
    const url = norm.ok ? norm.url : null
    if (px && px.kind !== 'busy' && url !== checkedUrl && url !== failedUrl) px = null
  })

  function errText(r: ProxyCheck): string {
    switch (r.kind) {
      case 'p407': return t('e407')
      case 'code': return t('eCode', r.code ?? 0)
      case 'timeout': return t('eTimeout')
      case 'connect': return t('eConnect')
      case 'pname': return t('ePName')
      case 'recv': return t('eRecv')
      case 'tls': return t('eTls')
      default: return r.err ?? t('eConnect')
    }
  }

  async function check() {
    if (!norm.ok) {
      px = { kind: 'err', text: t(norm.err) }
      return
    }
    const url = norm.url
    busy = true
    px = { kind: 'busy', text: t('pxChecking', proxyHost(url)) }
    const r = await api.checkProxy(url)
    busy = false
    const now = normalizeProxy(proxy)
    // пока шла проверка, адрес успели поменять
    if (!now.ok || now.url !== url) {
      px = null
      return
    }
    if (r.ok) {
      checkedUrl = url
      failedUrl = null
      let loc = r.ip ? ` · IP ${r.ip}` : ''
      const place = [r.city, r.country].filter(Boolean).join(', ')
      if (place) loc += ` · ${place}`
      px = { kind: 'ok', text: t('pxOk', r.ms ?? 0, loc) }
    } else {
      checkedUrl = null
      failedUrl = url
      px = { kind: 'err', text: errText(r) }
    }
  }

  function done(ok: boolean) {
    resolve(ok ? { name: name.trim(), color, proxy: pxOn && norm.ok ? norm.url : '', fullAccess: full, args: args.trim() } : null)
    app.accDialog = null
  }

  function setPx(on: boolean) {
    pxOn = on
    if (on) setTimeout(() => proxyEl?.focus(), 30)
  }

  onMount(() => {
    nameEl?.focus()
    nameEl?.select()
  })
</script>

<Modal title={t(isNew ? 'aNewTitle' : 'aEditTitle')} sub={t(isNew ? 'aNewSub' : 'aEditSub')} width={600} onclose={() => done(false)}>
  <form onsubmit={(e) => { e.preventDefault(); if (!hint) done(true) }}>
    <p class="caption">{t('aName')}</p>
    <input class="input" bind:this={nameEl} bind:value={name} placeholder={t('aNamePh')} spellcheck="false" />

    <p class="caption">{t('aColor')}</p>
    <div class="swatches">
      {#each PALETTE as c, i}
        <button type="button" class="sw" class:on={color === i} style:--a={c[0]} style:--b={c[1]} onclick={() => (color = i)} aria-label="color {i + 1}">
          {#if color === i}<Check size={14} strokeWidth={3} />{/if}
        </button>
      {/each}
    </div>

    <p class="caption">{t('aProxy')}</p>
    <div class="seg">
      <button type="button" class:on={!pxOn} onclick={() => setPx(false)}>{t('aPxNone')}</button>
      <button type="button" class:on={pxOn} onclick={() => setPx(true)}>{t('aPxOn')}</button>
    </div>
    {#if pxOn}
      <div class="px" transition:slide={{ duration: 200 }}>
        <div class="row">
          <input
            class="input"
            bind:this={proxyEl}
            bind:value={proxy}
            placeholder={t('aPxPh')}
            spellcheck="false"
            onkeydown={(e) => { if (e.key === 'Enter') { e.preventDefault(); check() } }}
          />
          <button type="button" class="btn ghost" disabled={busy} onclick={check}><Check size={15} />{t('aCheck')}</button>
        </div>
        {#if px}
          <div class="status {px.kind}" transition:slide={{ duration: 180 }}>
            {#if px.kind === 'ok'}<CircleCheck size={15} />{:else if px.kind === 'err'}<CircleAlert size={15} />{:else}<LoaderCircle size={15} class="spin" />{/if}
            <span>{px.text}</span>
          </div>
        {/if}
      </div>
    {:else}
      <p class="muted" transition:slide={{ duration: 200 }}>{t('aPxNoneHint')}</p>
    {/if}

    <p class="caption">{t('aLaunch')}</p>
    <Toggle bind:checked={full} label={t('aFull')} />
    <p class="label">{t('aArgs')}</p>
    <input class="input" bind:value={args} placeholder={t('aArgsPh')} spellcheck="false" />

    {#if acc}
      <p class="label">{t('aDir')}</p>
      <div class="dir">
        <span>{acc.dir}</span>
        <button type="button" class="btn icon" onclick={() => api.openPath(acc.dir)} use:tip={t('aOpenDir')}><FolderOpen size={16} /></button>
      </div>
    {/if}

    <div class="foot">
      <span class="hint">{hint}</span>
      <button type="button" class="btn ghost" onclick={() => done(false)}>{t('cancel')}</button>
      <button type="submit" class="btn accent" disabled={!!hint}>{t(isNew ? 'aNewOk' : 'save')}</button>
    </div>
  </form>
</Modal>

<style>
  .caption { margin-top: 22px; }
  .label { margin: 16px 0 7px; font-size: 12px; color: var(--muted); }
  .swatches { display: flex; gap: 6px; }
  .sw {
    width: 30px; height: 30px; border-radius: 50%; border: 0; cursor: pointer; display: grid; place-items: center; color: #fff;
    background: linear-gradient(135deg, var(--a), var(--b)); transition: transform .15s var(--ease), box-shadow .15s;
  }
  .sw:hover { transform: scale(1.1); }
  .sw.on { box-shadow: 0 0 0 2px var(--dialog), 0 0 0 4px var(--a); }
  .px { padding-top: 10px; }
  .row { display: flex; gap: 8px; }
  .row .btn { flex-shrink: 0; min-width: 128px; }
  .status { display: flex; align-items: center; gap: 10px; margin-top: 8px; padding: 10px 13px; border-radius: 10px; font-size: 12.5px; }
  .status :global(svg) { flex-shrink: 0; }
  .status.ok { background: var(--green-bg); color: var(--green); }
  .status.err { background: var(--red-bg); color: var(--red); }
  .status.busy { background: var(--orange-bg); color: var(--orange); }
  .status :global(.spin) { animation: spin .9s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .muted { margin: 9px 0 0 2px; font-size: 12px; color: var(--caption); }
  .dir { display: flex; align-items: center; gap: 8px; font-size: 12.5px; color: var(--text2); }
  .dir span { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; user-select: text; }
  .foot { display: flex; align-items: center; gap: 10px; margin-top: 26px; }
  .hint { flex: 1; font-size: 12px; color: var(--orange); }
  .foot .btn.ghost { min-width: 110px; }
  .foot .btn.accent { min-width: 150px; }
</style>
