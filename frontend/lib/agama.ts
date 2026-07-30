import { RpcProvider, uint256, type Call } from "starknet";
import { RPC_URL, ADDRESSES, POOLS } from "./config";

export const provider = new RpcProvider({ nodeUrl: RPC_URL });

// Block identifier for reads. Reads default to "latest"; the vault snapshot pins
// every call to ONE explicit block number so NAV and supply — updated together in a
// single deposit tx — are never read across a block boundary (which would show a
// phantom price spike). PublicNode (RPC 0.10) also rejects the "pending" tag.
export type Block = number | "latest";

export async function readFelt(
  address: string,
  entrypoint: string,
  calldata: string[] = [],
  block: Block = "latest",
): Promise<bigint> {
  if (!address) return 0n;
  const res: any = await provider.callContract(
    { contractAddress: address, entrypoint, calldata },
    block,
  );
  const arr: string[] = Array.isArray(res) ? res : res.result;
  return BigInt(arr[0]);
}

export async function readU256(
  address: string,
  entrypoint: string,
  calldata: string[] = [],
  block: Block = "latest",
): Promise<bigint> {
  if (!address) return 0n;
  const res: any = await provider.callContract(
    { contractAddress: address, entrypoint, calldata },
    block,
  );
  const arr: string[] = Array.isArray(res) ? res : res.result;
  return uint256.uint256ToBN({ low: arr[0], high: arr[1] });
}

export function u256Calldata(v: bigint): string[] {
  const u = uint256.bnToUint256(v);
  return [u.low.toString(), u.high.toString()];
}

// Deposit USDC into the vault (approve, then deposit) as a single multicall.
export function depositCalls(amount: bigint): Call[] {
  return [
    {
      contractAddress: ADDRESSES.usdc,
      entrypoint: "approve",
      calldata: [ADDRESSES.vault, ...u256Calldata(amount)],
    },
    {
      contractAddress: ADDRESSES.vault,
      entrypoint: "deposit",
      calldata: u256Calldata(amount),
    },
  ];
}

// Redeem agUSD back into USDC (vault burns the caller's agUSD as minter — no approve).
export function redeemCalls(amount: bigint): Call[] {
  return [
    {
      contractAddress: ADDRESSES.vault,
      entrypoint: "redeem",
      calldata: u256Calldata(amount),
    },
  ];
}

// --- Live NAV / share-price model -------------------------------------------
// agUSD's price is (vault idle + Σ pool value) / supply. Each pool's value grows
// with time at its APR, so we read the raw pool state once and project the value
// forward every second on the client using the exact on-chain formula
// (principal + accrued + principal*apr*dt/(BPS*year)). No rounding, no polling per
// tick — the number ticks smoothly and matches what the contract would return.

const YEAR = 31536000n;
const BPS = 10000n;

export type PoolState = {
  address: string;
  label: string;
  sector: string;
  principal: bigint;
  accrued: bigint;
  aprBps: bigint;
  lastTs: bigint;
};

export type VaultState = {
  idle: bigint;
  supply: bigint;
  pools: PoolState[];
};

export async function readPoolState(
  address: string,
  label: string,
  sector: string,
  block: Block = "latest",
): Promise<PoolState> {
  const [principal, accrued, aprBps, lastTs] = await Promise.all([
    readU256(address, "principal", [], block),
    readU256(address, "accrued", [], block),
    readFelt(address, "apr_bps", [], block),
    readFelt(address, "last_accrual", [], block),
  ]);
  return { address, label, sector, principal, accrued, aprBps, lastTs };
}

// One consistent snapshot: pin every read to the same block so NAV (idle + pools) and
// supply are always from the same on-chain state — no phantom price on a deposit.
export async function readVaultState(): Promise<VaultState> {
  const block = await provider.getBlockNumber();
  const [idle, supply, pools] = await Promise.all([
    readU256(ADDRESSES.vault, "idle", [], block),
    readU256(ADDRESSES.agusd, "total_supply", [], block),
    Promise.all(POOLS.map((p) => readPoolState(p.address, p.label, p.sector, block))),
  ]);
  return { idle, supply, pools };
}

