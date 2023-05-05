// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.18;

import "./CTokenInterface.sol";

interface CERC20Interface is CTokenInterface {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);
}
