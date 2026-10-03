// Форматирование времени: «через 3 ч 12 мин», «сегодня в 20:00», «5 мин назад»
import { lang, t } from './i18n.svelte'

const pad = (n: number) => String(n).padStart(2, '0')
const hm = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}`
const day = (d: Date) => (lang.idx ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : `${pad(d.getDate())}.${pad(d.getMonth() + 1)}`)
const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()

export function fmtUntil(ms: number, now: number): string {
  const s = (ms - now) / 1000
  if (s < 60) return t('lessMin')
  const days = Math.floor(s / 86400)
  const hours = Math.floor((s % 86400) / 3600)
  const mins = Math.floor((s % 3600) / 60)
  if (days >= 1) return t('fmtD', days, hours)
  if (hours >= 1) return t('fmtH', hours, mins)
  return t('fmtM', mins)
}

export function fmtAt(ms: number, now: number): string {
  const d = new Date(ms)
  const diff = (startOfDay(d) - startOfDay(new Date(now))) / 86400000
  if (diff === 0) return t('today', hm(d))
  if (diff === 1) return t('tomorrow', hm(d))
  return t('onDate', day(d), hm(d))
}

export function fmtAgo(ms: number, now: number): string {
  const s = (now - ms) / 1000
  if (s < 10) return t('justNow')
  if (s < 60) return t('secAgo', Math.floor(s))
  if (s < 3600) return t('minAgo', Math.floor(s / 60))
  const d = new Date(ms)
  return t('atTime', startOfDay(d) === startOfDay(new Date(now)) ? hm(d) : `${day(d)} ${hm(d)}`)
}