// Projected pool value at `nowSec` (matches LendingPool.total_value on-chain).
export function projectPoolValue(pool: PoolState, nowSec: bigint): bigint {
  const dt = nowSec > pool.lastTs ? nowSec - pool.lastTs : 0n;
  const pending = (pool.principal * pool.aprBps * dt) / (BPS * YEAR);
  return pool.principal + pool.accrued + pending;
}

// Projected NAV (total assets under management) at `nowSec`.
export function projectNav(state: VaultState, nowSec: bigint): bigint {
  let nav = state.idle;
  for (const p of state.pools) nav += projectPoolValue(p, nowSec);
  return nav;
}

// USDC and agUSD both use 6 decimals.
export const toUnits = (v: string): bigint => {
  const n = parseFloat(v || "0");
  if (!isFinite(n) || n <= 0) return 0n;
  return BigInt(Math.round(n * 1e6));
};

// Exact fixed-precision formatting of a 6-decimal token amount (never rounds away
// the yield): 1_000_231 -> "1.000231". `dp` fractional digits shown.
export function amountStr(v: bigint, dp = 6): string {
  const neg = v < 0n;
  const x = neg ? -v : v;
  const base = 1_000_000n;
  const int = x / base;
  const frac = (x % base).toString().padStart(6, "0").slice(0, dp);
  return (neg ? "-" : "") + int.toString() + (dp > 0 ? "." + frac : "");
}
export const fromUnits = (v: bigint): string => amountStr(v, 6);

// Exact ratio num/den to `dp` decimals — used for the share price (USDC per agUSD).
export function ratioStr(num: bigint, den: bigint, dp = 6): string {
  if (den === 0n) return "1." + "0".repeat(dp);
  const scale = 10n ** BigInt(dp);
  const scaled = (num * scale) / den;
  const int = scaled / scale;
  const frac = (scaled % scale).toString().padStart(dp, "0");
  return int.toString() + "." + frac;
}

// USDC value of `shares` agUSD at a projected NAV.
export function sharesToUsdc(shares: bigint, nav: bigint, supply: bigint): bigint {
  if (supply === 0n) return 0n;
  return (shares * nav) / supply;
}

// High-resolution share price (USDC per agUSD) to `dp` decimals. Projects each pool's
// yield at fine (sub-atomic) resolution so the price ticks smoothly every second,
// while staying exactly consistent with the on-chain integer NAV at block granularity.
export function sharePriceStr(state: VaultState, nowSec: bigint, dp = 8): string {
  if (state.supply === 0n) return "1." + "0".repeat(dp);
  const K = 1_000_000n; // extra precision on the pending term
  let navK = K * state.idle;
  for (const p of state.pools) {
    const dt = nowSec > p.lastTs ? nowSec - p.lastTs : 0n;
    navK += K * (p.principal + p.accrued) + (p.principal * p.aprBps * dt * K) / (BPS * YEAR);
  }
  const scale = 10n ** BigInt(dp);
  const scaled = (navK * scale) / (state.supply * K);
  const int = scaled / scale;
  const frac = (scaled % scale).toString().padStart(dp, "0");
  return int.toString() + "." + frac;
}

// Effective APR earned by agUSD, weighted over the whole NAV (so idle reserve, which
// earns nothing until allocated, correctly drags the rate down). This is the real rate
// the share price grows at: Σ(principal_i * apr_i) / NAV. aprBps is basis points.
export function blendedAprPct(state: VaultState, nav: bigint): string {
  let num = 0n;
  for (const p of state.pools) num += p.principal * p.aprBps;
  if (nav === 0n) return "0.00";
  const pct = Number(num) / Number(nav) / 100;
  return pct.toFixed(2);
}
