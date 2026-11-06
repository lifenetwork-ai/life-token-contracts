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
| `LIFEVestingVault.sol` | UUPS-upgradeable shared vesting vault for Investor, Advisor, Foundation and Ecosystem grants |
| `LIFEUpgradeTimelock.sol` | Timelock (minimum 48h delay) controlling vesting vault upgrades |
| `TGERegistry.sol` | Records the common TGE timestamp |
| `TGEDistributionVault.sol` | Fixed TGE distribution allocations |
| `LIFEEmissionVault.sol` | Scheduled emission release |
| `libraries/VestingMath.sol` | Vesting schedule math |

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
