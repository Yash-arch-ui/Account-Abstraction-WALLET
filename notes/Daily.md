# AAWALLET — Mental Model (Daily Notes)

> A living document capturing the current understanding of the project: what's built, how it fits together, and what's next.

## 1. What is this project?

**AAWALLET** is an **ERC-4337 Account Abstraction smart wallet** built with **Foundry** (forge/cast/anvil).

- Stack: Solidity `^0.8.19`, forge-std for testing, **account-abstraction v0.9.0** (EntryPoint + PackedUserOperation), OpenZeppelin (ECDSA).
- The goal: a `SimpleAccount` whose transactions are authorized by **ECDSA signature** and executed through an EntryPoint (bundler), not a plain EOA private-key tx.

## 2. The big picture (architecture)

```
          Bundler (EOA)
              │  1. collects UserOps, computes userOpHash, calls handleOps()
              ▼
        EntryPoint (v0.9, from account-abstraction lib)
              │  2. calls validateUserOp() on the account → checks signature
              │  3. calls executeUserOp → runs the account's callData
              ▼
         SimpleAccount  (our wallet, implements IAccount)
              └── owner (address) set in constructor
```

Key point: the **account itself never pays gas directly**. The bundler/EntryPoint front the gas, and the account repays the EntryPoint via `missingAccountFunds`.

## 3. Mental model of the validation flow

`SimpleAccount.validateUserOp(PackedUserOperation, userOpHash, missingAccountFunds)`:

1. **Recover signer** — `ECDSA.recover(userOpHash, userOp.signature)`.
2. **Check ownership** — recovered signer must equal `owner`, else return `SIG_VALIDATION_FAILED`.
3. **Pay the EntryPoint** — send `missingAccountFunds` wei to `msg.sender` (the EntryPoint). Revert if the transfer fails.
4. **Approve** — return `SIG_VALIDATION_SUCCESS` (validationData = 0 → valid forever, no time lock).

`userOpHash` is what gets signed — it's `entryPoint.getUserOpHash(userOp)`, NOT the raw userOp.

## 4. What's been written so far — status

| File | Status | Notes |
|---|---|---|
| `src/contracts/SimpleAccount.sol` | ✅ **Done** | Owner-based ECDSA validation, repays missingAccountFunds. |
| `test/SimpleAccount.t.sol` | ✅ **Done** | `testHandleOpsDoesNotRevert` — full flow through real EntryPoint. |
| `src/contracts/SimpleAccountFactory.sol` | ⬜ Empty | Not written yet — will deploy accounts via CREATE2 + initCode. |
| `script/Deploy.s.sol` | ⬜ Empty | Not written yet — deployment script. |
| `test/EntryPointIntegration.t.sol` | ⬜ Empty | Planned — deeper EntryPoint integration coverage. |
| `test/Validation.t.sol` | ⬜ Empty | Planned — signature/validation failure cases. |
| `foundry.toml` | ✅ **Done** | Default profile; OZ remapping only (AA/forge-std resolve via `libs`). |

## 5. Gotchas & lessons learned (important!)

1. **EntryPoint v0.9's `nonReentrant` guard requires an EOA caller**:
   `tx.origin == msg.sender && msg.sender.code.length == 0`. In tests, a contract (the test contract) calling `handleOps` directly is blocked. **Workaround:** `vm.prank(bundler, bundler)` — the two-arg form sets BOTH `msg.sender` and `tx.origin`, simulating a real EOA bundler.

2. **`PackedUserOperation` packs values into bytes32 slots**:
   - `accountGasLimits = bytes32(uint256(verificationGasLimit) << 128 | uint256(callGasLimit))`
   - `gasFees = bytes32(uint256(maxPriorityFeePerGas) << 128 | uint256(maxFeePerGas))`
   - Use a `_pack(uint128 hi, uint128 lo)` helper.

3. **Don't hardcode nonce 0** — ask the EntryPoint: `entryPoint.getNonce(address(account), 0)`.

4. **Sign the userOpHash, not the userOp** — `vm.sign(OWNER_KEY, entryPoint.getUserOpHash(userOp))`, then pack as `abi.encodePacked(r, s, v)`.

5. **Fund the account in setUp** — `vm.deal(address(account), 1 ether)` so it can cover `missingAccountFunds`.

