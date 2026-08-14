// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {TokenPaymaster} from "../src/contracts/TokenPaymaster.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {SimpleAccount} from "../src/contracts/SimpleAccount.sol";
import {SimpleAccountFactory} from "../src/contracts/SimpleAccountFactory.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployPaymaster is Script {
    function run() external {
        // Deploy the AA stack. EntryPoint first: the factory, accounts, and
        // paymaster all need its address.
        vm.startBroadcast();
        uint256 ownerKey = 1;
        address owner = vm.addr(ownerKey);
        EntryPoint entryPoint = new EntryPoint();
        SimpleAccountFactory factory = new SimpleAccountFactory(address(entryPoint));
        MockERC20 token = new MockERC20("Mock Token", "MTK");
        uint256 exchangeRate = 1e18;
        TokenPaymaster paymaster = new TokenPaymaster(address(token), address(entryPoint), exchangeRate);
        // Deposit ETH into EntryPoint to fund the paymaster's gas account.
        uint256 depositAccount = 1 ether;
        entryPoint.depositTo{value: depositAccount}(address(paymaster));
        vm.stopBroadcast();

        uint256 salt = 11123456;
        address sender = factory.getAddress(owner, salt);

        // Counterfactual account: pre-fund it so op1 (which pays its own gas via
        // missingAccountFunds) and the paymaster's token charge are both covered.
        vm.deal(sender, 1 ether);
        token.mint(sender, 1000 * 1e18);

        _deployAndApprove(ownerKey, owner, salt, sender, factory, entryPoint, token, paymaster);
        _runSponsoredOp(ownerKey, sender, entryPoint, token, paymaster);
    }

    // Op 1 (no paymaster): initCode deploys the account, and the account itself
    // approves the paymaster through its execute(). The account covers its own
    // gas from the ETH pre-funded above. Must be a SEPARATE bundle from the
    // sponsored op: handleOps validates every op before executing any, and the
    // paymaster checks allowance during validation.
    function _deployAndApprove(
        uint256 ownerKey,
        address owner,
        uint256 salt,
        address sender,
        SimpleAccountFactory factory,
        EntryPoint entryPoint,
        MockERC20 token,
        TokenPaymaster paymaster
    ) internal {
        // initCode: factory address ++ createAccount(owner, salt) selector + args
        bytes memory initCode = abi.encodePacked(
            address(factory),
            abi.encodeWithSelector(factory.createAccount.selector, owner, salt)
        );
        // callData: account.execute(token, 0, token.approve(paymaster, max))
        bytes memory approveCall = abi.encodeCall(IERC20.approve, (address(paymaster), type(uint256).max));
        bytes memory callData = abi.encodeCall(SimpleAccount.execute, (address(token), 0, approveCall));

        PackedUserOperation memory op = PackedUserOperation({
            sender: sender,
            nonce: entryPoint.getNonce(sender, 0),
            initCode: initCode,
            callData: callData,
            // verificationGasLimit must cover the initCode deploy (runtime code
            // deposit alone costs ~360k gas), so 1M gives comfortable headroom.
            accountGasLimits: bytes32(abi.encodePacked(uint128(1_000_000), uint128(200_000))),
            preVerificationGas: 50_000,
            gasFees: bytes32(abi.encodePacked(uint128(10 gwei), uint128(10 gwei))),
            paymasterAndData: "",
            signature: ""
        });
        _signUserOp(entryPoint, op, ownerKey);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        _submitBundle(entryPoint, ops);

        console.log("account deployed:", sender.code.length > 0);
        console.log("allowance after op1:", token.allowance(sender, address(paymaster)));
    }

    // Op 2: the sponsored op. The paymaster fronts gas and charges the account
    // tokens in postOp (transferFrom), using the approval set up by op1.
    function _runSponsoredOp(
        uint256 ownerKey,
        address sender,
        EntryPoint entryPoint,
        MockERC20 token,
        TokenPaymaster paymaster
    ) internal {
        // paymasterAndData: paymaster ++ validationGasLimit ++ postOpGasLimit
        bytes memory paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(100_000),
            uint128(50_000)
        );

        PackedUserOperation memory op = PackedUserOperation({
            sender: sender,
            // ask EntryPoint for the nonce instead of hardcoding (notes/Daily.md #3)
            nonce: entryPoint.getNonce(sender, 0),
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(abi.encodePacked(uint128(200_000), uint128(200_000))),
            preVerificationGas: 50_000,
            gasFees: bytes32(abi.encodePacked(uint128(10 gwei), uint128(10 gwei))),
            paymasterAndData: paymasterAndData,
            signature: ""
        });
        _signUserOp(entryPoint, op, ownerKey);

        console.log("token balance before op2:", token.balanceOf(sender));
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        _submitBundle(entryPoint, ops);

        console.log("token balance after op2:", token.balanceOf(sender));
        console.log("sender code length:", sender.code.length);
    }

    function _signUserOp(EntryPoint entryPoint, PackedUserOperation memory userOp, uint256 ownerKey) internal {
        bytes32 hash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, hash);
        userOp.signature = abi.encodePacked(r, s, v);
    }
    function _submitBundle(EntryPoint entryPoint, PackedUserOperation[] memory ops) internal {
        vm.prank(address(0xB0B0), address(0xB0B0));
        entryPoint.handleOps(ops, payable(address(0xBB)));
    }
}
