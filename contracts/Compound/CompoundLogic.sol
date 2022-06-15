// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProvider.sol";
import "./CTokenInterface.sol";
import "./ComptrollerLensInterface.sol";

import "../libraries/Utils.sol";
import "../libraries/TransferHelper.sol";

contract CompoundLogic is IProvider{
    uint constant public base = 1e12;
    
    ComptrollerLensInterface public comptroller;

    mapping(address => CTokenInterface) cTokens;

    constructor(address _comptroller){
        comptroller = ComptrollerLensInterface(_comptroller);
    }

    // call by delegates public functions
    function supply (address _underlying, uint _amount) external override{
        cTokens[_underlying].mint(_amount);
    }

    function withdraw(address _underlying, uint _amount) external override{
        cTokens[_underlying].redeem(_amount);
    }

    function withdrawAll(address _underlying) external override{
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        cToken.redeem(cToken.balanceOf(address(this)));
    }

    function borrow (address _underlying, uint _amount) external override{
        cTokens[_underlying].borrow(_amount);
    }

    function repay(address _underlying, uint _amount) external override{
        cTokens[_underlying].repayBorrow(_amount);
    } 

    // return underlying Token
    // return data for caller
    function supplyOf(address _underlying) external view override returns (uint) {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (uint totalCash, uint totalBorrows, uint totalReserves, ) = accrueInterest(_underlying, cToken);
        return (totalCash + totalBorrows - totalReserves) * cToken.balanceOf(msg.sender) / cToken.totalSupply();
    }

    function debtOf(address _underlying) external view override returns (uint) {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (,,, uint borrowIndex) = accrueInterest(_underlying, cToken);
        return cToken.borrowBalanceStore() * borrowIndex /  cToken.borrowIndex();
    }

    function getUsageParams(address _underlying) external view override returns (Types.UsageParams memory params){
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (uint totalCash, uint totalBorrows, uint totalReserves,) = accrueInterest(_underlying, cToken);
        
        params = Types.UsageParams(
            totalCash + totalBorrows - totalReserves,
            totalBorrows,
            truncateBase(cToken.interestRateModel().multiplierPerBlock()),
            truncateBase(cToken.interestRateModel().jumpMultiplierPerBlock()),
            truncateBase(cToken.interestRateModel().baseRatePerBlock()),
            truncateBase(cToken.interestRateModel().kink()),
            truncateBase(cToken.borrowRatePerBlock()),
            truncateBase(cToken.reserveFactorMantissa())
        );
    }

    function updateCTokenList(address _cToken) external {
        (bool isListed,,) = comptroller.markets(address(_cToken));
        require(isListed, "CompoundLogic: cToken Not Listed");
        CTokenInterface cToken = CTokenInterface(_cToken);
        cTokens[cToken.underlying()] = cToken;
    }

    function truncateBase(uint x) internal pure returns (uint32 y){
        return uint32(x / base);
    }

    function accrueInterest(address underlying, CTokenInterface cToken) internal view returns (uint totalCash, uint totalBorrows, uint totalReserves, uint borrowIndex) {
        /* Read the previous values out of storage */
        totalCash = TransferHelper.balanceOf(underlying, msg.sender);
        totalBorrows = cToken.totalBorrows();
        totalReserves = cToken.totalReserves();
        borrowIndex = cToken.borrowIndex();

        uint blockDelta =  block.number - cToken.accrualBlockNumber();

        if (blockDelta > 0) {
            /* Calculate the number of blocks elapsed since the last accrual */
            uint borrowRateMantissa = cToken.interestRateModel().getBorrowRate(totalCash, totalBorrows, totalReserves);
            uint simpleInterestFactor = borrowRateMantissa * blockDelta;
            uint interestAccumulated = simpleInterestFactor * totalBorrows / Utils.QUINTILLION;
            totalBorrows = interestAccumulated + totalBorrows;
            totalReserves = cToken.reserveFactorMantissa() * interestAccumulated / Utils.QUINTILLION + totalReserves;
            borrowIndex = simpleInterestFactor * borrowIndex / Utils.QUINTILLION + borrowIndex;
        }
    }
}