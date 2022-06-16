// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.14;

import "./CTokenInterface.sol";

interface CETHInterface is CTokenInterface{    
    function mint() external payable returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow() external payable returns (uint);
}