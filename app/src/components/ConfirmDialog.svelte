<script lang="ts">
  import { app } from '../lib/store.svelte'
  import { t } from '../lib/i18n.svelte'
  import Modal from './Modal.svelte'

  let { req }: { req: NonNullable<typeof app.confirm> } = $props()

  function done(v: boolean) {
    app.confirm = null
    req.resolve(v)
  }
</script>

<Modal title={req.title} sub={req.text} width={480} onclose={() => done(false)}>
  <div class="actions">
    {#if !req.info}<button class="btn ghost" onclick={() => done(false)}>{t('cancel')}</button>{/if}
    <!-- svelte-ignore a11y_autofocus -->
    <button class="btn" class:danger={req.danger} class:accent={!req.danger} autofocus onclick={() => done(true)}>{req.ok}</button>
  </div>
</Modal>

<style>
  .actions { display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; }
  .actions .btn { min-width: 110px; }
</style>
