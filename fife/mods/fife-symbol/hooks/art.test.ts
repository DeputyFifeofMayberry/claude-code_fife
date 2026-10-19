import { expect, test } from 'claude-code/testing'

import { DEFAULT_COLOR, encodeCells, fit, parseAnsi, xtermColor } from './art'

test('parses SGR colors and glyphs into a padded cell grid', () => {
  const art = parseAnsi('\x1b[38;5;196m█\x1b[48;5;236m▀\x1b[0m\n\x1b[38;5;222m▄\x1b[39m')

  expect(art.rows).toBe(2)
  expect(art.columns).toBe(2)
  expect(Array.from(art.cells)).toEqual([
    0x2588, xtermColor(196), DEFAULT_COLOR,
    0x2580, xtermColor(196), xtermColor(236),
    0x2584, xtermColor(222), DEFAULT_COLOR,
    0x20, DEFAULT_COLOR, DEFAULT_COLOR,
  ])
})

test('maps the 256-color palette to RGB', () => {
  expect(xtermColor(16)).toBe(0x000000)
  expect(xtermColor(196)).toBe(0xff0000)
  expect(xtermColor(231)).toBe(0xffffff)
  expect(xtermColor(236)).toBe(0x303030)
  expect(xtermColor(255)).toBe(0xeeeeee)
})

test('fits within the band and never enlarges', () => {
  const art = parseAnsi('█▀▄\n▄▀█\n███\n▀▀▀')

  expect(fit(art, 80, 40)).toBe(art)

  // 3x4 shrunk to a 2x2 box keeps its aspect: one column, two rows.
  const small = fit(art, 2, 2)
  expect(small.columns).toBe(1)
  expect(small.rows).toBe(2)
  expect(small.cells.length).toBe(1 * 2 * 3)
})

test('encodes columns * rows u32 triplets as padded base64', () => {
  const art = parseAnsi('█')

  expect(encodeCells(art)).toBe('iCUAAAAAAAEAAAAB')
})
