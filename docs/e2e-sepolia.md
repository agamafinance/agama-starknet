# E2E on Starknet Sepolia

End-to-end runs against the live stack — all real transactions, verifiable on
[Voyager](https://sepolia.voyager.online).

## Acceptance run (`scripts/e2e_full.sh`) — 8/8 checks passed

A single real-transaction sweep with state assertions and on-chain guard checks:

| Step | Assertion | Result |
|---|---|---|
| deposit 5 USDC → agUSD | reserve += 5 | ✓ |
| NAV push (fresh) | nav = 1_050_000, not stale | ✓ |
| NAV deviation guard (+25%) | reverts `deviation too large` | ✓ |
| allocate within cap | deployed += 1 | ✓ |
| concentration-cap guard | reverts `cap breached` | ✓ |
| deallocate | deployed back to start | ✓ |
| distribute yield | total_assets += 2 (agUSD share price rises) | ✓ |
| redeem all agUSD → USDC | shares burned to 0 (principal + yield returned) | ✓ |
| withdrawal queue enqueue/process | pending → 0 | ✓ |

The step-by-step run below (`scripts/e2e_sepolia.sh`) lists the individual transaction hashes;
the live yield round-trip is section 1.

## Deployed contracts

| Contract | Address |
|---|---|
| AgamaUSD (agUSD, yield-bearing share) | `0x05563a90a1368c73dd6ed86418ecabbd245d9d6dfdf1e23e09eb9141eb66c345` |
| AgamaVault | `0x06bd19937bf9bf258cf52c244a247d4ecc9ee08f4e553f67fadc971346cb3604` |
| NavOracle | `0x0524c9683f467d7c0ddc51b0b83352e33a2300bae006af90d9eb9ecad6349679` |
| WithdrawalQueue | `0x00a8f8cae024f97dd63c5fb90444d49ede807b23b25441d563b77450a8431493` |
| AllocationEngine | `0x013be6562483ab26ea3b1609580b8246eeb3542fbd57c7c583c036a46dc72bb9` |

USDC (Circle native): `0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343`.
The full stack is deployed and exercised end-to-end.

## Run results

### 1. Yield-bearing round-trip (agUSD share price rises with distributed yield)
Deposit 3 USDC → mint 3 agUSD shares (price 1.0). Owner distributes 2 USDC of RWA yield, so
total assets grow to 5 while supply stays 3 → **3 agUSD is now worth 5 USDC** (share price
1.667). Redeeming the 3 shares returns the appreciated 5 USDC. Verified on-chain:
`convert_to_assets(3_000_000) = 5_000_000`.

| Step | Tx |
|---|---|
| approve 3 USDC | [`0x2137644b…`](https://sepolia.voyager.online/tx/0x2137644b045bb54618ad23bde109ca33814024874e91772ea22ece1be8bcd2b) |
| deposit 3 USDC → 3 agUSD | [`0x36ffd4d7…`](https://sepolia.voyager.online/tx/0x36ffd4d76b92338d85da91d692149b7cfbabd48c23c0d5c2738aa75cdc40350) |
| approve 2 USDC (yield) | [`0x3849d65d…`](https://sepolia.voyager.online/tx/0x3849d65d588b2f5485037a3137dd1e7a097d68fdf1eee53667c7eba8468815f) |
| distribute 2 USDC | [`0x13d7a321…`](https://sepolia.voyager.online/tx/0x13d7a32104eb6e186487b9485b084e6f65d756be98b30e200a4b745fa700172) |
| redeem 3 agUSD → 5 USDC | [`0x43649200…`](https://sepolia.voyager.online/tx/0x43649200090ace1bcc5c2b0ad9a983db93a532f252a069d9ba77429b00bf65d) |

Result: share price 1.0 → 1.667, `agUSD supply = 0`, `total_assets = 0` after redeem (clean).

### 2. NAV oracle push
`push_nav(1_050_000)` = +5% from 1_000_000, accepted at exactly the deviation cap; oracle fresh.

| Step | Tx |
|---|---|
| add_reporter | [`0x51ae4e7d…`](https://sepolia.voyager.online/tx/0x51ae4e7dad914a0091461128914a4b6f1509cf40b4a3131c0c41b518573b05d) |
| push_nav(1_050_000) | [`0x5acf5c7b…`](https://sepolia.voyager.online/tx/0x5acf5c7bb44019abc074667e5d684f792785a297d80b37568d1f24eb4878dc4) |

Result: `nav = 1_050_000`, `is_stale = false`.

### 3. Withdrawal queue
FIFO enqueue then process; queue drains to empty.

| Step | Tx |
|---|---|
| enqueue | [`0x7f9f4fc3…`](https://sepolia.voyager.online/tx/0x7f9f4fc363d8ca59b6abdcd21b70e6a58b55fb942e1ce6b0a6bdb97d901ac79) |
| process | [`0x4fe30b74…`](https://sepolia.voyager.online/tx/0x4fe30b742b77554439009ca639a087193d64302da214de3cdf902dc42ab7d8e) |

Result: `pending = 0`.

### 4. Allocation engine
Register a pool at a 40% cap, fund 10, allocate 4 (exactly the cap), deallocate 1 — all
gated on a fresh NAV oracle.

| Step | Tx |
|---|---|
| push_nav (freshen) | [`0x58932392…`](https://sepolia.voyager.online/tx/0x5893239288a6e8c4dbeea681a23f9743c60bc024713fef1c8f8c6f5ea363639) |
| register_pool(1, 40%) | [`0xe459016f…`](https://sepolia.voyager.online/tx/0xe459016f26e03c04cb098b46ff86692720acd84ef026733c3fdc6db199f478) |
| fund(10) | [`0x60b78f3a…`](https://sepolia.voyager.online/tx/0x60b78f3ae44fe892fa551ccf372181d4a8c5df05efc474780580be101585506) |
| allocate(1, 4 = cap) | [`0x6b6c3292…`](https://sepolia.voyager.online/tx/0x6b6c3292a523fbbe848c94e258249a398b87b369c4ecfe20c21e997a744c982) |
| deallocate(1, 1) | [`0x1ecbad89…`](https://sepolia.voyager.online/tx/0x1ecbad89a4afad452ee38599a6cdbfb4a5e1b1306729d20bfe57123e870241c) |

Result: `deployed(1) = 3`, `idle = 7`, `total_deployed = 3`.

The yield-bearing behavior itself (deposit → distribute → redeem-at-appreciated-price) is the
round-trip in section 1 above; there is no separate staking token — agUSD is the yield token.
