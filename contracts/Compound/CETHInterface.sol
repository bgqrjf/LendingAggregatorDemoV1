// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.18;

import "./CTokenInterface.sol";

interface CETHInterface is CTokenInterface {
    function mint() external payable;

    function redeem(uint256 redeemTokens) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow() external payable;
}
