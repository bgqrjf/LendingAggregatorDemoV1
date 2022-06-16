// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.14;

import "./CTokenInterface.sol";

interface CERC20Interface is CTokenInterface{    
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
}