6. **Current test values are placeholders** (marked TODO in code): gas/fee values are "pick real numbers" — try `verificationGasLimit = 150_000`, `callGasLimit = 100_000`, `maxPriorityFeePerGas = 1 gwei`, `maxFeePerGas = 10 gwei`.

## 6. Day 1 goal (current milestone)

> `entryPoint.handleOps()` should **NOT revert** for a properly signed userOp.

This is verified in `SimpleAccount.t.sol` via the EOA-bundler prank. The test passes when the whole loop (sign → validate → pay → execute) works.

## 7. CREATE2 cheat sheet — salt, bytecode, bytecode hash

### Definitions

- **Salt** — a `bytes32` value chosen by the deployer (we pass a `uint256`, cast to `bytes32`). It's the "variation knob" of CREATE2: same deployer + same init code + different salt → **different address**. It is not secret and has no intrinsic meaning — it just lets you generate many distinct deterministic addresses for the same contract + args (e.g. one account per user).

- **Bytecode / creation code** — the raw bytes the EVM runs to create a contract. In Solidity: `type(SimpleAccount).creationCode`. At deploy time the constructor arguments are appended to it, producing the **init code**: `initCode = creationCode ++ abi.encode(owner)`. This is what the CREATE2 opcode executes and hashes.

- **Bytecode hash / init code hash** — `keccak256(initCode)`. Init code can be large, so the CREATE2 formula uses its fixed 32-byte keccak digest as a "fingerprint". It encodes *which* contract, with *which* constructor args. Change the owner → the hash changes → the address changes.

### The three formulas (in the order they're computed)

```solidity
// 1. Init code: creation bytecode + constructor args (owner baked in)
bytes memory initCode = abi.encodePacked(type(SimpleAccount).creationCode, abi.encode(owner));

// 2. Bytecode hash (fixed 32-byte fingerprint of the init code)
bytes32 bytecodeHash = keccak256(initCode);

// 3. CREATE2 address — deployer is the FACTORY (address(this)), not the owner
address predicted = address(uint160(uint256(
    keccak256(abi.encodePacked(bytes1(0xff), deployer, bytes32(salt), bytecodeHash))
)));
// ^ only the last 20 bytes of the 32-byte hash are used as the address
```

### Rules to never break

1. `getAddress()` must agree with the real deployment on **three things**: the deployer (`address(this)`), the salt encoding (`bytes32(salt)`), and the init code. If any one differs, prediction ≠ reality and the factory's whole guarantee breaks.
2. `new SimpleAccount{salt: bytes32(salt)}(owner)` is pure Solidity — the compiler emits the `CREATE2` opcode for you, no assembly needed.
3. Two different owners + same salt → different bytecode hash → **different addresses** (no collision).

### Commands (foundry / cast)

```bash
# Compile; artifacts land in out/ (SimpleAccount.sol/SimpleAccount.json has .bytecode.object = creation code)
forge build

# Compute a CREATE2 address from the pieces (deployer + salt + init code)
cast create2 --deployer 0x... --salt 0x... --init-code 0x...

# Same, but pass the already-computed init code hash
cast create2 --deployer 0x... --salt 0x... --init-code-hash 0x...

# Hash arbitrary data with keccak256 (e.g. compute a bytecode hash by hand)
cast keccak <hex-data>

# Fetch the runtime bytecode of a deployed contract
cast code 0x...

# Nonce-based CREATE address (also supports --salt for CREATE2)
cast compute-address 0x... [--nonce N] [--salt 0x...]

# Deploy via the factory (this is what actually performs the CREATE2)
cast send <FACTORY_ADDR> "createAccount(address,uint256)" <owner> <salt>
```

> Note: `forge create` has **no** `--salt` flag in this foundry version — it only does nonce-based (CREATE) deploys. To deploy counterfactually, call the factory's `createAccount` instead.

## 8. Next steps / open threads

- [ ] Write `SimpleAccountFactory.sol` (CREATE2, `createAccount`, counterfactual addresses).
- [ ] Write `script/Deploy.s.sol` (deploy EntryPoint + factory + sample account).
- [ ] Fill in `EntryPointIntegration.t.sol` (reverts, refunds, paymaster-less gas flows).
- [ ] Fill in `Validation.t.sol` (wrong signer → FAILED, bad signature, nonce handling).
- [ ] Replace placeholder gas/fee values with realistic ones.
- [ ] Run `forge test` to confirm everything is green.
