import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import { encodeCells, fit, parseAnsi } from './art'
import type { Art } from './art'

// The installed mod sits at <fife root>\config\mods\fife-symbol and the art
// at <fife root>\assets; a checkout keeps the same two levels apart.
const ART_PATH = '\\..\\..\\assets\\claude-symbol.ans'

const done = atom({ plugin: 'fife-symbol', key: 'isDone' } as const, false)

let mode = 'auto'
let reading: Promise<Art | null> | null = null

function isOff(value: string): boolean {
  return value === 'never' || value === '0' || value === 'off' || value === 'false'
}

function staysUp(value: string): boolean {
  return value === 'always' || value === '1' || value === 'on' || value === 'true'
}

async function load($: EngineInterface): Promise<Art | null> {
  if (reading) return reading
  reading = (async () => {
    mode = ((await $.env.get('CLAUDE_FIFE_SYMBOL')) ?? 'auto').toLowerCase()
    if (isOff(mode)) return null
    return parseAnsi(await $.fs.read(`${$.plugin.root}${ART_PATH}`))
  })().catch(() => null)
  return reading
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await load($)
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    // auto: the symbol is the welcome, so it lifts once the session begins.
    if (!staysUp(mode)) await update($, done, () => true)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.surface !== 'terminal' || e.props.hasSurvey) return next(e)
    if (await read($, done)) return next(e)
    const picture = await load($)
    if (!picture) return next(e)

    const fitted = fit(picture, e.props.bodyColumns, e.props.maxRows)
    if (fitted.columns < 8 || fitted.rows < 4) return next(e)

    const { Box, Raster } = $.ui.resolve(e)
    return (
      <Box justifyContent="center">
        <Raster
          key="symbol"
          columns={fitted.columns}
          rows={fitted.rows}
          cells={encodeCells(fitted)}
        />
      </Box>
    )
  })
}
