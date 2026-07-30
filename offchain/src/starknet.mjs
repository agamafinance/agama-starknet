import { Account, RpcProvider, uint256 } from 'starknet'
import { cfg } from './config.mjs'

export const provider = new RpcProvider({ nodeUrl: cfg.rpcUrl })

export function account() {
  if (!cfg.reporterAddress || !cfg.reporterKey) {
    throw new Error('REPORTER_ADDRESS and REPORTER_PRIVATE_KEY are required for writes')
  }
  return new Account(provider, cfg.reporterAddress, cfg.reporterKey)
}

// callContract returns string[] (recent starknet.js) or { result } (older).
export async function read(address, entrypoint, calldata = []) {
  const res = await provider.callContract({ contractAddress: address, entrypoint, calldata })
  return Array.isArray(res) ? res : res.result
}

export const u256 = (v) => {
  const x = uint256.bnToUint256(BigInt(v))
  return [String(x.low), String(x.high)]
}
export const readU256 = ([low, high]) => uint256.uint256ToBN({ low, high })
export const hex = (v) => '0x' + BigInt(v).toString(16)
