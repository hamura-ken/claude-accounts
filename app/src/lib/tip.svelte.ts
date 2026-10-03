// Подсказки в стиле приложения вместо системных: use:tip={'текст'}
export const tipState = $state({ text: '', x: 0, y: 0, below: false, show: false })

let timer: number | undefined
let owner: HTMLElement | null = null

function place(el: HTMLElement) {
  const r = el.getBoundingClientRect()
  tipState.x = r.left + r.width / 2
  tipState.below = r.top < 60
  tipState.y = tipState.below ? r.bottom + 8 : r.top - 8
}

export function tip(el: HTMLElement, text: string | null | undefined) {
  let current = text
  const enter = () => {
    if (!current) return
    owner = el
    clearTimeout(timer)
    timer = window.setTimeout(() => {
      place(el)
      tipState.text = current ?? ''
      tipState.show = true
    }, tipState.show ? 0 : 450)
  }
  const leave = () => {
    clearTimeout(timer)
    if (owner === el) tipState.show = false
  }
  el.addEventListener('mouseenter', enter)
  el.addEventListener('mouseleave', leave)
  el.addEventListener('mousedown', leave)
  return {
    update(t: string | null | undefined) {
      current = t
      // открытая подсказка обновляется на лету (например, таймер «следующее через N сек»)
      if (owner === el && tipState.show) {
        if (t) tipState.text = t
        else tipState.show = false
      }
    },
    destroy() {
      leave()
      el.removeEventListener('mouseenter', enter)
      el.removeEventListener('mouseleave', leave)
      el.removeEventListener('mousedown', leave)
    },
  }
}
