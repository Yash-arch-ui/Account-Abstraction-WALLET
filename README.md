# AAWallet

An ERC-4337 (Account Abstraction) smart-contract wallet built with [Foundry](https://book.getfoundry.sh/).

The project implements the pieces needed to run sponsored (gasless) transactions:

- a minimal **smart account** whose owner signs user operations,
- a **factory** that deterministically deploys accounts via CREATE2,
- a **token paymaster** that sponsors gas and charges the user back in an ERC-20 token,
- a **mock ERC-20** for local testing and deployment.

It builds against [account-abstraction](https://github.com/eth-infinitism/account-abstraction) `v0.9.0`
(EntryPoint v0.9, `PackedUserOperation`) and OpenZeppelin Contracts.

## Architecture

| Contract | Description |
| --- | --- |
| `src/contracts/SimpleAccount.sol` | Minimal `IAccount` implementation. The owner's ECDSA signature over the `userOpHash` is validated in `validateUserOp`; the account also covers `missingAccountFunds` owed to the EntryPoint. |
| `src/contracts/SimpleAccountFactory.sol` | Deploys `SimpleAccount` instances at deterministic addresses using CREATE2 (`createAccount(owner, salt)`), and returns the existing account if one is already deployed at that address. `getAddress` computes the same address off-chain without deploying. |
| `src/contracts/TokenPaymaster.sol` | ERC-20 paymaster implementing `IPaymaster`. During `validatePaymasterUserOp` it checks the sender has enough token balance/allowance to cover the worst-case `maxCost`, then in `postOp` it charges the user proportionally to the **actual** gas cost (`actualGasCost * exchangeRate / 1e18`). The user must approve the paymaster to spend their tokens. |
| `src/mocks/MockERC20.sol` | Simple `ERC20` with a public `mint(address, uint256)`, used by tests and the deploy script. |

### How a sponsored transaction flows

1. The user approves the paymaster to spend their ERC-20 tokens.
2. A bundler submits a user op whose `paymasterAndData` points at the paymaster.
3. `validatePaymasterUserOp` checks balance + allowance and quotes a worst-case `maxTokenCost`.
4. After execution, `postOp` charges only for the real gas used, transferring tokens from the user to the paymaster.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas snapshots

```shell
$ forge snapshot
```

### Local chain

```shell
$ anvil
```

### Deploy (paymaster + mock token)

```shell
$ forge script script/DeployPaymaster.s.sol:DeployPaymaster \
    --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

> Note: the deploy script currently deploys a fresh `EntryPoint` and a `MockERC20`. For a real deployment,
> point it at an existing EntryPoint and a real token, and add the paymaster deposit via
> `entryPoint.depositTo{value: X}(address(paymaster))`.

### Help

```shell
$ forge --help
$ cast --help
$ anvil --help
```

## Layout

```
script/       Deploy scripts
src/contracts  Production contracts (account, factory, paymaster)
src/mocks      Test-only mocks (MockERC20)
test/          Forge tests
lib/           Git submodules (forge-std, account-abstraction, openzeppelin-contracts)
```
