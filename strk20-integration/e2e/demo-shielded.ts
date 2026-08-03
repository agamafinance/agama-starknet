// Agama STRK20 shielded demo (local devnet, mock prover, nothing from StarkWare).
// A user deposits USDC anonymously through Starknet's real privacy pool and receives
// yield-bearing agUSD into an encrypted note, unlinked from their address.
//
// Run:  npx tsx demo-shielded.ts   (with the e2e prerequisites built)
import { Devnet } from "@starkware-libs/starknet-privacy-sdk/testing";
import { Open } from "@starkware-libs/starknet-privacy-sdk";
import { createE2eTestEnv } from "./src/harness.js";
import { deployAgamaStack } from "./src/agama-setup.js";
import { u256Calldata } from "./src/utils.js";

const ONE = 10n ** 18n;
const fmt = (v: bigint) => (Number(v) / 1e18).toFixed(4);
const line = (s = "") => console.log(s);
const step = (n: number, s: string) => console.log(`\n[${n}] ${s}`);

async function main() {
  line("======================================================================");
  line("  AGAMA x STRK20   shielded deposit into yield-bearing agUSD (local)");
  line("  Real StarkWare privacy pool + mock prover on a local devnet.");
  line("======================================================================");

  const devnet = new Devnet();
  const env = await createE2eTestEnv(devnet, { indexer: { logFile: "demo-indexer.log" } });
  const { env: de, transfers } = env;
  try {
    step(1, "Deploy the Agama stack (USDC, agUSD, vault, STRK20 anonymizer)");
    const agama = await deployAgamaStack(de.admin, de.node);
    line(`    agUSD   ${agama.agusd.slice(0, 14)}...`);
    line(`    vault   ${agama.vault.slice(0, 14)}...`);
    line(`    adapter ${agama.adapter.slice(0, 14)}...`);
    line(`    LP (Alice) ${de.alice.address.slice(0, 14)}...`);

    const deposit = 100n * ONE;
    const lend = 60n * ONE;

    // Fund Alice with USDC and let the privacy pool pull it.
    const mint = await de.admin.execute({
      contractAddress: agama.usdToken,
      entrypoint: "mint",
      calldata: [de.alice.address, ...u256Calldata(deposit)],
    });
    await de.node.waitForTransaction(mint.transaction_hash);
    const approve = await de.alice.execute({
      contractAddress: agama.usdToken,
      entrypoint: "approve",
      calldata: [de.privacy.address, deposit, 0n],
    });
    await de.node.waitForTransaction(approve.transaction_hash);

    step(2, `Alice shields ${fmt(deposit)} USDC into the privacy pool`);
    const { callAndProof: depositCall } = await transfers.alice
      .build({
        autoRegister: true,
        autoSetup: true,
        autoDiscover: { notes: "refresh", channels: "refresh" },
      })
      .with(agama.usdToken, (t) => t.deposit({ amount: deposit }))
      .surplusTo(de.alice.address)
      .execute();
    await devnet.executeOutside(depositCall);
    await env.indexer.waitForBlock(devnet.url);
    line("    USDC is now inside the shielded pool as an encrypted note.");

    step(3, `Lend ${fmt(lend)}: the anonymizer deposits into the vault, agUSD comes back into a note`);
    const { callAndProof: lendCall } = await transfers.alice
      .build({
        autoSetup: true,
        autoSelectNotes: "all",
        autoDiscover: { notes: "refresh", channels: "refresh" },
      })
      .with(agama.usdToken)
      .withdraw({ recipient: agama.adapter, amount: lend })
      .surplusTo(de.alice.address, false)
      .with(agama.agusd)
      .transfer({ recipient: de.alice.address, amount: Open })
      .done()
      .invoke((args) => {
        const openNote = args.openNotes[0];
        if (!openNote) throw new Error("no open note");
        return {
          contractAddress: agama.adapter,
          calldata: [0n, agama.usdToken, agama.agusd, lend, 0n, openNote.noteId],
        };
      })
      .execute();
    await devnet.executeOutside(lendCall);
    await env.indexer.waitForBlock(devnet.url);

    step(4, "Alice discovers her shielded agUSD note (only she can, via her viewing key)");
    const { notes } = await transfers.alice.discoverNotes();
    const agusdNotes = notes.get(BigInt(agama.agusd)) ?? [];
    const agusdAmount = agusdNotes.reduce((s, n) => s + n.amount, 0n);
    line(`    Shielded agUSD in note: ${fmt(agusdAmount)} agUSD  (yield-bearing)`);

    step(5, "Redeem: agUSD back to USDC into a note");
    const { callAndProof: redeemCall } = await transfers.alice
      .build({
        autoSetup: true,
        autoSelectNotes: "all",
        autoDiscover: { notes: "refresh", channels: "refresh" },
      })
      .with(agama.agusd)
      .withdraw({ recipient: agama.adapter, amount: agusdAmount })
      .surplusTo(de.alice.address, false)
      .with(agama.usdToken)
      .transfer({ recipient: de.alice.address, amount: Open })
      .done()
      .invoke((args) => {
        const openNote = args.openNotes[0];
        if (!openNote) throw new Error("no open note");
        return {
          contractAddress: agama.adapter,
          calldata: [1n, agama.agusd, agama.usdToken, agusdAmount, 0n, openNote.noteId],
        };
      })
      .execute();
    await devnet.executeOutside(redeemCall);
    await env.indexer.waitForBlock(devnet.url);
    const { notes: fin } = await transfers.alice.discoverNotes();
    const usdcBack = (fin.get(BigInt(agama.usdToken)) ?? []).reduce((s, n) => s + n.amount, 0n);
    line(`    Shielded USDC recovered: ${fmt(usdcBack)} USDC`);

    line("\n----------------------------------------------------------------------");
    line("  RESULT");
    line(`    Alice deposited ${fmt(deposit)} USDC, lent ${fmt(lend)} into agUSD, redeemed back.`);
    line(`    On-chain, nothing links Alice's address to her ${fmt(agusdAmount)} agUSD position:`);
    line("    it lived in an encrypted note, openable only with her viewing key.");
    line("    No proving service needed: mock prover on a local devnet.");
    line("----------------------------------------------------------------------");
  } finally {
    await env.indexer.shutdown();
    await devnet.cleanup();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
