import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { Devnet } from "@starkware-libs/starknet-privacy-sdk/testing";
import { Open } from "@starkware-libs/starknet-privacy-sdk";
import { createE2eTestEnv, type E2eTestEnv } from "../../src/harness.js";
import { deployAgamaStack, type AgamaAddresses } from "../../src/agama-setup.js";
import { u256Calldata } from "../../src/utils.js";

// A shielded deposit driven through StarkWare's real privacy pool lands as yield-bearing agUSD
// in an encrypted note, via the Agama invoke anonymizer. Then the reverse (agUSD back to USDC).
// Runs fully local: patched starknet-devnet + mock prover, no StarkWare proving service.
describe("Agama shielded lending on devnet", () => {
  let devnet: Devnet;
  let env: E2eTestEnv;
  let agama: AgamaAddresses;

  beforeAll(async () => {
    devnet = new Devnet();
    env = await createE2eTestEnv(devnet, {
      indexer: { logFile: "agama-lending-indexer.log" },
    });
    agama = await deployAgamaStack(env.env.admin, env.env.node);
  });

  afterAll(async () => {
    await env?.indexer.shutdown();
    await devnet?.cleanup();
  });

  it("shielded deposit into agUSD + redeem roundtrip", async () => {
    const { env: de, transfers } = env;
    const ONE = 10n ** 18n;
    const depositAmount = 100n * ONE;
    const lendAmount = 50n * ONE;

    // Mint USDC to alice and approve the privacy pool.
    const mintTx = await de.admin.execute({
      contractAddress: agama.usdToken,
      entrypoint: "mint",
      calldata: [de.alice.address, ...u256Calldata(depositAmount)],
    });
    await de.node.waitForTransaction(mintTx.transaction_hash);
    const approveTx = await de.alice.execute({
      contractAddress: agama.usdToken,
      entrypoint: "approve",
      calldata: [de.privacy.address, depositAmount, 0n],
    });
    await de.node.waitForTransaction(approveTx.transaction_hash);

    // Phase 1: shielded deposit of USDC into the privacy pool.
    const { callAndProof: depositCall } = await transfers.alice
      .build({
        autoRegister: true,
        autoSetup: true,
        autoDiscover: { notes: "refresh", channels: "refresh" },
      })
      .with(agama.usdToken, (token) => token.deposit({ amount: depositAmount }))
      .surplusTo(de.alice.address)
      .execute();
    await devnet.executeOutside(depositCall);
    await env.indexer.waitForBlock(devnet.url);

    // Phase 2: lend, withdraw USDC to the adapter, adapter mints agUSD, agUSD lands in a note.
    const { callAndProof: lendCall } = await transfers.alice
      .build({
        autoSetup: true,
        autoSelectNotes: "all",
        autoDiscover: { notes: "refresh", channels: "refresh" },
      })
      .with(agama.usdToken)
      .withdraw({ recipient: agama.adapter, amount: lendAmount })
      .surplusTo(de.alice.address, false)
      .with(agama.agusd)
      .transfer({ recipient: de.alice.address, amount: Open })
      .done()
      .invoke((args) => {
        const openNote = args.openNotes[0];
        if (!openNote) throw new Error("Expected one open note for lend");
        return {
          contractAddress: agama.adapter,
          calldata: [
            0n, // LendingOperation::Deposit
            agama.usdToken,
            agama.agusd,
            lendAmount,
            0n,
            openNote.noteId,
          ],
        };
      })
      .execute();
    await devnet.executeOutside(lendCall);
    await env.indexer.waitForBlock(devnet.url);

    // Phase 3: discover the shielded agUSD note.
    const { notes: agusdNotes } = await transfers.alice.discoverNotes();
    const agusdOut = agusdNotes.get(BigInt(agama.agusd)) ?? [];
    const agusdAmount = agusdOut.reduce((s, n) => s + n.amount, 0n);
    expect(agusdAmount).toBeGreaterThan(0n);
    expect(agusdAmount).toEqual(lendAmount); // 1:1 at price 1.0

    // Phase 4: redeem, withdraw agUSD to the adapter, get USDC back into a note.
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
        if (!openNote) throw new Error("Expected one open note for redeem");
        return {
          contractAddress: agama.adapter,
          calldata: [
            1n, // LendingOperation::Withdraw
            agama.agusd,
            agama.usdToken,
            agusdAmount,
            0n,
            openNote.noteId,
          ],
        };
      })
      .execute();
    await devnet.executeOutside(redeemCall);
    await env.indexer.waitForBlock(devnet.url);

    // Phase 5: value preserved, USDC recovered into notes.
    const { notes: finalNotes } = await transfers.alice.discoverNotes();
    const usdcOut = finalNotes.get(BigInt(agama.usdToken)) ?? [];
    const usdcRecovered = usdcOut.reduce((s, n) => s + n.amount, 0n);
    expect(usdcRecovered).toBeGreaterThanOrEqual(depositAmount - lendAmount);
  });
});
