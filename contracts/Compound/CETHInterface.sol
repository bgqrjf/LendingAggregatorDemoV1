// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.18;

import "./InterestRateModel.sol";

interface CETHInterface {
    function mint() external payable;

    function redeem(uint256 redeemTokens) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow() external payable;

    function balanceOf(address owner) external view returns (uint256);

    function balanceOfUnderlying(address owner) external view returns (uint256);

    function getAccountSnapshot(
        address account
    ) external view returns (uint256, uint256, uint256, uint256);

    function totalSupply() external view returns (uint256);

    function borrowBalanceStored(
        address account
    ) external view returns (uint256);

    function borrowIndex() external view returns (uint256);

    function interestRateModel() external view returns (InterestRateModel);

    function supplyRatePerBlock() external view returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function reserveFactorMantissa() external view returns (uint256);

    function accrualBlockNumber() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function totalReserves() external view returns (uint256);
}
