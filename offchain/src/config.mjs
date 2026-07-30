import { existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

// Minimal .env loader (no dependency): populate process.env from ../.env if present.
function loadDotEnv() {
  const path = fileURLToPath(new URL('../.env', import.meta.url))
  if (!existsSync(path)) return
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/)
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '')
  }
}
loadDotEnv()

const env = (k, d) => process.env[k] ?? d
const p = (rel) => fileURLToPath(new URL(rel, import.meta.url))

export const cfg = {
  rpcUrl: env('RPC_URL', 'https://starknet-sepolia-rpc.publicnode.com'),
  pollIntervalMs: Number(env('POLL_INTERVAL_MS', '60000')),
  reporterAddress: env('REPORTER_ADDRESS', ''),
  reporterKey: env('REPORTER_PRIVATE_KEY', ''),
  addresses: {
    navOracle: env('NAV_ORACLE', ''),
    allocationEngine: env('ALLOCATION_ENGINE', ''),
    vault: env('VAULT', ''),
    withdrawalQueue: env('WITHDRAWAL_QUEUE', ''),
    agusd: env('AGUSD', ''),
    usdc: env('USDC', '0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343'),
  },
  navReportsFile: env('NAV_REPORTS_FILE', p('../nav-reports.json')),
  indexer: {
    fromBlock: Number(env('INDEXER_FROM_BLOCK', '0')),
    stateFile: env('INDEXER_STATE_FILE', p('../.indexer-state.json')),
    outFile: env('INDEXER_OUT_FILE', p('../events.jsonl')),
  },
}
