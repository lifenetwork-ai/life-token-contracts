# LIFE token contracts

Solidity source for the LIFE AI (`LIFE`) ERC20 token and its funded distribution contracts on Avalanche C-Chain.

## LIFE token

[`src/LIFEToken.sol`](src/LIFEToken.sol)

- Standard ERC20 built on OpenZeppelin Contracts v5.4.0.
- Name `LIFE AI`, symbol `LIFE`, 18 decimals.
- Fixed supply of 10,000,000,000 LIFE, minted once in the constructor to `initialRecipient`.
- No owner or admin role. No mint, burn, pause, blacklist, transfer fee or upgrade functions.

## Other contracts

| Contract | Purpose |
|---|---|
| `LIFEVestingVault.sol` | UUPS-upgradeable shared vesting vault for Investor, Advisor, Foundation, Ecosystem and Team grants |
| `LIFEUpgradeTimelock.sol` | Timelock (minimum 48h delay) controlling vesting vault upgrades |
| `TGERegistry.sol` | Records the common TGE timestamp |
| `TGEDistributionVault.sol` | Fixed TGE distribution allocations |
| `LIFEEmissionVault.sol` | Scheduled emission release |
| `libraries/VestingMath.sol` | Vesting schedule math |

## Allocation and vesting

Total supply 10,000,000,000 LIFE. Months are 30 days, measured from TGE.

| Allocation | Share | LIFE | Contract | Release |
|---|---:|---:|---|---|
| Subnet distribution | 19% | 1,900,000,000 | `TGEDistributionVault` | Unlocked at TGE |
| Subnet emission and rewards | 31% | 3,100,000,000 | `LIFEEmissionVault` | 80 quarterly batches, Months 48–285 |
| Investors | 20% | 2,000,000,000 | `LIFEVestingVault` (category 0) | 0% before Month 12; 25% at Month 12; then 1/48 per month, Months 13–48 |
| Advisors | 5% | 500,000,000 | `LIFEVestingVault` (category 1) | Same as Investors |
| Foundation | 8% | 800,000,000 | `LIFEVestingVault` (category 2) | 3-month cliff, then 1/120 per month, Months 4–123 |
| Ecosystem | 10% | 1,000,000,000 | `LIFEVestingVault` (category 3) | 3-month cliff, then 1/120 per month, Months 4–123 |
| Team | 7% | 700,000,000 | `LIFEVestingVault` (category 4) | 12-month cliff, then 1/48 per month, Months 13–60 |

## Build and test

Requires [Foundry](https://book.getfoundry.sh/).

```sh
git clone --recurse-submodules <repo-url>
forge build
forge test
```

Compiler settings (from `foundry.toml`): solc `0.8.30`, optimizer enabled with 200 runs, EVM version `cancun`.

## Deployments

| Network | Contract | Address |
|---|---|---|
| Avalanche Fuji testnet (43113) | LIFEToken | [`0xb4099e22daff6f8aea114ad89194c9e9538df08e`](https://testnet.snowtrace.io/address/0xb4099e22daff6f8aea114ad89194c9e9538df08e#code) |
| Avalanche C-Chain mainnet | LIFEToken | Not yet deployed |

The mainnet token will be deployed from `src/LIFEToken.sol` in this repository with the compiler settings above and source-verified on Snowtrace and Sourcify.

## License

MIT (see SPDX headers).
