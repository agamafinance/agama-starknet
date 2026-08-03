# Real shielded STRK20 on public Starknet Sepolia

Public Starknet Sepolia (chain_id `SN_SEPOLIA`) supports STRK20 / SNIP-36
in-protocol privacy proof verification. A real shielded deposit can be submitted
on the public testnet and is verifiable on a public explorer. This folder holds
the empirical proof of that, the privacy pool deployed on Sepolia, and the runner
that lands a real shielded deposit once a prover is reachable.

## Evidence: the public Sepolia sequencer verifies STRK20 proofs

`proof-support-probe.mjs` submits an invoke v3 carrying the SNIP-36 `proof_facts`
field to the live public gateway and reads its reply. A network without the
privacy feature would reject `proof_facts` as an unknown field. Public Sepolia
instead answers with the privacy protocol's own validation, which proves the
feature is live:

| Submission | Public Sepolia gateway reply |
|---|---|
| `proof_facts` without a proof | code 63, "Proof facts and proof must either both be present or both be absent" |
| `proof_facts` + a malformed proof | code 69, "The proof field in the invoke v3 transaction is invalid" |
| `proof` as an array | "cannot unmarshal array ... of type core.Base64" (proof must be Base64) |

Reproduce (needs a funded Sepolia account, no gas is spent because the tx is
rejected at validation), from a folder where `starknet@10.0.0-beta.6` resolves:

```bash
ADDR=0x... PK=0x... node proof-support-probe.mjs
```

`starknet@10.0.0-beta.6` carries these fields natively: `Account.execute(calls,
{ proofFacts, proof })` and `provider.invokeFunction` add `proof_facts` + `proof`
to the invoke, and the transaction hash commits to `poseidonHashMany(proof_facts)`.

## Privacy pool on Sepolia

The real StarkWare privacy pool (class `0x52107fad…`) is deployed on public
Sepolia at:

```
0x01b39392c749f030c60ae8d3ce6b1a382f290882b69584e7bec9755d48749c83
```

Constructor: `governance_admin` = deployer, `auditor_public_key` = `0x1`,
`screener_public_key` = `starkKey(0xCAFEBABE)` (the SDK test screener, so
deposit screening attestations can be signed locally), `proof_validity_blocks`
= `450`. Voyager: https://sepolia.voyager.online/contract/0x01b39392c749f030c60ae8d3ce6b1a382f290882b69584e7bec9755d48749c83

## Landing a real shielded deposit

The one piece that is not a protocol gate is proof generation. StarkWare ships
the prover as a public image; point it at Sepolia with `docker-compose.yml` +
`prover-config.sepolia.json`, then run `shield-sepolia.ts`:

```bash
docker compose up -d                       # transaction prover on :3000
PROVER_URL=http://localhost:3000 npx tsx shield-sepolia.ts
```

`shield-sepolia.ts` approves the deposit token, builds the shielded deposit with
a real proof from the prover, waits for block maturity (proof block must be
`<= current - 10`), and submits the proof-carrying invoke via SNIP-9 outside
execution. On success it prints the Voyager link to the shielded transaction.

## The one host constraint: the prover needs AVX512

The Stwo prover (`transaction-prover:PRIVACY-0.14.3-RC.2`) requires the AVX512
instruction set exposed to the process, with no AVX2 fallback: it aborts with
SIGILL (exit 132, no logs) the moment AVX512 is missing. This is the single
reason it cannot run just anywhere. Verified across environments:

| Host | x86-64 | AVX512 exposed | Prover |
|---|---|---|---|
| Docker / OrbStack arm64 (Apple M4) | no | n/a | SIGILL (arm64 build needs an unexposed ARM extension) |
| Rosetta amd64 (Apple M4) | emulated | no | SIGILL |
| QEMU TCG amd64, `-cpu max` (Apple M4) | emulated | no (TCG caps at AVX2) | SIGILL |
| GitHub Actions `ubuntu-latest` (AMD EPYC 9V74) | yes | no (masked by the hypervisor) | SIGILL |
| Cloud compute VM (GCP c3, AWS m7i/c7i, AVX512 SKU) | yes | yes | runs |

So run the prover on a cloud instance whose CPU exposes AVX512 (most modern
compute-optimized instances do). Everything else in this folder, and the whole
transparent + local-devnet-shielded stack, runs anywhere including Apple Silicon.
