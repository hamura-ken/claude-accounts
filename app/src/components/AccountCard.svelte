<script lang="ts">
  import { Ellipsis, Globe, Star, Play, UserRound, ShieldCheck, TriangleAlert, Settings, RefreshCw, FolderOpen, ArrowUp, ArrowDown, LogOut, Trash2 } from '@lucide/svelte'
  import {
    app, PALETTE, effective, score, bestAcc, launch, openMenu, editAccount, refreshOne, moveAccount, logoutAccount, removeAccount,
    type AccState,
  } from '../lib/store.svelte'
  import { api } from '../lib/api'
  import { t } from '../lib/i18n.svelte'
  import { fmtAgo, fmtUntil } from '../lib/format'
  import { tip } from '../lib/tip.svelte'
  import LimitBar from './LimitBar.svelte'

  let { st, index }: { st: AccState; index: number } = $props()

  const color = $derived(PALETTE[st.acc.color % PALETTE.length])
  const logged = $derived(!!st.local?.loggedIn)
  const eff = $derived(effective(st))
  const sc = $derived(score(st))
  const best = $derived(bestAcc())
  const isBest = $derived(best === st)
  const multi = $derived(app.accs.filter((s) => (score(s) ?? 100) < 100).length >= 2)
  // яркая кнопка — у лучшего аккаунта и там, где нужно войти; у остальных спокойная
  const accentRun = $derived(!logged || isBest || (!best && sc === null))
  const initial = $derived(st.acc.name.match(/(\d+)\s*$/)?.[1] ?? (st.acc.name.trim()[0]?.toUpperCase() || '?'))

  const status = $derived.by(() => {
    if (!logged) return { kind: 'gray', text: t('stNoLogin') }
    if (sc === null) return { kind: 'gray', text: t('stNoData') }
    if (sc >= 100) return { kind: 'red', text: t('stLim') }
    if (sc >= 80) return { kind: 'orange', text: t('stNear') }
    return { kind: 'green', text: t('stOk') }
  })

  // свежесть данных — в подсказке; на карточке только проблема, мешающая видеть лимиты
  const fresh = $derived.by(() => {
    let tipText: string
    let why: string | null = null
    let show = false
    if (eff && eff.src === 'live' && !st.err) tipText = t('liveUpd', fmtAgo(eff.at!, app.now))
    else if (st.fetching && !eff) tipText = t('loading')
    else {
      tipText = eff ? t(eff.src === 'live' ? 'liveAgo' : 'fromCache', eff.at ? fmtAgo(eff.at, app.now) : '?') : t('noData')
      if (st.local?.tokenExpired || st.err === 'token') {
        why = t('whyToken')
        show = true
      } else if (st.err === 'rate') {
        // временное ограничение: данные на карточке остаются, пояснение — только в подсказке
        why = t('whyRate', fmtUntil(Math.max(st.retryAt, app.now + 60000), app.now))
        show = !eff
      } else if (st.err === 'net') {
        why = t(st.acc.proxy ? 'whyNetPx' : 'whyNet')
        show = true
      }
    }
    return { tipText: why ? `${tipText}\n${why}` : tipText, why: show ? why : null }
  })

  const proxyHost = $derived.by(() => {
    try {
      const u = new URL(st.acc.proxy)
      return `${u.hostname}:${u.port}`
    } catch {
      return st.acc.proxy
    }
  })

  function menu(e: MouseEvent) {
    const i = app.accs.indexOf(st)
    openMenu(e.currentTarget as HTMLElement, [
      { icon: Settings, text: t('mSettings'), action: () => editAccount(st) },
      { icon: RefreshCw, text: t('mRefresh'), action: () => refreshOne(st) },
      { icon: FolderOpen, text: t('mDir'), action: () => api.openPath(st.acc.dir) },
      '-',
      { icon: ArrowUp, text: t('mUp'), disabled: i === 0, action: () => moveAccount(st, -1) },
      { icon: ArrowDown, text: t('mDown'), disabled: i === app.accs.length - 1, action: () => moveAccount(st, 1) },
      '-',
      { icon: LogOut, text: t('mLogout'), disabled: !logged, action: () => logoutAccount(st) },
      { icon: Trash2, text: t('mRemove'), danger: true, action: () => removeAccount(st) },
    ])
  }
</script>

