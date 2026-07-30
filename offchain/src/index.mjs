import { pushNav } from './nav-backend.mjs'
import { runIndexer } from './indexer.mjs'
import { runKeeper } from './keeper.mjs'

const [, , cmd, ...rest] = process.argv
const once = rest.includes('--once')

const commands = {
  nav: () => pushNav(),
  keeper: () => runKeeper({ once }),
  indexer: () => runIndexer({ once }),
}

const run = commands[cmd]
if (!run) {
  console.error('usage: node src/index.mjs <nav|keeper|indexer> [--once]')
  process.exit(1)
}
run().catch((e) => {
  console.error(e)
  process.exit(1)
})
