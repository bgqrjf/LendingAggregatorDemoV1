// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.14;

import "./InterestRateModel.sol";

interface CTokenInterface {    
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    
    function balanceOf(address owner) external view returns (uint);
    function totalSupply() external view returns(uint);

    function borrowBalanceStore() external view returns (uint);
    function borrowIndex() external view returns (uint);
    function interestRateModel() external view returns(InterestRateModel);
    function borrowRatePerBlock() external view returns (uint);
    function reserveFactorMantissa() external view returns (uint);
    function accrualBlockNumber() external view returns(uint);
    function underlying() external view returns(address);
    function totalBorrows() external view returns (uint);
    function totalReserves() external view returns (uint);
}