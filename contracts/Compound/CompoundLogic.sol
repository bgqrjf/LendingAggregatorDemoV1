// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProtocol.sol";
import "./CERC20Interface.sol";
import "./CETHInterface.sol";
import "./ComptrollerInterface.sol";

import "../libraries/Utils.sol";
import "../libraries/Math.sol";
import "../libraries/TransferHelper.sol";

contract CompoundLogic is IProtocol{
    using Math for uint;

    struct SimulateSupplyData{
        uint cTokenAmount;
        uint underlyingValue;
    }

    struct SimulateBorrowData{
        uint amount;
        uint index;
    }

    uint public immutable BASE = 1e12;
    uint public immutable BLOCK_PER_YEAR = 2102400;
    
    ComptrollerInterface public comptroller;
    address public compTokenAddress;

    mapping(address => address) public cTokens;
    mapping(address => uint) public underlyingUnit;

    mapping(address => address) public initialized;
    mapping(address => SimulateSupplyData) public lastSimulatedSupply;
    mapping(address => SimulateBorrowData) public lastSimulatedBorrow;


    constructor(address _comptroller, address _cETH, address _compTokenAddress){
        comptroller = ComptrollerInterface(_comptroller);
        (bool isListed,,) = comptroller.markets(_cETH);
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[TransferHelper.ETH] = _cETH;
        underlyingUnit[_cETH] = 1e18;

        compTokenAddress = _compTokenAddress;
    }

    receive() external payable {}

    function setInitialized(address _underlying) external override {
    }

    function updateSupplyShare(address _underlying, uint _amount) external override{
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        uint cTokenSupply = cToken.totalSupply();
        (uint totalCash, uint totalBorrows, uint totalReserves,) = accrueInterest(_underlying, cToken);
        uint underlyingValue = totalCash + totalBorrows - totalReserves;

        lastSimulatedSupply[_underlying] = SimulateSupplyData(
            _amount * cTokenSupply / underlyingValue,
            _amount
        );
    }

    function updateBorrowShare(address _underlying, uint _amount) external override{
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (,,, uint borrowIndex) = accrueInterest(_underlying, cToken);
        lastSimulatedBorrow[_underlying] = SimulateBorrowData(_amount, borrowIndex);
    }

    function lastSupplyInterest(address _underlying) external view override returns(uint){
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        uint cTokenSupply = cToken.totalSupply();
        (uint totalCash, uint totalBorrows, uint totalReserves,) = accrueInterest(_underlying, cToken);
        uint underlyingValue = totalCash + totalBorrows - totalReserves;
        return lastSimulatedSupply[_underlying].cTokenAmount * underlyingValue / cTokenSupply;
    }

    function lastBorrowInterest(address _underlying) external view override returns(uint){
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (,,, uint borrowIndex) = accrueInterest(_underlying, cToken);

        return lastSimulatedBorrow[_underlying].amount * borrowIndex / lastSimulatedBorrow[_underlying].index - lastSimulatedBorrow[_underlying].amount;
    }

    function getAddAssetData(address _underlying) external view returns(Types.ProtocolData memory data){
        address[] memory underlyings = new address[](1);
        underlyings[0] = cTokens[_underlying];
        data.target = address(comptroller);
        data.encodedData = abi.encodeWithSelector(comptroller.enterMarkets.selector, underlyings);
    }

    // call by delegates public functions
    function getSupplyData(address _underlying, uint _amount) external view override returns(Types.ProtocolData memory data){
        data.target = cTokens[_underlying];
        if (_underlying == TransferHelper.ETH){
            data.encodedData = abi.encodeWithSelector(CETHInterface.mint.selector);
        }else{
            data.approveTo = data.target;
            data.encodedData = abi.encodeWithSelector(CERC20Interface.mint.selector, _amount);
        } 
        data.initialized = initialized[_underlying] == msg.sender;
    }

    function getRedeemData(address _underlying, uint _amount) external view override returns(Types.ProtocolData memory data){
        data.target = cTokens[_underlying];
        uint cTokenSupply = CTokenInterface(data.target).totalSupply();
        (uint totalCash, uint totalBorrows, uint totalReserves,) = accrueInterest(_underlying, CTokenInterface(data.target));
        uint underlyingValue = totalCash + totalBorrows - totalReserves;

        data.encodedData = abi.encodeWithSelector(CERC20Interface.redeem.selector, underlyingValue > 0 ? _amount * cTokenSupply / underlyingValue : 0);
    }

    function getRedeemAllData(address _underlying) external view override returns(Types.ProtocolData memory data){
        data.target = cTokens[_underlying];
        data.encodedData = abi.encodeWithSelector(CERC20Interface.redeem.selector, CERC20Interface(data.target).balanceOf(address(this)));
    }

    function getBorrowData(address _underlying, uint _amount)external view override returns(Types.ProtocolData memory data){
        data.target = cTokens[_underlying];
        data.encodedData = abi.encodeWithSelector(CERC20Interface.borrow.selector, _amount);
    }

    function getRepayData(address _underlying, uint _amount) external view override returns(Types.ProtocolData memory data){
        data.target = cTokens[_underlying];
        if (_underlying == TransferHelper.ETH){
            data.encodedData = abi.encodeWithSelector(CETHInterface.repayBorrow.selector);
        }else{
            data.approveTo = data.target;
            data.encodedData = abi.encodeWithSelector(CERC20Interface.repayBorrow.selector, _amount);
        } 
    } 

    function getClaimRewardData(address _rewardToken) external view override returns(Types.ProtocolData memory data){
        data.target = address(comptroller);
        data.encodedData = abi.encodeWithSelector(ComptrollerInterface.claimComp.selector, msg.sender);
    }

    function getClaimUserRewardData(address _underlying, Types.UserShare memory _share, bytes memory _user, bytes memory _router) external view override returns (bytes memory, bytes memory, address, uint){
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        Types.UserCompRewardData memory userRewardData = abi.decode(_user, (Types.UserCompRewardData));
        Types.RouterCompRewardData memory routerRewardData  = abi.decode(_router, (Types.RouterCompRewardData));
        
        routerRewardData = newSupplyReward(cToken, routerRewardData, _share.total);
        routerRewardData = newBorrowReward(cToken, routerRewardData, _share.total);

        userRewardData.supply.rewardAccured += (routerRewardData.supply.rewardPerShare - userRewardData.supply.rewardPerShare) * _share.amount;
        userRewardData.supply.rewardPerShare = routerRewardData.supply.rewardPerShare;
        userRewardData.borrow.rewardAccured += (routerRewardData.borrow.rewardPerShare - userRewardData.borrow.rewardPerShare) * _share.amount;
        userRewardData.borrow.rewardPerShare = routerRewardData.borrow.rewardPerShare;

        uint amount = userRewardData.supply.rewardAccured - userRewardData.supply.rewardCollected + userRewardData.borrow.rewardAccured - userRewardData.borrow.rewardCollected;
        userRewardData.supply.rewardCollected = userRewardData.supply.rewardAccured;
        userRewardData.borrow.rewardCollected = userRewardData.borrow.rewardAccured;
        return (abi.encode(userRewardData), abi.encode(routerRewardData), compTokenAddress, amount);
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

    function supplyToTargetSupplyRate(uint _targetRate, bytes memory _params) external pure override returns (int){
        Types.CompoundUsageParams memory params = abi.decode(_params, (Types.CompoundUsageParams));

        _targetRate = _targetRate * Utils.MILLION / params.reserveFactor;

        uint delta = params.base * params.base + 4 * params.slope1 * _targetRate;
        uint supply = params.totalBorrowed * (params.base  + delta.sqrt()) / (_targetRate + _targetRate);

        if (params.totalBorrowed * Utils.MILLION > supply * params.optimalLTV){
            params.base +=  params.optimalLTV * params.slope1 / Utils.MILLION;

            uint a = params.slope2 * params.optimalLTV - params.base * Utils.MILLION;
            delta = (a / Utils.MILLION) ** 2 + 4 * params.slope2 * _targetRate;
            supply = params.totalBorrowed * (Utils.MILLION * delta.sqrt() - a) / ((_targetRate + _targetRate) * Utils.MILLION);
        }

        return int(supply) - int(params.totalSupplied);
    }

    function borrowToTargetBorrowRate(uint _targetRate, bytes memory _params) external pure returns (int){
        Types.CompoundUsageParams memory params = abi.decode(_params, (Types.CompoundUsageParams));
        
        if (_targetRate < params.base){
            _targetRate = params.base;
        }

        uint borrow = ((_targetRate - params.base) * params.totalSupplied) / (params.slope1);

        if (borrow * Utils.MILLION > params.totalSupplied * params.optimalLTV){
            params.base += params.optimalLTV * params.slope1 / Utils.MILLION;
            borrow = (((_targetRate - params.base) * Utils.MILLION + params.optimalLTV * params.slope2 ) * params.totalSupplied) / (params.slope2 * Utils.MILLION);
        }

        return int(borrow) - int(params.totalBorrowed);
    }


    function getUsageParams(address _underlying, uint _suppliesToRedeem) external view override returns (bytes memory){
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (uint totalCash, uint totalBorrows, uint totalReserves,) = accrueInterest(_underlying, cToken);

        InterestRateModel interestRateModel = cToken.interestRateModel();

        Types.CompoundUsageParams memory params = Types.CompoundUsageParams(
            totalCash + totalBorrows - totalReserves - _suppliesToRedeem,
            totalBorrows,
            interestRateModel.multiplierPerBlock() * BLOCK_PER_YEAR / BASE,
            interestRateModel.jumpMultiplierPerBlock() * BLOCK_PER_YEAR / BASE,
            interestRateModel.baseRatePerBlock() * BLOCK_PER_YEAR / BASE,
            interestRateModel.kink() / BASE,
            Utils.MILLION - cToken.reserveFactorMantissa() / BASE
        );

        return abi.encode(params);
    }

    function updateCTokenList(address _cToken, uint _decimals) external {
        (bool isListed,,) = comptroller.markets(address(_cToken));
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[CTokenInterface(_cToken).underlying()] = _cToken;
        underlyingUnit[_cToken] = 10 ** _decimals;
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

    function getCurrentSupplyRate(address _underlying) external view override returns (uint){
        return CTokenInterface(cTokens[_underlying]).supplyRatePerBlock() * BLOCK_PER_YEAR / BASE;
    }
    
    function getCurrentBorrowRate(address _underlying) external view override returns (uint){
        return CTokenInterface(cTokens[_underlying]).borrowRatePerBlock() * BLOCK_PER_YEAR / BASE;
    }

    function getRewardSupplyData(address _underlying, Types.UserShare memory _share, bytes memory _user, bytes memory _router) external view override returns (bytes memory, bytes memory){
        Types.RouterCompRewardData memory routerRewardData = newSupplyReward(CTokenInterface(cTokens[_underlying]), abi.decode(_router, (Types.RouterCompRewardData)), _share.total);

        Types.UserCompRewardData memory userRewardData;
        if(_share.amount > 0){
            userRewardData = abi.decode(_user, (Types.UserCompRewardData));
        }

        userRewardData.supply.rewardAccured += (routerRewardData.supply.rewardPerShare - userRewardData.supply.rewardPerShare) * _share.amount;
        userRewardData.supply.rewardPerShare = routerRewardData.supply.rewardPerShare;

        return (abi.encode(userRewardData), abi.encode(routerRewardData));
    }

    function getRouterRewardSupplyData(address _underlying, uint _totalShare, bytes memory _router) external view override returns (bytes memory){
        return abi.encode(newSupplyReward(CTokenInterface(cTokens[_underlying]), abi.decode(_router, (Types.RouterCompRewardData)), _totalShare));
    }

    function getRewardBorrowData(address _underlying, Types.UserShare memory _share, bytes memory _user, bytes memory _router) external view override returns (bytes memory, bytes memory){
        Types.RouterCompRewardData memory routerRewardData = newBorrowReward(CTokenInterface(cTokens[_underlying]), abi.decode(_router, (Types.RouterCompRewardData)), _share.total);

        Types.UserCompRewardData memory userRewardData;
        if(_share.amount > 0){
            userRewardData = abi.decode(_user, (Types.UserCompRewardData));
        }

        userRewardData.borrow.rewardAccured += (routerRewardData.borrow.rewardPerShare - userRewardData.borrow.rewardPerShare) * _share.amount;
        userRewardData.borrow.rewardPerShare = routerRewardData.borrow.rewardPerShare;

        return (abi.encode(userRewardData), abi.encode(routerRewardData));
    }

    function newSupplyReward(CTokenInterface cToken, Types.RouterCompRewardData memory _params, uint _totalShare) internal view returns (Types.RouterCompRewardData memory){
        (uint supplyIndex, ) = comptroller.compSupplyState(address(cToken));
        uint amount = cToken.balanceOf(msg.sender) * (supplyIndex - _params.supply.index) / Utils.UNDECILLION; 
        _params.supply.index = supplyIndex;
        _params.supply.rewardPerShare += amount / _totalShare;
        return _params;
    }

    function newBorrowReward(CTokenInterface cToken, Types.RouterCompRewardData memory _params, uint _totalShare) internal view returns (Types.RouterCompRewardData memory){
        (uint borrowIndex, ) = comptroller.compBorrowState(address(cToken));
        uint amount = cToken.borrowBalanceStored(msg.sender) * Utils.QUINTILLION / cToken.borrowIndex();
        amount = (amount * (borrowIndex - _params.borrow.index) /  Utils.UNDECILLION);

        _params.borrow.index = borrowIndex;
        _params.borrow.rewardPerShare += amount / _totalShare;
        return _params;
    }
}