<article class="card" style:--c1={color[0]} style:--c2={color[1]} style:--delay="{index * 60}ms">
  <div class="top">
    <div class="avatar" use:tip={status.text}>
      <span>{initial}</span>
      <i class="dot {status.kind}"></i>
    </div>
    <div class="who">
      <div class="name-row">
        <span class="name">{st.acc.name}</span>
        {#if st.local?.plan}<span class="plan">{st.local.plan.toUpperCase()}</span>{/if}
        {#if isBest && multi}<span class="star" use:tip={t('bestStar')}><Star size={13} fill="currentColor" strokeWidth={0} /></span>{/if}
      </div>
      <div class="sub">
        {#if st.acc.proxy}<span class="px" use:tip={t('proxyTip', proxyHost)}><Globe size={12} /></span>{/if}
        <span class="email">{logged ? st.local?.email || t('signedIn') : t('notSignedIn')}</span>
      </div>
    </div>
    <button class="btn icon more" onclick={menu} use:tip={t('actions')}><Ellipsis size={18} /></button>
  </div>

  <div class="body">
    <div class="limits" class:hidden={!logged} use:tip={fresh.tipText}>
      <LimitBar label={t('five')} lim={eff?.data.five} />
      <LimitBar label={t('week')} lim={eff?.data.week} />
    </div>
    {#if !logged}
      <div class="nologin">
        <div class="ni"><UserRound size={17} /></div>
        <div>
          <b>{t('noLogin')}</b>
          <span>{t('noLoginHint')}</span>
        </div>
      </div>
    {/if}
  </div>

  {#if logged && fresh.why}
    <div class="warn" use:tip={fresh.tipText}><TriangleAlert size={13} />{fresh.why}</div>
  {/if}

  <!-- карточки в ряду одной высоты, кнопка всегда внизу -->
  <div class="grow"></div>
  <button class="btn lg block run" class:accent={accentRun} class:ghost={!accentRun} onclick={() => launch(st)}>
    {#if logged}<Play size={14} />{t('run')}{:else}<UserRound size={15} />{t('signIn')}{/if}
    {#if st.acc.admin}<span class="shield" use:tip={t('runAdmin')}><ShieldCheck size={15} /></span>{/if}
  </button>
</article>

<style>
  .card {
    position: relative; display: flex; flex-direction: column; padding: 18px 20px 20px; border-radius: 18px;
    background: var(--card); border: 1px solid var(--card-line); box-shadow: var(--card-shadow);
    transition: transform .25s var(--ease), border-color .25s, box-shadow .25s;
    animation: rise .5s var(--ease) both; animation-delay: var(--delay);
  }
  .card::before {
    content: ''; position: absolute; inset: -1px; border-radius: inherit; pointer-events: none; opacity: 0; transition: opacity .25s;
    background: linear-gradient(180deg, color-mix(in srgb, var(--c1) 9%, transparent), transparent 55%);
    border: 1px solid color-mix(in srgb, var(--c1) 55%, transparent); mask: linear-gradient(#000, transparent 85%);
  }
  .card:hover { transform: translateY(-3px); }
  .card:hover::before { opacity: 1; }
  @keyframes rise { from { opacity: 0; transform: translateY(14px); } }

  .top { display: flex; align-items: center; gap: 13px; }
  .avatar {
    position: relative; flex-shrink: 0; width: 44px; height: 44px; border-radius: 13px; display: grid; place-items: center;
    background: linear-gradient(135deg, var(--c1), var(--c2)); color: #fff; font-size: 18px; font-weight: 700;
    box-shadow: 0 6px 18px -6px var(--c1);
  }
  .dot { position: absolute; right: -3px; bottom: -3px; width: 14px; height: 14px; border-radius: 50%; border: 2.5px solid var(--card); transition: background .3s; }
  .dot.green { background: var(--green); }
  .dot.orange { background: var(--orange); }
  .dot.red { background: var(--red); }
  .dot.gray { background: var(--faint); }
  .who { flex: 1; min-width: 0; }
  .name-row { display: flex; align-items: center; gap: 8px; min-width: 0; }
  .name { font-size: 15.5px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .plan { flex-shrink: 0; padding: 1px 6px; border-radius: 5px; background: var(--plan-bg); color: var(--plan-text); font-size: 9.5px; font-weight: 700; letter-spacing: .03em; }
  .star { display: inline-flex; color: #f0a060; filter: drop-shadow(0 0 6px rgba(240, 160, 96, .5)); }
  .sub { display: flex; align-items: center; gap: 6px; margin-top: 3px; color: var(--muted); font-size: 12px; min-width: 0; }
  .px { display: inline-flex; color: var(--faint); }
  .email { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .more { align-self: flex-start; margin: -6px -10px 0 0; }

  .body { position: relative; margin-top: 20px; }
  .limits { display: flex; flex-direction: column; gap: 16px; }
  .limits.hidden { visibility: hidden; }
  .nologin {
    position: absolute; inset: 0; display: flex; align-items: center; gap: 12px; padding: 0 16px; border-radius: 14px;
    background: var(--inset); border: 1px solid var(--inset-line);
  }
  .ni { width: 38px; height: 38px; border-radius: 50%; display: grid; place-items: center; background: var(--inset-icon); color: var(--muted); flex-shrink: 0; }
  .nologin b { display: block; font-size: 13.5px; font-weight: 600; color: var(--text2); }
  .nologin span { display: block; font-size: 12px; color: var(--muted); margin-top: 2px; }

  .warn {
    display: flex; align-items: center; gap: 8px; margin-top: 14px; padding: 6px 10px; border-radius: 9px;
    background: var(--orange-bg); color: var(--orange); font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .warn :global(svg) { flex-shrink: 0; }
  .grow { flex: 1; }
  .run { margin-top: 18px; }
  .shield { display: inline-flex; margin-left: 2px; opacity: .85; }
</style>
