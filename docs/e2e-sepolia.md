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
| AgamaUSD (agUSD, yield-bearing share) | `0x04c0d175cab9fd3163958443830678c9828f52bbbfcd99c04cc52985302abd1f` |
| AgamaVault | `0x059ed11c2b242e766818f3a957a1a9cfe22b0462b4eb7a60bbb71f5ecdb160b1` |
| LendingPool A (private credit, 12%) | `0x07fd9db4d3377e6909555ea100b631784048de519e0100f32d5877180ebb55ad` |
| LendingPool B (tokenized treasuries, 5%) | `0x018d17c95680bc634ffaa4211be8db4bfec2625ff614a2faf925422c44e3eb2d` |
| LendingPool C (bonds, 7%) | `0x0438cd90d88358b574690ccdd8fd17370245929bed2d390f27bc984cbcf206e6` |
| LendingPool D (onchain RWA yield, 9%) | `0x01ac07c1564032d8c3d02bdff1f9661783f3abc3b97ccdc6de318f70a171249f` |
| NavOracle | `0x0524c9683f467d7c0ddc51b0b83352e33a2300bae006af90d9eb9ecad6349679` |
| WithdrawalQueue | `0x00a8f8cae024f97dd63c5fb90444d49ede807b23b25441d563b77450a8431493` |
| AllocationEngine | `0x013be6562483ab26ea3b1609580b8246eeb3542fbd57c7c583c036a46dc72bb9` |

USDC (Circle native): `0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343`.
The full stack is deployed and exercised end-to-end.

## Run results

### 1. Live yield-bearing NAV across four lending pools
Deposit 4 USDC → mint 4 agUSD (price 1.0), then allocate the reserve across the four pools:
1.5 → Pool A (12%), 1.0 → Pool B (5%), 1.0 → Pool C (7%), 0.5 → Pool D (9%). Each pool now
accrues at its own APR every block, so the vault NAV — and the `agUSD` share price — rises
continuously (blended ~8.63% APR). Verified on-chain: `total_assets` grows past `4_000_000`
each block; the dApp reads the raw pool state and projects the price live.

| Step | Tx |
|---|---|
| approve 4 USDC | [`0x4ba9c9fd…`](https://sepolia.voyager.online/tx/0x4ba9c9fd22334b8d9336e184c46121579637dc7bceaf932b294b1721c6ae774) |
| deposit 4 USDC → 4 agUSD | [`0x491967b8…`](https://sepolia.voyager.online/tx/0x491967b826ef1648c05bc1f42b381bd6095c6dcd32946ef0ba41b95102397af) |
| allocate 1.5 → Pool A (12%) | [`0x677d5213…`](https://sepolia.voyager.online/tx/0x677d521375713a3d95f93e1520cdc1bde6c38e36cf0283c8c717e8e034ee3e5) |
| allocate 1.0 → Pool B (5%) | [`0xb3d42b91…`](https://sepolia.voyager.online/tx/0xb3d42b91c61d66312e1fd9867f16384998916186440c67357c81075159c51) |
| allocate 1.0 → Pool C (7%) | [`0x126fa510…`](https://sepolia.voyager.online/tx/0x126fa510c7dbdef350051ced3c24d18321f88a2c6f03f89e6bea3d5621dad6f) |
| allocate 0.5 → Pool D (9%) | [`0x3191290f…`](https://sepolia.voyager.online/tx/0x3191290f1c6d7afff56854b73296b623608c49963722c210f2ca4fc1ae65f0f) |

Result: NAV = 4.0 at t0, rising every block; `agUSD` price = NAV / supply, indexed on the
aggregate of the four pools.

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
