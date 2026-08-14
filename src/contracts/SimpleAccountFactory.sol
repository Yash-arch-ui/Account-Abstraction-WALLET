//SPDX-License-identifier:MIT
pragma solidity ^0.8.20;
import "./SimpleAccount.sol";

contract SimpleAccountFactory {
    // The account's constructor now takes the EntryPoint too, so the factory
    // must know it in order to deploy accounts and predict their addresses.
    address public immutable entryPoint;

    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
    }

    function createAccount(address owner, uint256 salt) public returns (SimpleAccount) {
        // step 1: figure out what address this WOULD be deployed to
        // step 2: if something is already deployed there, just return it, don't redeploy
        // step 3: otherwise, actually deploy it at that deterministic address

        address addr = getAddress(owner, salt);
        if (addr.code.length > 0) {
            return SimpleAccount(payable(addr));
        }
        SimpleAccount account = new SimpleAccount{salt: bytes32(salt)}(entryPoint, owner);
        return account;
    }

    function getAddress(address owner, uint256 salt) public view returns (address) {
        // needs to compute the SAME address createAccount would produce,
        // without actually deploying anything
        //
        // CREATE2: keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))
        // - deployer is THIS contract (the one calling CREATE2), not the owner
        // - initCode is the creation bytecode with the constructor args baked
        //   in, then hashed
        bytes32 bytecodeHash = keccak256(abi.encodePacked(type(SimpleAccount).creationCode, abi.encode(entryPoint, owner)));
        address addr = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), bytecodeHash))))
        );
        return addr;
    }
}
