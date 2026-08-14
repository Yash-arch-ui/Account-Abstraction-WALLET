//SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;
import {IPaymaster} from "account-abstraction/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenPaymaster is IPaymaster {
    IERC20 public immutable token;
    uint256 public exchangeRate;
    address public immutable entryPoint;

    constructor(address _token, address _entryPoint, uint256 _exchangeRate) {
        token = IERC20(_token);
        entryPoint = _entryPoint;
        exchangeRate = _exchangeRate;
    }

    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        returns (bytes memory context, uint256 validationData)
    {
        /*
        the core goal of validationUserOp is to detemine whether
        your paymaster agrees to sponsor the transaction and whether
         the user has enough resources to cover the maximum possible cost
        */
        require(msg.sender == entryPoint, "TokenPaymaster: not from EntryPoint");
        // 1. ensure the caller is the trusted EntryPoint contract to prevent unauthorized invocations
        address sender = userOp.sender; //extract the users account address
        bytes memory customData = userOp.paymasterAndData; // extract the paymasterAndData field from the user operation

        // 3. maxTokenCost = maxCost*exchangeRate/PrecisionFactor
        uint256 maxTokenCost = maxCost * exchangeRate / 1e18;
        // 4. Verify that the userOp.sender:
        // has enough token balance to cover the maximum token cost
        // has granted approval to the paymaster to spend the required amount of tokens on their behalf
        if (token.balanceOf(sender) < maxTokenCost || token.allowance(sender, address(this)) < maxTokenCost) {
            return ("", 1); // Return an error code if the user doesn't have enough balance or allowance
        }
        // Pack the quote (maxCost in wei) and the exchangeRate so postOp can recompute
        // the real, cheaper charge once it knows the actual gas cost.
        context = abi.encode(sender, maxCost, exchangeRate);
        validationData = 0;
    }

    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        external
    {
        // Ensure caller is EntryPoint
        require(msg.sender == entryPoint, "Paymaster: caller not EntryPoint");
        // Decode context passed from validatePaymasterUserOp.
        // rate = exchangeRate (tokens per 1 ETH, scaled by 1e18) as packed during validation.
        (address sender, uint256 maxCost, uint256 rate) = abi.decode(context, (address, uint256, uint256));
        // 3. Handle postOpReverted mode to prevent infinite revert loops
        if (mode == PostOpMode.postOpReverted) {
            // Do not attempt transfer again or throw; log or ignore
            // to ensure Paymaster doesn't fail the EntryPoint's fallback logic.
            return;
        }

        // 4. Convert the real ETH gas cost into an ERC-20 token amount.
        // The user was quoted (maxCost * exchangeRate / 1e18) tokens for up to maxCost wei;
        // now that actualGasCost is known (usually < maxCost), charge proportionally.
        uint256 maxTokenCost = (maxCost * rate) / 1e18;
        uint256 tokenAmount = (maxTokenCost * actualGasCost) / maxCost;

        // 6. Transfer tokens from user's account to Paymaster
        // User MUST have approved Paymaster to spend `tokenAmount` prior to or during UserOp
        bool success = token.transferFrom(sender, address(this), tokenAmount);
        require(success, "Paymaster: token transfer failed");
    }
}
