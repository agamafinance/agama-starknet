// Real shielded deposit on PUBLIC Starknet Sepolia.
//
// This drives StarkWare's privacy SDK against the privacy pool deployed on
// public Sepolia, with a REAL Stwo proof from a transaction prover, and submits
// the proof-carrying invoke to the public sequencer. The sequencer verifies the
// proof in-protocol (SNIP-36) and the deposit lands as an encrypted note, on a
// public explorer (Voyager / Starkscan).
//
// Why this is possible on public testnet: proof-support-probe.mjs shows the
// public Sepolia gateway verifies STRK20 proofs (error codes 63 / 69). The only
// piece that is not on this machine is proof GENERATION: the Stwo prover needs a
// native x86-64 Linux host (it SIGILLs in Docker Desktop on Apple Silicon).
//
// Prerequisites:
//   1. A prover reachable at PROVER_URL, proving against Sepolia. On a Linux
//      host: `docker compose up` in this folder (see docker-compose.yml).
//   2. Screening: the pool at POOL was deployed with screener_public_key =
//      starkKey(0xCAFEBABE), the SDK test screener. Run the deposit-screening
//      interceptor with that key, OR redeploy the pool with your interceptor's
//      production screener key.
//   3. A funded Sepolia account (reads sncast agama_deployer by default).
//
// Run (from the starknet-privacy e2e workspace, where the SDK resolves):
//   PROVER_URL=http://<linux-host>:3000 npx tsx shield-sepolia.ts
//
import { RpcProvider, Account, constants, CallData, OutsideExecutionVersion } from "starknet";
import {
  createPrivateTransfers,
  ContractDiscoveryProvider,
} from "@starkware-libs/starknet-privacy-sdk";
import fs from "node:fs";
import os from "node:os";

const RPC = process.env.RPC || "https://starknet-sepolia-rpc.publicnode.com";
const POOL = process.env.POOL || "0x01b39392c749f030c60ae8d3ce6b1a382f290882b69584e7bec9755d48749c83";
const PROVER_URL = process.env.PROVER_URL || "http://localhost:3000";
// STRK is a convenient deposit token already held by the deployer on Sepolia.
const TOKEN = process.env.DEPOSIT_TOKEN || "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";
const AMOUNT = BigInt(process.env.AMOUNT || String(10n ** 16n)); // 0.01 token
const VIEWING_KEY = BigInt(process.env.VIEWING_KEY || "0xA11CE");
const BUFFER = 11; // proof block must be <= current - STORED_BLOCK_HASH_BUFFER (10)

function account(provider: RpcProvider): Account {
  const addr = process.env.ADDR;
  const pk = process.env.PK;
  if (addr && pk) return new Account({ provider, address: addr, signer: pk });
  const f = `${os.homedir()}/.starknet_accounts/starknet_open_zeppelin_accounts.json`;
  const a = JSON.parse(fs.readFileSync(f, "utf8"))["alpha-sepolia"]["agama_deployer"];
  return new Account({ provider, address: a.address, signer: a.private_key });
}

async function main() {
  const provider = new RpcProvider({ nodeUrl: RPC, specVersion: "0.10.2" });
  const chainId = await provider.getChainId();
  if (chainId !== constants.StarknetChainId.SN_SEPOLIA) throw new Error(`not SN_SEPOLIA: ${chainId}`);
  const acc = account(provider);
  console.log(`account ${acc.address}`);
  console.log(`pool    ${POOL}`);
  console.log(`prover  ${PROVER_URL}`);

  const transfers = createPrivateTransfers({
    account: { address: acc.address, signer: acc.signer },
    viewingKeyProvider: { getViewingKey: async () => VIEWING_KEY },
    // Config object -> the SDK builds a ProvingServiceProofProvider that calls
    // the real prover's starknet_proveTransaction against Sepolia.
    provingProvider: { url: PROVER_URL, chainId, nodeUrl: RPC },
    discoveryProvider: new ContractDiscoveryProvider(POOL),
    poolContractAddress: POOL,
  });

  // Approve the pool to pull the deposit, then build the shielded deposit and
  // get back the pool call plus its real proof + proof_facts.
  console.log(`approving ${AMOUNT} of ${TOKEN} to the pool`);
  const approve = await acc.execute([
    { contractAddress: TOKEN, entrypoint: "approve", calldata: CallData.compile([POOL, AMOUNT, 0n]) },
  ]);
  await provider.waitForTransaction(approve.transaction_hash);

  console.log("building shielded deposit + proving (this is the heavy Stwo step)...");
  const { callAndProof } = await transfers.alice
    .build({ autoRegister: true, autoSetup: true, autoDiscover: { notes: "refresh", channels: "refresh" } })
    .with(TOKEN, (t: any) => t.deposit({ amount: AMOUNT }))
    .surplusTo(acc.address)
    .execute();

  // The proof embeds the block it was proven against; the sequencer requires
  // proof_block <= current - 10. Wait for Sepolia to advance past that.
  const provenAt = await provider.getBlockNumber();
  console.log(`proof ready at block ${provenAt}; waiting for +${BUFFER} blocks of maturity`);
  while ((await provider.getBlockNumber()) < provenAt + BUFFER) {
    await new Promise((r) => setTimeout(r, 15000));
  }

  // Submit the proof-carrying invoke via SNIP-9 outside execution (a relayer
  // pattern: keeps the depositor address off the pool call for unlinkability).
  const now = Math.floor(Date.now() / 1000);
  const outsideTx = await acc.getOutsideTransaction(
    { caller: acc.address, execute_after: now - 3600, execute_before: now + 3600 },
    callAndProof.call,
    OutsideExecutionVersion.V2,
  );
  const resp = await acc.executeFromOutside(outsideTx, {
    proofFacts: callAndProof.proof.proofFacts,
    proof: callAndProof.proof.data,
  });
  console.log(`submitted: ${resp.transaction_hash}`);
  const receipt = await provider.waitForTransaction(resp.transaction_hash);
  console.log(`status: ${receipt.isSuccess?.() ? "ACCEPTED" : "reverted"}`);
  console.log(`voyager: https://sepolia.voyager.online/tx/${resp.transaction_hash}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
