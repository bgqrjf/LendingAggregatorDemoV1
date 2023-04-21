// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IDToken.sol";

// DebtToken
abstract contract DTokenSotrage is IDToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    address public override underlying;
    uint256 public override feeRate;
    uint256 public override accFee;
    uint256 public override collectedFee;
    uint256 public override feeIndex;

    mapping(address => uint256) public override balanceOf;
    mapping(address => uint256) public override feeIndexOf;
}
