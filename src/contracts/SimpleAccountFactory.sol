//SPDX-License-identifier:MIT
pragma solidity ^0.8.20;
import "./SimpleAccount.sol";

contract SimpleAccountFactory {
    // I need to create store a reference to.... what ? think: does the facotry need to know about EnytrPoint or just deploy SimpleAccount instances? 

    function createAccount(address owner, uint256 salt) public returns (SimpleAccount) {
        // step 1: figure out what address this WOULD be deployed to
        // step 2: if something is already deployed there, just return it, don't redeploy
        // step 3: otherwise, actually deploy it at that deterministic address

        address addr = getAddress(owner, salt);
        if (addr.code.length > 0) {
            return SimpleAccount(payable(addr));
        }
        SimpleAccount account = new SimpleAccount{salt: bytes32(salt)}(owner);
        return account;
    }

    function getAddress(address owner, uint256 salt) public view returns (address) {
        // needs to compute the SAME address createAccount would produce,
        // without actually deploying anything
        //
        // CREATE2: keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))
        // - deployer is THIS contract (the one calling CREATE2), not the owner
        // - initCode is the creation bytecode with the owner baked in as the
        //   constructor argument, then hashed
        bytes32 bytecodeHash = keccak256(abi.encodePacked(type(SimpleAccount).creationCode, abi.encode(owner)));
        address addr = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), bytes32(salt), bytecodeHash)
        ))));
        return addr;
    }
}
