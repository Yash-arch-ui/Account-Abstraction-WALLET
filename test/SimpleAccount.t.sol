/*

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "../src/contracts/SimpleAccount.sol";

contract SimpleAccountTest is Test {
    EntryPoint entryPoint;
    SimpleAccount account;

    address beneficiary = payable(address(0xB0B));

    // owner of the account; userOps are signed with this key
    uint256 constant OWNER_KEY = 0xA11CE;
    address owner;

    function setUp() public {
        owner = vm.addr(OWNER_KEY);
        entryPoint = new EntryPoint();
        account = new SimpleAccount(owner);

        // fund the account so it can cover missingAccountFunds
        vm.deal(address(account), 1 ether);
    }

    function testHandleOpsDoesNotRevert() public {
        // TODO: pick real gas values — try something like:
        // verificationGasLimit = 150_000, callGasLimit = 100_000
        uint128 verificationGasLimit = 150_000;
        uint128 callGasLimit = 100_000;
        bytes32 accountGasLimits = _pack(verificationGasLimit, callGasLimit);

        // TODO: pick fee values, e.g. maxPriorityFeePerGas = 1 gwei, maxFeePerGas = 10 gwei
        uint128 maxPriorityFeePerGas = 1 wei;
        uint128 maxFeePerGas = 10 wei;
        bytes32 gasFees = _pack(maxPriorityFeePerGas, maxFeePerGas);

        // ask EntryPoint for the correct nonce instead of hardcoding 0
        uint256 nonce = entryPoint.getNonce(address(account), 0);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(account),
            nonce: nonce,
            initCode: "",
            callData: "",
            accountGasLimits: accountGasLimits,
            preVerificationGas: 50_000,
            gasFees: gasFees,
            paymasterAndData: "",
            signature: ""
        });

        // the account validates signatures now, so sign the userOpHash with the owner's key
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_KEY, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Day 1 goal: this should NOT revert
        // EntryPoint v0.9's nonReentrant guard requires an EOA caller
        // (tx.origin == msg.sender && msg.sender.code.length == 0), i.e. a real bundler.
        // Simulate an EOA bundler submitting the bundle.
        address bundler = address(0xB0B0);
        // two-arg prank sets both msg.sender AND tx.origin (the guard checks both)
        vm.prank(bundler, bundler);
        entryPoint.handleOps(ops, payable(beneficiary));
    }

    function _pack(uint128 hi, uint128 lo) internal pure returns (bytes32) {
        return bytes32(uint256(hi) << 128 | uint256(lo));
    }
}
*/