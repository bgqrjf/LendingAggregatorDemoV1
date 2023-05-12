// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../interfaces/IDToken.sol";
import "../interfaces/IRewards.sol";
import "../interfaces/IRouter.sol";

// DebtToken
abstract contract DTokenSotrage is IDToken {
    IRewards public rewards;
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public override feeRate;
    uint256 public override minBorrow;
    address public override underlying;

    uint256 public override totalSupply;
    uint256 public override accFee;
    uint256 public override collectedFee;
    uint256 public override feeIndex;
    mapping(address => uint256) public override balanceOf;
    mapping(address => uint256) public override feeIndexOf;
}
