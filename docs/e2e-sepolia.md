# E2E on Starknet Sepolia

End-to-end run of the live stack via `scripts/e2e_sepolia.sh` — all real transactions,
verifiable on [Voyager](https://sepolia.voyager.online).

## Deployed contracts

| Contract | Address |
|---|---|
| AgamaUSD (agUSD) | `0x0143b8bf5144be0c0568410b6f8c3eb90629ddadfd0da9ac3a90cb35ec1b6006` |
| AgamaVault | `0x07909652ce28348eabfdce6b67a82228513798c70d5e06ec23fc2028abc261b5` |
| NavOracle | `0x0524c9683f467d7c0ddc51b0b83352e33a2300bae006af90d9eb9ecad6349679` |
| WithdrawalQueue | `0x00a8f8cae024f97dd63c5fb90444d49ede807b23b25441d563b77450a8431493` |

USDC (Circle native): `0x0512feac6339ff7889822cb5aa2a86c848e9d392bb0e3e237c008674feed8343`.
`AllocationEngine` and `StakedAgamaUSD` are pending a STRK top-up for their declare fee.

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
