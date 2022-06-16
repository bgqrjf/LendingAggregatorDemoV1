// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProvider.sol";
import "./CERC20Interface.sol";
import "./CETHInterface.sol";
import "./ComptrollerLensInterface.sol";

import "../libraries/Utils.sol";
import "../libraries/TransferHelper.sol";

contract CompoundLogic is IProvider{
    uint constant public base = 1e12;
    
    ComptrollerLensInterface public comptroller;

    mapping(address => address) cTokens;

    constructor(address _comptroller){
        comptroller = ComptrollerLensInterface(_comptroller);
    }

    receive() external payable {}

    // call by delegates public functions
    function supply (address _underlying, uint _amount) external payable override{
        if (_underlying == TransferHelper.ETH){
            CETHInterface(payable(cTokens[_underlying])).mint{value: _amount}();
        }else{
            CERC20Interface(cTokens[_underlying]).mint(_amount);
        } 
    }

    function withdraw(address _underlying, uint _amount) external override{
        CERC20Interface(cTokens[_underlying]).redeem(_amount);
    }

    function withdrawAll(address _underlying) external override{
        CERC20Interface cToken = CERC20Interface(cTokens[_underlying]);
        cToken.redeem(cToken.balanceOf(address(this)));
    }

    function borrow (address _underlying, uint _amount) external override{
       CERC20Interface(cTokens[_underlying]).borrow(_amount);
    }

    function repay(address _underlying, uint _amount) external payable override{
        if (_underlying == TransferHelper.ETH){
            CETHInterface(payable(cTokens[_underlying])).repayBorrow{value: _amount}();
        }else{
            CERC20Interface(cTokens[_underlying]).repayBorrow(_amount);
        } 
    } 

    // return underlying Token
    // return data for caller
    function supplyOf(address _underlying, address _account) external view override returns (uint) {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (uint totalCash, uint totalBorrows, uint totalReserves, ) = accrueInterest(_underlying, cToken);
        return (totalCash + totalBorrows - totalReserves) * cToken.balanceOf(_account) / cToken.totalSupply();
    }

    function debtOf(address _underlying, address _account) external view override returns (uint) {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (,,, uint borrowIndex) = accrueInterest(_underlying, cToken);
        return cToken.borrowBalanceStore(_account) * borrowIndex  /  cToken.borrowIndex();
    }

    function totalColletralAndBorrow(address _account, address _quote) external view returns (uint collateralValue, uint borrowValue){
        // For each asset the account is in
        CTokenInterface[] memory assets = comptroller.accountAssets(_account);
        for (uint i = 0; i < assets.length; i++) {
            CTokenInterface asset = assets[i];

            // Read the balances and exchange rate from the cToken
            (, uint cTokenBalance, uint borrowBalance, uint exchangeRate) = asset.getAccountSnapshot(_account);

            uint oraclePrice = comptroller.oracle().getUnderlyingPrice(asset);
            require(oraclePrice > 0, "Compound Logic: Price Not found");

            uint underlyingAmount = cTokenBalance * exchangeRate / Utils.QUINTILLION;
            collateralValue += underlyingAmount * oraclePrice / Utils.QUINTILLION ;
            borrowValue += oraclePrice * borrowBalance;
        }

        uint oraclePriceQuote = comptroller.oracle().getUnderlyingPrice(CTokenInterface(cTokens[_quote]));
        require(oraclePriceQuote > 0, "Compound Logic: Price Not found");

        collateralValue = collateralValue * oraclePriceQuote / Utils.QUINTILLION;
        borrowValue = collateralValue * oraclePriceQuote / Utils.QUINTILLION;
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
        cTokens[CTokenInterface(_cToken).underlying()] = _cToken;
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
            uint borrowRateMantissa = cToken.interestRateModel().getBorrowRate(totalCash, totalBorrows, totalReserves);
            uint simpleInterestFactor = borrowRateMantissa * blockDelta;
            uint interestAccumulated = simpleInterestFactor * totalBorrows / Utils.QUINTILLION;
            totalBorrows = interestAccumulated + totalBorrows;
            totalReserves = cToken.reserveFactorMantissa() * interestAccumulated / Utils.QUINTILLION + totalReserves;
            borrowIndex = simpleInterestFactor * borrowIndex / Utils.QUINTILLION + borrowIndex;
        }
    }
}