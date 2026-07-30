import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs'
import { hash } from 'starknet'
import { cfg } from './config.mjs'
import { hex, provider } from './starknet.mjs'

// Contracts + events to index, with field decoders (order matches the Cairo event).
function targets() {
  const a = cfg.addresses
  const t = []
  if (a.vault) {
    t.push({ address: a.vault, name: 'Deposit', fields: ['user:addr', 'amount:u256'] })
    t.push({ address: a.vault, name: 'Redeem', fields: ['user:addr', 'amount:u256'] })
  }
  if (a.navOracle) {
    t.push({ address: a.navOracle, name: 'NavUpdated', fields: ['nav:u256', 'timestamp:u64', 'by_admin:bool'] })
  }
  if (a.allocationEngine) {
    t.push({ address: a.allocationEngine, name: 'Allocated', fields: ['pool_id:u32', 'amount:u256'] })
  }
  return t
}

function decode(fields, data) {
  const out = {}
  let i = 0
  for (const f of fields) {
    const [k, ty] = f.split(':')
    if (ty === 'u256') {
      out[k] = (BigInt(data[i]) + (BigInt(data[i + 1]) << 128n)).toString()
      i += 2
    } else if (ty === 'addr') {
      out[k] = hex(data[i]); i += 1
    } else if (ty === 'bool') {
      out[k] = BigInt(data[i]) === 1n; i += 1
    } else {
      out[k] = BigInt(data[i]).toString(); i += 1
    }
  }
  return out
}

const loadState = () =>
  existsSync(cfg.indexer.stateFile)
    ? JSON.parse(readFileSync(cfg.indexer.stateFile, 'utf8'))
    : { lastBlock: cfg.indexer.fromBlock }
const saveState = (s) => writeFileSync(cfg.indexer.stateFile, JSON.stringify(s))

async function pass() {
  const latest = await provider.getBlockNumber()
  const from = loadState().lastBlock
  let total = 0
  for (const t of targets()) {
    const key = hash.getSelectorFromName(t.name)
    let cont
    do {
      const page = await provider.getEvents({
        address: t.address,
        from_block: { block_number: from },
        to_block: { block_number: latest },
        keys: [[key]],
        chunk_size: 100,
        continuation_token: cont,
      })
      for (const ev of page.events) {
        const record = {
          block: ev.block_number,
          tx: ev.transaction_hash,
          address: t.address,
          event: t.name,
          ...decode(t.fields, ev.data),
        }
        appendFileSync(cfg.indexer.outFile, JSON.stringify(record) + '\n')
        console.log(`[indexer] ${t.name} @ block ${record.block}`, record)
        total += 1
      }
      cont = page.continuation_token
    } while (cont)
  }
  saveState({ lastBlock: latest + 1 })
  console.log(`[indexer] indexed ${total} event(s) up to block ${latest}`)
}

export async function runIndexer({ once = false } = {}) {
  await pass()
  if (!once) setInterval(() => pass().catch((e) => console.error('[indexer] error', e.message)), cfg.pollIntervalMs)
}
