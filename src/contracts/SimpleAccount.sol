// SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;
import "account-abstraction/interfaces/IAccount.sol";
import "account-abstraction/interfaces/PackedUserOperation.sol";

contract SimpleAccount is IAccount {
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override returns (uint256 validationData)
    // userOp - The operation that is about to be executed .
    // userOpHash - the hash to be presered for signature.
    // missingAccountFunds - - Packaged ValidationData structure. use _packValidationData and _unpackValidationData to encode and decode.
    {
        (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
        require(success, "Trasnfer failed");
        return 0;
    }
}
