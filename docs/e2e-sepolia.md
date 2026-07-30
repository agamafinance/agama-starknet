# E2E on Starknet Sepolia

End-to-end runs against the live stack — all real transactions, verifiable on
[Voyager](https://sepolia.voyager.online).

## Acceptance run (`scripts/e2e_full.sh`) — 8/8 checks passed

A single real-transaction sweep with state assertions and on-chain guard checks:

| Step | Assertion | Result |
|---|---|---|
| deposit 5 USDC → agUSD | reserve 25 → 30 | ✓ |
| NAV push (fresh) | nav = 1_050_000, not stale | ✓ |
| NAV deviation guard (+25%) | reverts `deviation too large` | ✓ |
| allocate within cap | deployed 3 → 4 | ✓ |
| concentration-cap guard | reverts `cap breached` | ✓ |
| deallocate | deployed 4 → 3 | ✓ |
| stake / distribute / unstake | staking pool drains to 0 (yield returned) | ✓ |
| redeem 5 agUSD → USDC | reserve 30 → 25 | ✓ |
| withdrawal queue enqueue/process | pending → 0 | ✓ |

The step-by-step run below (`scripts/e2e_sepolia.sh` + the allocation/staking flow) lists the
individual transaction hashes.

## Deployed contracts

| Contract | Address |
|---|---|
| AgamaUSD (agUSD) | `0x0143b8bf5144be0c0568410b6f8c3eb90629ddadfd0da9ac3a90cb35ec1b6006` |
| AgamaVault | `0x07909652ce28348eabfdce6b67a82228513798c70d5e06ec23fc2028abc261b5` |
| NavOracle | `0x0524c9683f467d7c0ddc51b0b83352e33a2300bae006af90d9eb9ecad6349679` |
| WithdrawalQueue | `0x00a8f8cae024f97dd63c5fb90444d49ede807b23b25441d563b77450a8431493` |
| AllocationEngine | `0x013be6562483ab26ea3b1609580b8246eeb3542fbd57c7c583c036a46dc72bb9` |
| StakedAgamaUSD (sagUSD) | `0x0129c466978f096b28e64cc086dea792bd1134e284915bf331cca40670160602` |

USDC (Circle native): `0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343`.
The full stack is deployed and exercised end-to-end.

## Run results

### 1. Vault redeem / deposit round-trip
agUSD 15.0 → redeem 5 → deposit 5 → 15.0 (conserved), all with native USDC.

| Step | Tx |
|---|---|
| redeem 5 agUSD → USDC | [`0x10eac24c…`](https://sepolia.voyager.online/tx/0x10eac24c78c4f7cab3add8f886743b5fbd9b9a231f376ee6668c34547198869) |
| approve 5 USDC | [`0x3302ddf3…`](https://sepolia.voyager.online/tx/0x3302ddf321b6a7d8d7b93d6797ff5df5cca6fbea4528c1473365f46886e88ca) |
| deposit 5 USDC → agUSD | [`0x58fa66ae…`](https://sepolia.voyager.online/tx/0x58fa66ae516d26350d39af1bfa79ba05042bb7295806aeaaced642cd59f7219) |

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

### 5. sagUSD staking with yield
Deposit 10 USDC → agUSD, stake 5 → sagUSD, distribute 2 agUSD of yield into the pool, then
unstake all shares. The share price grew 1.0 → 1.4, so unstaking 5 sagUSD returns **7 agUSD**
(5 principal + 2 yield).

| Step | Tx |
|---|---|
| approve USDC | [`0x1546eedf…`](https://sepolia.voyager.online/tx/0x1546eedfd10f8b9d90816dc29a3a1c8a5569063e39bd82910bee82d4fd9ba9e) |
| deposit 10 USDC → agUSD | [`0x5b74cafc…`](https://sepolia.voyager.online/tx/0x5b74cafce7bcb65a4a457e0896acbccf9666e3e9fc195456461784edc26152f) |
| approve agUSD → sagUSD | [`0x28b40a07…`](https://sepolia.voyager.online/tx/0x28b40a0747655bb8c1f3e69e98c92334d61690fd6c510dba5a5b0e0b14bd086) |
| stake 5 agUSD | [`0x4102eee0…`](https://sepolia.voyager.online/tx/0x4102eee02280758e8c57fed35ef388c041985923a54e813dd3642cb4e2651cc) |
| distribute 2 (yield) | [`0x3a33dbe4…`](https://sepolia.voyager.online/tx/0x3a33dbe4cb0f3aed8a42226764552175c8d8c4e620066702e8be34ec3d9d307) |
| unstake 5 sagUSD → 7 agUSD | [`0x5372485e…`](https://sepolia.voyager.online/tx/0x5372485e4835291b8c40d0634439b304aa1e695883b844eea5d51338dcf8d34) |

Result: `agUSD balance = 25` (15 + 10 deposited, with staked principal + yield returned),
`sagUSD balance = 0`.
