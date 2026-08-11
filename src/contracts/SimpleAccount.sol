// SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;
import "account-abstraction/interfaces/IAccount.sol";
import "account-abstraction/interfaces/PackedUserOperation.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";

contract SimpleAccount is IAccount {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override returns (uint256 validationData)
    // userOp - The operation that is about to be executed .
    // userOpHash - the hash to be presered for signature.
    // missingAccountFunds - - Packaged ValidationData structure. use _packValidationData and _unpackValidationData to encode and decode.
    {
        address signer = ECDSA.recover(userOpHash, userOp.signature);
        if (signer != owner) {
            return SIG_VALIDATION_FAILED;
        }
        (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
        require(success, "Trasnfer failed");
        return SIG_VALIDATION_SUCCESS;
    }
}
