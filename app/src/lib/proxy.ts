// Разбор адреса прокси: host:port, host:port:user:pass, user:pass@host:port, http://user:pass@host:port
export type Normalized = { ok: true; url: string } | { ok: false; err: 'pxEmpty' | 'pxSocks' | 'pxFormat' }

const isPort = (p: string) => /^\d{1,5}$/.test(p)

export function normalizeProxy(input: string): Normalized {
  let s = input.trim()
  if (!s) return { ok: false, err: 'pxEmpty' }
  if (/^socks/i.test(s)) return { ok: false, err: 'pxSocks' }
  s = s.replace(/^https?:\/\//i, '').replace(/\/+$/, '')
  const at = s.lastIndexOf('@')
  if (at >= 0) {
    const cred = s.slice(0, at)
    const [host, port, ...rest] = s.slice(at + 1).split(':')
    if (cred && host && port && isPort(port) && !rest.length) return { ok: true, url: `http://${cred}@${host}:${port}` }
    return { ok: false, err: 'pxFormat' }
  }
  const p = s.split(':')
  if (p.length === 2 && p[0] && isPort(p[1])) return { ok: true, url: `http://${p[0]}:${p[1]}` }
  if (p.length >= 4 && p[0] && isPort(p[1])) {
    const user = encodeURIComponent(p[2])
    const pass = encodeURIComponent(p.slice(3).join(':'))
    return { ok: true, url: `http://${user}:${pass}@${p[0]}:${p[1]}` }
  }
  return { ok: false, err: 'pxFormat' }
}

/** host:port без логина и пароля — для показа в интерфейсе */
export function proxyHost(url: string): string {
  try {
    const u = new URL(url)
    return `${u.hostname}:${u.port}`
  } catch {
    return url
  }
}
