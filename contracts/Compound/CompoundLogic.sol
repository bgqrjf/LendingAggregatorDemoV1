// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProvider.sol";
import "./CERC20Interface.sol";
import "./CETHInterface.sol";
import "./ComptrollerInterface.sol";

import "../libraries/Utils.sol";
import "../libraries/TransferHelper.sol";

contract CompoundLogic is IProvider{
    uint constant public base = 1e12;
    
    ComptrollerInterface public comptroller;

    mapping(address => address) cTokens;
    mapping(address => uint) underlyingUnit;

    mapping(address => address) initialized;

    constructor(address _comptroller, address _cETH){
        comptroller = ComptrollerInterface(_comptroller);
        (bool isListed,,) = comptroller.markets(_cETH);
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[TransferHelper.ETH] = _cETH;
        underlyingUnit[_cETH] = 1e18;
    }

    receive() external payable {}

    function setInitialized(address _underlying) external override {
    }

    function getAddAssetData(address _underlying) external view returns(Types.ProviderData memory data){
        address[] memory underlyings = new address[](1);
        underlyings[0] = cTokens[_underlying];
        data.target = address(comptroller);
        data.encodedData = abi.encodeWithSelector(comptroller.enterMarkets.selector, underlyings);
    }

    // call by delegates public functions
    function getSupplyData(address _underlying, uint _amount) external view override returns(Types.ProviderData memory data){
        data.target = cTokens[_underlying];
        if (_underlying == TransferHelper.ETH){
            data.encodedData = abi.encodeWithSelector(CETHInterface.mint.selector);
        }else{
            data.approveTo = data.target;
            data.encodedData = abi.encodeWithSelector(CERC20Interface.mint.selector, _amount);
        } 
        data.initialized = initialized[_underlying] == msg.sender;
    }

    function getWithdrawData(address _underlying, uint _amount) external view override returns(Types.ProviderData memory data){
        data.target = cTokens[_underlying];
        data.encodedData = abi.encodeWithSelector(CERC20Interface.redeem.selector, _amount);
    }

    function getWithdrawAllData(address _underlying) external view override returns(Types.ProviderData memory data){
        data.target = cTokens[_underlying];
        data.encodedData = abi.encodeWithSelector(CERC20Interface.redeem.selector, CERC20Interface(data.target).balanceOf(address(this)));
    }

    function getBorrowData(address _underlying, uint _amount)external view override returns(Types.ProviderData memory data){
        data.target = cTokens[_underlying];
        data.encodedData = abi.encodeWithSelector(CERC20Interface.borrow.selector, _amount);
    }

    function getRepayData(address _underlying, uint _amount) external view override returns(Types.ProviderData memory data){
        data.target = cTokens[_underlying];
        if (_underlying == TransferHelper.ETH){
            data.encodedData = abi.encodeWithSelector(CETHInterface.repayBorrow.selector);
        }else{
            data.approveTo = data.target;
            data.encodedData = abi.encodeWithSelector(CERC20Interface.repayBorrow.selector, _amount);
        } 
    } 

    // return underlying Token
    // return data for caller
    function supplyOf(address _underlying, address _account) external view override returns (uint) {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (uint totalCash, uint totalBorrows, uint totalReserves, ) = accrueInterest(_underlying, cToken);
        uint cTokentotalSupply = cToken.totalSupply();
        return cTokentotalSupply > 0 ? (totalCash + totalBorrows - totalReserves) * cToken.balanceOf(_account) / cTokentotalSupply : 0;
    }

    function debtOf(address _underlying, address _account) external view override returns (uint) {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (,,, uint borrowIndex) = accrueInterest(_underlying, cToken);
        return cToken.borrowBalanceStored(_account) * borrowIndex  /  cToken.borrowIndex();
    }

    function totalColletralAndBorrow(address _account, address _quote) external view returns (uint collateralValue, uint borrowValue){
        // For each asset the account is in
        CTokenInterface[] memory userCTokens = comptroller.getAssetsIn(_account);
        IOracle oracle = comptroller.oracle();
        for (uint i = 0; i < userCTokens.length; i++) {
            CTokenInterface cToken = userCTokens[i];
            // Read the balances and exchange rate from the cToken
            (, uint cTokenBalance, uint borrowBalance, uint exchangeRate) = cToken.getAccountSnapshot(_account);

            uint oraclePrice = oracle.getUnderlyingPrice(cToken);
            require(oraclePrice > 0, "Compound Logic: Price Not found");

            uint underlyingAmount = cTokenBalance * exchangeRate / Utils.QUINTILLION;
            collateralValue += (underlyingAmount * oraclePrice / Utils.QUINTILLION) * underlyingUnit[address(cToken)] / Utils.QUINTILLION;
            borrowValue += (borrowBalance * oraclePrice / Utils.QUINTILLION) * underlyingUnit[address(cToken)] / Utils.QUINTILLION;
        }

        address cQuote = cTokens[_quote];
        uint oraclePriceQuote = oracle.getUnderlyingPrice(CTokenInterface(cQuote));
        require(oraclePriceQuote > 0, "Compound Logic: Price Not found");

        uint factor = Utils.QUINTILLION * Utils.QUINTILLION / underlyingUnit[cQuote];
        collateralValue = collateralValue * factor / oraclePriceQuote ;
        borrowValue = borrowValue * factor / oraclePriceQuote;
    }

    function getUsageParams(address _underlying) external view override returns (Types.UsageParams memory params){
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (uint totalCash, uint totalBorrows, uint totalReserves,) = accrueInterest(_underlying, cToken);

        InterestRateModel interestRateModel = cToken.interestRateModel();

        params = Types.UsageParams(
            totalCash + totalBorrows - totalReserves,
            totalBorrows,
            truncateBase(interestRateModel.multiplierPerBlock()),
            truncateBase(interestRateModel.jumpMultiplierPerBlock()),
            truncateBase(interestRateModel.baseRatePerBlock()),
            truncateBase(interestRateModel.kink()),
            truncateBase(cToken.borrowRatePerBlock()),
            truncateBase(cToken.reserveFactorMantissa())
        );
    }

    function updateCTokenList(address _cToken, uint _decimals) external {
        (bool isListed,,) = comptroller.markets(address(_cToken));
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[CTokenInterface(_cToken).underlying()] = _cToken;
        underlyingUnit[_cToken] = 10 ** _decimals;
    }

    function truncateBase(uint x) internal pure returns (uint32 y){
        return uint32(x / base);
    }

    function getAccountSnapshot(CTokenInterface cToken, address account) internal view returns (uint, uint, uint) {
        address underlying;
        if (address(cToken) == cTokens[TransferHelper.ETH]){
            underlying == TransferHelper.ETH;
        }else{
            underlying == cToken.underlying();
        }

        (uint totalCash, uint totalBorrows, uint totalReserves, uint _borrowIndexCurrent) = accrueInterest(underlying, cToken);
        uint totalSupply = cToken.totalSupply();

        return (
            cToken.balanceOf(account),
            cToken.borrowBalanceStored(account) * _borrowIndexCurrent / cToken.borrowIndex(),
            totalSupply > 0 ? (totalCash + totalBorrows - totalReserves) * Utils.QUINTILLION / totalSupply : 0
        );
    }

    function accrueInterest(address _underlying, CTokenInterface _cToken) internal view returns (uint totalCash, uint totalBorrows, uint totalReserves, uint borrowIndex) {
        totalCash = TransferHelper.balanceOf(_underlying, address(_cToken));
        totalBorrows = _cToken.totalBorrows();
        totalReserves = _cToken.totalReserves();
        borrowIndex = _cToken.borrowIndex();

        uint blockDelta =  block.number - _cToken.accrualBlockNumber();

        if (blockDelta > 0) {
            uint borrowRateMantissa = _cToken.interestRateModel().getBorrowRate(totalCash, totalBorrows, totalReserves);
            uint simpleInterestFactor = borrowRateMantissa * blockDelta;
            uint interestAccumulated = simpleInterestFactor * totalBorrows / Utils.QUINTILLION;
            totalBorrows = interestAccumulated + totalBorrows;
            totalReserves = _cToken.reserveFactorMantissa() * interestAccumulated / Utils.QUINTILLION + totalReserves;
            borrowIndex = simpleInterestFactor * borrowIndex / Utils.QUINTILLION + borrowIndex;
        }
    }

}