import { existsSync, readFileSync } from 'node:fs'
import { cfg } from './config.mjs'
import { account, provider, read, readU256, u256 } from './starknet.mjs'

// Reconcile per-originator reported values into a single NAV figure.
export function reconcile(reports) {
  return reports.reduce((sum, r) => sum + BigInt(r.value), 0n)
}

export function loadReports() {
  if (existsSync(cfg.navReportsFile)) return JSON.parse(readFileSync(cfg.navReportsFile, 'utf8'))
  // demo fallback: a single originator report
  return [{ originator: 'qiro', value: '1000000' }]
}

// Reconcile originator reports and push the signed NAV on-chain (push_nav).
export async function pushNav() {
  const oracle = cfg.addresses.navOracle
  if (!oracle) throw new Error('NAV_ORACLE address required')

  const reports = loadReports()
  const nav = reconcile(reports)
  const ts = Math.floor(Date.now() / 1000)
  const current = readU256(await read(oracle, 'nav'))
  console.log(
    `[nav] reconciled ${reports.length} report(s) -> NAV=${nav} (on-chain=${current}); push @ ts=${ts}`,
  )

  const acc = account()
  const { transaction_hash } = await acc.execute({
    contractAddress: oracle,
    entrypoint: 'push_nav',
    calldata: [...u256(nav), String(ts)],
  })
  console.log(`[nav] push_nav tx ${transaction_hash}`)
  await provider.waitForTransaction(transaction_hash)
  console.log('[nav] accepted')
  return transaction_hash
}
