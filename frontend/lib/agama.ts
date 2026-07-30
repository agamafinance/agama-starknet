import { RpcProvider, uint256, type Call } from "starknet";
import { RPC_URL, ADDRESSES } from "./config";

export const provider = new RpcProvider({ nodeUrl: RPC_URL });

export async function readU256(
  address: string,
  entrypoint: string,
  calldata: string[] = [],
): Promise<bigint> {
  if (!address) return 0n;
  // Read on the "latest" block: PublicNode (RPC 0.10) rejects the default
  // "pending" block tag that starknet.js v6 would otherwise use.
  const res: any = await provider.callContract(
    { contractAddress: address, entrypoint, calldata },
    "latest",
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

// Stake agUSD into sagUSD (approve, then stake).
export function stakeCalls(amount: bigint): Call[] {
  return [
    {
      contractAddress: ADDRESSES.agusd,
      entrypoint: "approve",
      calldata: [ADDRESSES.sagusd, ...u256Calldata(amount)],
    },
    {
      contractAddress: ADDRESSES.sagusd,
      entrypoint: "stake",
      calldata: u256Calldata(amount),
    },
  ];
}

// USDC / agUSD / sagUSD use 6 decimals.
export const toUnits = (v: string): bigint => {
  const n = parseFloat(v || "0");
  if (!isFinite(n) || n <= 0) return 0n;
  return BigInt(Math.round(n * 1e6));
};
export const fromUnits = (v: bigint): string =>
  (Number(v) / 1e6).toLocaleString(undefined, { maximumFractionDigits: 6 });
