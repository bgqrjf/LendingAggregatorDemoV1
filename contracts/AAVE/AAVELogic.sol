// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProvider.sol";
import "../interfaces/IWETH.sol";

import "./IAAVEPool.sol";
import "./IAAVEInterestRateStrategy.sol";
import "./IAAVEPriceOracleGetter.sol";

import "./AAVEDataTypes.sol";
import "./AAVEReserveConfigurationGetter.sol";
import "../libraries/Utils.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/Types.sol";

contract AAVELogic is IProvider{
    // ray = 1e27 truncate to 1e6
    uint constant public base = 1e21;
    address payable public wrappedNative;

    // mapping underlying to msg.sender;
    mapping(address => address) initialized;

    IAAVEPool public pool;

    receive() external payable {}

    constructor(address _pool, address payable _wrappedNative){
        pool = IAAVEPool(_pool);
        wrappedNative = _wrappedNative;
    }

    function setInitialized(address _underlying) external override {
        initialized[_underlying] = msg.sender;
    }

    function getAddAssetData(address _underlying) external view returns(Types.ProviderData memory data){
        _underlying = replaceNative(_underlying);
        data.target = address(pool);
        data.encodedData = abi.encodeWithSelector(pool.setUserUseReserveAsCollateral.selector, _underlying, true);
    }

    function getSupplyData(address _underlying, uint _amount) external view override returns(Types.ProviderData memory data){
        data.target = address(pool);
        data.approveTo = data.target;
        if (_underlying != TransferHelper.ETH){
            data.encodedData = abi.encodeWithSelector(pool.supply.selector, _underlying, _amount, msg.sender, 0);
        }else{
            data.weth = wrappedNative;
            data.encodedData = abi.encodeWithSelector(pool.supply.selector, data.weth, _amount, msg.sender, 0);
        }

        data.initialized = initialized[_underlying] == msg.sender;
    }

    function getWithdrawData(address _underlying, uint _amount) external view override returns(Types.ProviderData memory data){
        data.target = address(pool);
        if (_underlying != TransferHelper.ETH){
            data.encodedData = abi.encodeWithSelector(pool.withdraw.selector, _underlying, _amount, msg.sender);
        }else{
            data.weth = wrappedNative;
            data.encodedData = abi.encodeWithSelector(pool.withdraw.selector, data.weth, _amount, msg.sender);
        }
    }

    function getWithdrawAllData(address _underlying) external view override returns(Types.ProviderData memory data){
        data.target = address(pool);
        if (_underlying != TransferHelper.ETH){
            data.encodedData = abi.encodeWithSelector(pool.withdraw.selector, _underlying, Utils.MAX_UINT, msg.sender);
        }else{
            data.weth = wrappedNative;
            data.encodedData = abi.encodeWithSelector(pool.withdraw.selector, data.weth, Utils.MAX_UINT, msg.sender);
        }
    }

    function getBorrowData(address _underlying, uint _amount) external view override returns(Types.ProviderData memory data){
        data.target = address(pool);
        if (_underlying != TransferHelper.ETH){
            data.encodedData = abi.encodeWithSelector(pool.borrow.selector, _underlying, _amount, uint(AAVEDataTypes.InterestRateMode.VARIABLE), 0, msg.sender);
        }else{
            data.weth = wrappedNative;
            data.encodedData = abi.encodeWithSelector(pool.borrow.selector, data.weth, _amount, uint(AAVEDataTypes.InterestRateMode.VARIABLE), 0, msg.sender);
        }
    }
 
    function getRepayData(address _underlying, uint _amount) external view override returns(Types.ProviderData memory data){
        data.target = address(pool);
        data.approveTo = data.target;
        if (_underlying != TransferHelper.ETH){
            data.encodedData = abi.encodeWithSelector(pool.borrow.selector, _underlying, _amount, uint(AAVEDataTypes.InterestRateMode.VARIABLE), msg.sender);
        }else{
            data.weth = wrappedNative;
            data.encodedData = abi.encodeWithSelector(pool.borrow.selector, data.weth, _amount, uint(AAVEDataTypes.InterestRateMode.VARIABLE), msg.sender);
        }
    } 

    function supplyOf(address _underlying, address _account) external view override returns (uint) {
        _underlying = replaceNative(_underlying);
        AAVEDataTypes.ReserveData memory reserve = pool.getReserveData(_underlying);
        return TransferHelper.balanceOf(reserve.aTokenAddress, _account);
    }

    function debtOf(address _underlying, address _account) external view override returns (uint) {
        _underlying = replaceNative(_underlying);
        AAVEDataTypes.ReserveData memory reserve = pool.getReserveData(_underlying);
        return TransferHelper.balanceOf(reserve.variableDebtTokenAddress, _account);
    }

    function totalColletralAndBorrow(address _account, address _quote) external view override returns(uint collateralValue, uint borrowedValue){
        _quote = replaceNative(_quote);
        (collateralValue, borrowedValue,,,,) = pool.getUserAccountData(_account);
        IAAVEPriceOracleGetter priceOracle = IAAVEPriceOracleGetter(pool.ADDRESSES_PROVIDER().getPriceOracle());
        uint priceQuote = priceOracle.getAssetPrice(_quote);

        AAVEDataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(_quote);
        (,,,uint decimals,,) = AAVEReserveConfigurationGetter.getParams(configuration);
        uint unit = 10 ** (decimals);

        collateralValue *= unit / priceQuote;
        borrowedValue *= unit / priceQuote;
    }

    // ray to Million
    function getUsageParams(address _underlying) external view override returns (Types.UsageParams memory params){
        _underlying = replaceNative(_underlying);
        AAVEDataTypes.ReserveData memory reserve = pool.getReserveData(_underlying);
        params = Types.UsageParams(
            TransferHelper.totalSupply(reserve.aTokenAddress),
            TransferHelper.totalSupply(reserve.variableDebtTokenAddress) + TransferHelper.totalSupply(reserve.stableDebtTokenAddress),
            truncateBase(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).getVariableRateSlope1()),
            truncateBase(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).getVariableRateSlope2()),
            truncateBase(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).getBaseVariableBorrowRate()),
            truncateBase(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).OPTIMAL_USAGE_RATIO()),
            truncateBase(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).getBaseVariableBorrowRate()),
            uint32(AAVEReserveConfigurationGetter.getReserveFactor(reserve.configuration) * 100)
        );
    }
    
    function replaceNative(address _underlying) internal view returns (address){
        if (_underlying == TransferHelper.ETH){
            return wrappedNative;
        }else{
            return _underlying;
        }
    }

    function truncateBase(uint x) internal pure returns (uint32 y){
        return uint32(x / base);
    }
} 