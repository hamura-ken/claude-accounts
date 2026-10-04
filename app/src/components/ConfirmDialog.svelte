<script lang="ts">
  import { untrack } from 'svelte'
  import { app } from '../lib/store.svelte'
  import { t } from '../lib/i18n.svelte'
  import Modal from './Modal.svelte'

  let { req }: { req: NonNullable<typeof app.confirm> } = $props()
  // после закрытия (app.confirm = null) prop req станет null — запоминаем запрос сразу
  const r = untrack(() => req)

  function done(v: boolean) {
    r.resolve(v)
    app.confirm = null
  }
</script>

<Modal title={r.title} sub={r.text} width={480} onclose={() => done(false)}>
  <div class="actions">
    {#if !r.info}<button class="btn ghost" onclick={() => done(false)}>{t('cancel')}</button>{/if}
    <!-- svelte-ignore a11y_autofocus -->
    <button class="btn" class:danger={r.danger} class:accent={!r.danger} autofocus onclick={() => done(true)}>{r.ok}</button>
  </div>
</Modal>

<style>
  .actions { display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; }
  .actions .btn { min-width: 110px; }
</style>
