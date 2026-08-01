# STRK20 integration test (against the real StarkWare privacy package)

This package proves the Agama shielded adapter is a valid STRK20 invoke anonymizer against
StarkWare's **actual** privacy code, not a local copy. The adapter here imports the real
`privacy::objects::OpenNoteDeposit` (the exact note type the on-chain pool applies) and is tested
under StarkWare's pinned toolchain.

## What it verifies

The native STRK20 privacy pool (stood in for by a caller) drives the Agama adapter through a
shielded deposit and withdraw: 1 USDC in, the vault mints yield-bearing agUSD to the adapter, and
the adapter approves the pool to seal it into a `privacy::objects::OpenNoteDeposit` note. Reverse
for withdraw.

## How to run

This package depends on `privacy` from `starkware-libs/starknet-privacy`, so it runs inside a
clone of that workspace with the pinned toolchain (scarb 2.17.0, starknet-foundry 0.59.0).

```bash
git clone --depth 1 https://github.com/starkware-libs/starknet-privacy.git
cp -r strk20-integration starknet-privacy/packages/agama_shielded_anonymizer
# add "packages/agama_shielded_anonymizer" to the workspace members in starknet-privacy/Scarb.toml
cd starknet-privacy
snforge test -p agama_shielded_anonymizer
```

## Result (verified 2026-08-01)

```
Collected 3 test(s) from agama_shielded_anonymizer package
[PASS] test_adapter_rejects_equal_tokens
[PASS] test_shielded_deposit_into_agusd
[PASS] test_shielded_withdraw_from_agusd
Tests: 3 passed, 0 failed
```

Alongside this, StarkWare's own suites pass in the same environment: 7/7 for
`vesu_lending_anonymizer` and 303/303 for the `privacy` pool (deposit/withdraw private flow,
viewing keys, notes, and an anonymizer driven through the real pool). The one part not
reproducible locally is the off-chain proving service (client-side ZK, Stwo), which is
StarkWare-operated.
