import { cfg } from './config.mjs'
import { account, provider, read, readU256, u256 } from './starknet.mjs'

async function tick() {
  const { navOracle, vault, withdrawalQueue } = cfg.addresses

  // 1. NAV oracle freshness — the vault/allocation block while stale.
  if (navOracle) {
    const [stale] = await read(navOracle, 'is_stale')
    console.log(`[keeper] oracle stale=${BigInt(stale) === 1n}`)
    if (BigInt(stale) === 1n) console.log('[keeper] -> feed is stale, run `npm run nav` to refresh')
  }

  // 2. Settle the withdrawal queue against the vault reserve (FIFO).
  if (withdrawalQueue && vault) {
    const [pending] = await read(withdrawalQueue, 'pending')
    if (BigInt(pending) > 0n) {
      const reserve = readU256(await read(vault, 'reserve'))
      console.log(`[keeper] queue pending=${pending}, reserve=${reserve} -> process`)
      const acc = account()
      const { transaction_hash } = await acc.execute({
        contractAddress: withdrawalQueue,
        entrypoint: 'process',
        calldata: [...u256(reserve)],
      })
      console.log(`[keeper] process tx ${transaction_hash}`)
      await provider.waitForTransaction(transaction_hash)
    } else {
      console.log('[keeper] withdrawal queue empty')
    }
  }
}

export async function runKeeper({ once = false } = {}) {
  await tick()
  if (once) return
  setInterval(() => tick().catch((e) => console.error('[keeper] error', e.message)), cfg.pollIntervalMs)
}
