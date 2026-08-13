// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {TokenPaymaster} from "../src/contracts/TokenPaymaster.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract DeployPaymaster is Script {
    function run() external {
        // TODO: deploy or reference an existing EntryPoint
        // TODO: deploy your token (mock ERC20) if you haven't yet
        // TODO: deploy TokenPaymaster(token, entryPoint, exchangeRate)
        // TODO: call entryPoint.depositTo{value: X}(address(paymaster))
        //       — this is the ETH backing that gets decremented per sponsored op
        vm.startBroadcast();
        EntryPoint entryPoint = new EntryPoint();
        MockERC20 token = new MockERC20("Mock Token", "MTK");
        uint256 exchangeRate = 1e18;
        TokenPaymaster paymaster = new TokenPaymaster(address(token), address(entryPoint), exchangeRate);
        // depositingeth into entryPoint to fund the Paymaster's gas account
        uint256 depositAccount = 1 ether;
        entryPoint.depositTo{value: depositAccount}(address(paymaster));
        vm.stopBroadcast();
    }
}
