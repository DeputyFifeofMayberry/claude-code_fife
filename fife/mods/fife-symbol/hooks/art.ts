// Turns the claude-fife .ans artwork into the cell grid a Raster draws:
// row-major little-endian u32 triplets [codePoint, foreground, background],
// colors 0x00RRGGBB and 0x01000000 for the terminal's default.

export type Cell = { cp: number; fg: number; bg: number }
export type Art = { columns: number; rows: number; cells: Uint32Array }

export const DEFAULT_COLOR = 0x01000000

// The xterm 256-color palette the artwork's SGR sequences index.
const BASE_16 = [
  0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xc0c0c0,
  0x808080, 0xff0000, 0x00ff00, 0xffff00, 0x0000ff, 0xff00ff, 0x00ffff, 0xffffff,
]
const CUBE = [0, 95, 135, 175, 215, 255]
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

export function xtermColor(index: number): number {
  const n = Math.max(0, Math.min(255, Math.floor(index)))
  if (n < 16) return BASE_16[n] ?? 0
  if (n < 232) {
    const m = n - 16
    const r = CUBE[Math.floor(m / 36)] ?? 0
    const g = CUBE[Math.floor(m / 6) % 6] ?? 0
    const b = CUBE[m % 6] ?? 0
    return (r << 16) | (g << 8) | b
  }
  const v = 8 + 10 * (n - 232)
  return (v << 16) | (v << 8) | v
}

export function parseAnsi(text: string): Art {
  const rows: Cell[][] = []
  let row: Cell[] = []
  let fg = DEFAULT_COLOR
  let bg = DEFAULT_COLOR

  const applySgr = (params: string): void => {
    const parts = params.split(';').map(p => (p === '' ? 0 : Number(p)))
    for (let k = 0; k < parts.length; k++) {
      const p = parts[k] ?? 0
      if (p === 0) {
        fg = DEFAULT_COLOR
        bg = DEFAULT_COLOR
      } else if (p === 39) {
        fg = DEFAULT_COLOR
      } else if (p === 49) {
        bg = DEFAULT_COLOR
      } else if (p === 38 || p === 48) {
        const kind = parts[k + 1]
        const color = kind === 5 ? xtermColor(parts[k + 2] ?? 0) : undefined
        if (color !== undefined) {
          if (p === 38) fg = color
          else bg = color
        }
        k += kind === 5 ? 2 : 4
      }
    }
  }

  for (let i = 0; i < text.length; ) {
    const ch = text.charCodeAt(i)
    if (ch === 0x1b && text.charCodeAt(i + 1) === 0x5b) {
      let j = i + 2
      while (j < text.length) {
        const c = text.charCodeAt(j)
        if (c >= 0x40 && c <= 0x7e) break
        j++
      }
      if (text.charCodeAt(j) === 0x6d) applySgr(text.slice(i + 2, j))
      i = j + 1
      continue
    }
    if (ch === 0x0a) {
      rows.push(row)
      row = []
      i++
      continue
    }
    if (ch === 0x0d) {
      i++
      continue
    }
    const cp = text.codePointAt(i) ?? 0x20
    row.push({ cp, fg, bg })
    i += cp > 0xffff ? 2 : 1
  }
  rows.push(row)

  // A trailing newline leaves one empty row; drop blank rows from the end.
  while (rows.length > 0) {
    const last = rows[rows.length - 1] ?? []
    if (last.some(c => c.cp !== 0x20 || c.bg !== DEFAULT_COLOR)) break
    rows.pop()
  }

  const columns = rows.reduce((widest, r) => Math.max(widest, r.length), 0)
  const cells = new Uint32Array(columns * rows.length * 3)
  for (let y = 0; y < rows.length; y++) {
    const r = rows[y] ?? []
    for (let x = 0; x < columns; x++) {
      const c = r[x] ?? { cp: 0x20, fg: DEFAULT_COLOR, bg: DEFAULT_COLOR }
      const at = (y * columns + x) * 3
      cells[at] = c.cp
      cells[at + 1] = c.fg
      cells[at + 2] = c.bg
    }
  }
  return { columns, rows: rows.length, cells }
}

// Shrinks the art to fit the band, never enlarging it, sampling the nearest
// source cell so every glyph and both colors survive.
export function fit(art: Art, maxColumns: number, maxRows: number): Art {
  const maxC = Math.max(1, Math.floor(maxColumns))
  const maxR = Math.max(1, Math.floor(maxRows))
  const scale = Math.min(1, maxC / art.columns, maxR / art.rows)
  const columns = Math.max(1, Math.min(art.columns, Math.floor(art.columns * scale)))
  const rows = Math.max(1, Math.min(art.rows, Math.floor(art.rows * scale)))
  if (columns === art.columns && rows === art.rows) return art

  const cells = new Uint32Array(columns * rows * 3)
  for (let y = 0; y < rows; y++) {
    const sy = Math.min(art.rows - 1, Math.floor((y * art.rows) / rows))
    for (let x = 0; x < columns; x++) {
      const sx = Math.min(art.columns - 1, Math.floor((x * art.columns) / columns))
      const from = (sy * art.columns + sx) * 3
      const to = (y * columns + x) * 3
      cells[to] = art.cells[from] ?? 0x20
      cells[to + 1] = art.cells[from + 1] ?? DEFAULT_COLOR
      cells[to + 2] = art.cells[from + 2] ?? DEFAULT_COLOR
    }
  }
  return { columns, rows, cells }
}

// The Raster `cells` string: standard padded base64 of the triplets.
export function encodeCells(art: Art): string {
  const bytes = new Uint8Array(art.columns * art.rows * 12)
  const view = new DataView(bytes.buffer)
  for (let i = 0; i < art.cells.length; i++) view.setUint32(i * 4, art.cells[i] ?? 0, true)
  let out = ''
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i] ?? 0
    const b = bytes[i + 1]
    const c = bytes[i + 2]
    const n = (a << 16) | ((b ?? 0) << 8) | (c ?? 0)
    out += B64[(n >> 18) & 63] ?? '='
    out += B64[(n >> 12) & 63] ?? '='
    out += b === undefined ? '=' : B64[(n >> 6) & 63] ?? '='
    out += c === undefined ? '=' : B64[n & 63] ?? '='
  }
  return out
}
