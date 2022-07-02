// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.14;

import "./InterestRateModel.sol";

interface CTokenInterface {
    function balanceOf(address owner) external view returns (uint);
    function balanceOfUnderlying(address owner) external view returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    function totalSupply() external view returns(uint);

    function borrowBalanceStored(address account) external view returns (uint);
    function borrowIndex() external view returns (uint);
    function interestRateModel() external view returns(InterestRateModel);
    function supplyRatePerBlock() external view returns (uint);
    function borrowRatePerBlock() external view returns (uint);
    function reserveFactorMantissa() external view returns (uint);
    function accrualBlockNumber() external view returns(uint);
    function underlying() external view returns(address);
    function totalBorrows() external view returns (uint);
    function totalReserves() external view returns (uint);
}