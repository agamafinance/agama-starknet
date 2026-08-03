// Empirical proof that PUBLIC Starknet Sepolia (chain_id SN_SEPOLIA) supports
// STRK20 / SNIP-36 in-protocol privacy proof verification.
//
// It submits an invoke v3 that carries the SNIP-36 `proof_facts` field to the
// live public gateway and reads the gateway's own reply. A non-privacy network
// would reject the field as unknown. Public Sepolia instead replies with the
// privacy protocol's own validation errors, which proves the feature is live.
//
// Run (needs a funded Sepolia account for the account nonce/estimate, no gas is
// spent because the tx is rejected at validation):
//   ADDR=0x... PK=0x... node proof-support-probe.mjs
// Defaults read the sncast agama_deployer account if ADDR/PK are unset.
//
// Requires starknet@10.0.0-beta.6 (the SNIP-36-aware release). Run it from a
// folder where that version resolves, e.g. the starknet-privacy e2e workspace.

import { RpcProvider, Account, CallData, num } from "starknet";
import fs from "node:fs";
import os from "node:os";

const RPC = process.env.RPC || "https://starknet-sepolia-rpc.publicnode.com";
const STRK = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

let ADDR = process.env.ADDR;
let PK = process.env.PK;
if (!ADDR || !PK) {
  const f = `${os.homedir()}/.starknet_accounts/starknet_open_zeppelin_accounts.json`;
  const a = JSON.parse(fs.readFileSync(f, "utf8"))["alpha-sepolia"]["agama_deployer"];
  ADDR = a.address;
  PK = a.private_key;
}

const provider = new RpcProvider({ nodeUrl: RPC, specVersion: "0.10.2" });
console.log("chainId:", await provider.getChainId(), " spec:", await provider.getSpecVersion());
const account = new Account({ provider, address: ADDR, signer: PK });

// A trivial, always-valid call so only the proof fields decide the outcome.
const call = { contractAddress: STRK, entrypoint: "transfer", calldata: CallData.compile([ADDR, "0x0", "0x0"]) };

const b = (s) => num.toHex(BigInt("0x" + Buffer.from(s).toString("hex")));
const mockFacts = [b("PROOF0"), b("VIRTUAL_SNOS"), "0x1", b("VIRTUAL_SNOS0"), "0x2", "0x3"];

const rb = (await account.estimateInvokeFee([call])).resourceBounds;

async function probe(label, detail) {
  try {
    const r = await account.execute([call], { resourceBounds: rb, tip: 0, ...detail });
    console.log(`\n[${label}] ACCEPTED tx ${r.transaction_hash}`);
  } catch (e) {
    const be = e?.baseError ? JSON.stringify(e.baseError) : (e?.message || String(e)).slice(0, 300);
    console.log(`\n[${label}] gateway said: ${be}`);
  }
}

// A: proof_facts without a proof. A privacy-aware gateway demands both together.
await probe("proof_facts only", { proofFacts: mockFacts });
// B: proof_facts with a malformed proof. A privacy-aware gateway parses and
//    verifies the proof, and rejects the invalid one (error code 69).
await probe("proof_facts + bad proof", { proofFacts: mockFacts, proof: "AAAAAA==" });

console.log(`
Expected on public Sepolia (verified 2026-08-03):
  [proof_facts only]      code 63  "Proof facts and proof must either both be present or both be absent"
  [proof_facts + bad proof] code 69  "The proof field in the invoke v3 transaction is invalid"
Both are privacy-protocol errors, so SNIP-36 proof verification is live on public Sepolia.`);
