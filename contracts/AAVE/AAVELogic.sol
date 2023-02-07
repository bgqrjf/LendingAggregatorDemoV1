// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProtocol.sol";
import "../interfaces/IWETH.sol";

import "./IAToken.sol";
import "./IVariableDebtToken.sol";
import "./IAAVEInterestRateStrategy.sol";
import "./IAAVEPriceOracleGetter.sol";

import "./AAVEDataTypes.sol";
import "./AAVEReserveConfigurationGetter.sol";
import "../libraries/internals/Utils.sol";
import "../libraries/internals/TransferHelper.sol";
import "../libraries/internals/Types.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./AAVELogicStorage.sol";

contract AAVELogic is IProtocol {
    using Math for uint256;

    AAVELogicStorage public immutable LOGIC_STORAGE;
    // ray = 1e27 truncate to 1e6
    uint256 public immutable RAY = 1e27;
    uint256 public immutable BASE = 1e21;

    receive() external payable {}

    constructor(
        address _protocolsHandler,
        address _pool,
        address payable _wrappedNative
    ) {
        // for testing purpose
        if (_protocolsHandler == address(0)) {
            _protocolsHandler = address(this);
        }
        LOGIC_STORAGE = new AAVELogicStorage(
            _protocolsHandler,
            _pool,
            _wrappedNative
        );
    }

    function updateSupplyShare(address _underlying, uint256 _amount)
        external
        override
    {
        AAVELogicStorage.SimulateData memory data = AAVELogicStorage
            .SimulateData(
                _amount,
                LOGIC_STORAGE.pool().getReserveNormalizedIncome(_underlying)
            );

        LOGIC_STORAGE.setLastSimulatedSupply(_underlying, data);

        emit SupplyShareUpdated(_underlying, _amount, abi.encode(data));
    }

    function updateBorrowShare(address _underlying, uint256 _amount)
        external
        override
    {
        AAVELogicStorage.SimulateData memory data = AAVELogicStorage
            .SimulateData(
                _amount,
                LOGIC_STORAGE.pool().getReserveNormalizedVariableDebt(
                    _underlying
                )
            );

        LOGIC_STORAGE.setLastSimulatedBorrow(_underlying, data);

        emit BorrowShareUpdated(_underlying, _amount, abi.encode(data));
    }

    function lastSupplyInterest(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        AAVELogicStorage.SimulateData memory data = LOGIC_STORAGE
            .getLastSimulatedSupply(_underlying);

        if (data.index == 0) {
            return 0;
        }

        uint256 deltaIndex = LOGIC_STORAGE.pool().getReserveNormalizedIncome(
            _underlying
        ) - data.index;
        return (deltaIndex * data.amount) / data.index;
    }

    function lastBorrowInterest(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        AAVELogicStorage.SimulateData memory data = LOGIC_STORAGE
            .getLastSimulatedBorrow(_underlying);
        if (data.index == 0) {
            return 0;
        }

        uint256 deltaIndex = LOGIC_STORAGE
            .pool()
            .getReserveNormalizedVariableDebt(_underlying) - data.index;
        return (deltaIndex * data.amount) / data.index;
    }

    function supply(address _underlying, uint256 _amount) external override {
        IAAVEPool aPool = LOGIC_STORAGE.pool();
        if (_underlying == TransferHelper.ETH) {
            _underlying = LOGIC_STORAGE.wrappedNative();
            IWETH(payable(_underlying)).deposit{value: _amount}();
        }

        TransferHelper.approve(_underlying, address(aPool), _amount);
        aPool.supply(_underlying, _amount, address(this), 0);
    }

    function redeem(address _underlying, uint256 _amount) external {
        IAAVEPool aPool = LOGIC_STORAGE.pool();

        if (_underlying == TransferHelper.ETH) {
            _underlying = LOGIC_STORAGE.wrappedNative();
            aPool.withdraw(_underlying, _amount, address(this));
            IWETH(payable(_underlying)).withdraw(_amount);
        } else {
            aPool.withdraw(_underlying, _amount, address(this));
        }
    }

    function borrow(address _underlying, uint256 _amount) external {
        IAAVEPool aPool = LOGIC_STORAGE.pool();
        if (_underlying != TransferHelper.ETH) {
            aPool.borrow(
                _underlying,
                _amount,
                uint256(AAVEDataTypes.InterestRateMode.VARIABLE),
                0,
                address(this)
            );
        } else {
            _underlying = LOGIC_STORAGE.wrappedNative();
            aPool.borrow(
                _underlying,
                _amount,
                uint256(AAVEDataTypes.InterestRateMode.VARIABLE),
                0,
                address(this)
            );
            IWETH(payable(_underlying)).withdraw(_amount);
        }
    }

    function repay(address _underlying, uint256 _amount) external {
        IAAVEPool aPool = LOGIC_STORAGE.pool();
        if (_underlying == TransferHelper.ETH) {
            _underlying = LOGIC_STORAGE.wrappedNative();
            IWETH(payable(_underlying)).deposit{value: _amount}();
        }

        TransferHelper.approve(_underlying, address(aPool), _amount);
        aPool.repay(
            _underlying,
            _amount,
            uint256(AAVEDataTypes.InterestRateMode.VARIABLE),
            address(this)
        );
    }

    function claimRewards(address _account) external override {}

    function supplyOf(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        _underlying = replaceNative(_underlying);
        AAVEDataTypes.ReserveData memory reserve = LOGIC_STORAGE
            .pool()
            .getReserveData(_underlying);
        return IERC20(reserve.aTokenAddress).balanceOf(_account);
    }

    function debtOf(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        _underlying = replaceNative(_underlying);
        AAVEDataTypes.ReserveData memory reserve = LOGIC_STORAGE
            .pool()
            .getReserveData(_underlying);
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(_account);
    }

    function totalColletralAndBorrow(address _account, address _quote)
        external
        view
        override
        returns (uint256 collateralValue, uint256 borrowedValue)
    {
        _quote = replaceNative(_quote);
        (collateralValue, borrowedValue, , , , ) = LOGIC_STORAGE
            .pool()
            .getUserAccountData(_account);
        IAAVEPriceOracleGetter priceOracle = IAAVEPriceOracleGetter(
            LOGIC_STORAGE.pool().ADDRESSES_PROVIDER().getPriceOracle()
        );
        uint256 priceQuote = priceOracle.getAssetPrice(_quote);

        AAVEDataTypes.ReserveConfigurationMap
            memory configuration = LOGIC_STORAGE.pool().getConfiguration(
                _quote
            );
        (, , , uint256 decimals, , ) = AAVEReserveConfigurationGetter.getParams(
            configuration
        );
        uint256 unit = 10**(decimals);

        collateralValue = (collateralValue * unit) / priceQuote;
        borrowedValue = (borrowedValue * unit) / priceQuote;
    }

    function supplyToTargetSupplyRate(uint256 _targetRate, bytes memory _params)
        external
        pure
        override
        returns (int256)
    {
        Types.AAVEUsageParams memory params = abi.decode(
            _params,
            (Types.AAVEUsageParams)
        );

        _targetRate = (_targetRate * Utils.MILLION).ceilDiv(
            params.reserveFactor
        );

        uint256 a = params.optimalLTV *
            (params.baseS *
                params.totalBorrowedStable +
                params.baseV *
                params.totalBorrowedVariable -
                _targetRate *
                params.unbacked);
        uint256 delta = ((a * a) / Utils.TRILLION) +
            ((4 * params.totalBorrowed * _targetRate * params.optimalLTV) /
                Utils.MILLION) *
            (params.slopeV1 *
                params.totalBorrowedVariable +
                params.slopeS1 *
                params.totalBorrowedStable);
        uint256 supplyAmount = (a + Utils.MILLION * delta.sqrt()) /
            (2 * _targetRate * params.optimalLTV);

        if (
            params.totalBorrowed * Utils.MILLION >
            supplyAmount * params.optimalLTV
        ) {
            params.baseS += params.slopeS1;
            params.baseV += params.slopeV1;
            params.slopeS2 =
                (params.slopeS2 * Utils.MILLION) /
                params.maxExcessUsageRatio;
            params.slopeV2 =
                (params.slopeV2 * Utils.MILLION) /
                params.maxExcessUsageRatio;

            a =
                Utils.MILLION *
                _targetRate *
                params.unbacked +
                params.optimalLTV *
                (params.slopeS2 *
                    params.totalBorrowedStable +
                    params.slopeV2 *
                    params.totalBorrowedVariable) -
                Utils.MILLION *
                (params.totalBorrowedStable *
                    params.baseS +
                    params.totalBorrowedVariable *
                    params.baseV);
            delta =
                ((a * a) / Utils.TRILLION) +
                4 *
                _targetRate *
                params.totalBorrowed *
                (params.slopeS2 *
                    params.totalBorrowedStable +
                    params.slopeV2 *
                    params.totalBorrowedVariable);
            supplyAmount =
                (delta.sqrt() - a / Utils.MILLION) /
                (2 * _targetRate);
        }

        return int256(supplyAmount) - int256(params.totalSupplied);
    }

    function borrowToTargetBorrowRate(uint256 _targetRate, bytes memory _params)
        external
        pure
        override
        returns (int256)
    {
        Types.AAVEUsageParams memory params = abi.decode(
            _params,
            (Types.AAVEUsageParams)
        );

        if (_targetRate < params.baseV) {
            _targetRate = params.baseV;
        }

        uint256 borrowAmount = (params.totalSupplied *
            (_targetRate - params.baseV) *
            params.optimalLTV) / (Utils.MILLION * params.slopeV1);

        if (
            borrowAmount * Utils.MILLION >
            params.totalSupplied * params.optimalLTV
        ) {
            params.baseV += params.slopeV1;
            params.slopeV2 =
                (params.slopeV2 * Utils.MILLION) /
                (params.maxExcessUsageRatio);
            borrowAmount =
                (params.totalSupplied *
                    (_targetRate - params.baseV) *
                    Utils.MILLION +
                    params.optimalLTV *
                    params.slopeV2) /
                (Utils.MILLION * params.slopeV2);
        }

        return int256(borrowAmount) - int256(params.totalBorrowed);
    }

    function totalRewards(
        address _underlying,
        address _account,
        bool _isSupply
    ) external view override returns (uint256 rewards) {}

    function pool() external view returns (IAAVEPool) {
        return LOGIC_STORAGE.pool();
    }

    function rewardToken() external view override returns (address) {
        return LOGIC_STORAGE.rewardToken();
    }

    function wrappedNative() external view returns (address) {
        return LOGIC_STORAGE.wrappedNative();
    }

    function lastSimulatedSupply(address _asset)
        external
        view
        returns (AAVELogicStorage.SimulateData memory)
    {
        return LOGIC_STORAGE.getLastSimulatedSupply(_asset);
    }

    function lastSimulatedBorrow(address _asset)
        external
        view
        returns (AAVELogicStorage.SimulateData memory)
    {
        return LOGIC_STORAGE.getLastSimulatedBorrow(_asset);
    }

    function getUsageParams(address _underlying, uint256 _suppliesToRedeem)
        external
        view
        override
        returns (bytes memory)
    {
        AAVEDataTypes.ReserveData memory reserve = LOGIC_STORAGE
            .pool()
            .getReserveData(replaceNative(_underlying));
        IAAVEInterestRateStrategy strategy = IAAVEInterestRateStrategy(
            reserve.interestRateStrategyAddress
        );

        Types.AAVEUsageParams memory params = Types.AAVEUsageParams(
            IERC20(reserve.aTokenAddress).totalSupply() - _suppliesToRedeem,
            0,
            IERC20(reserve.stableDebtTokenAddress).totalSupply(),
            IERC20(reserve.variableDebtTokenAddress).totalSupply(),
            reserve.unbacked,
            strategy.getVariableRateSlope1() / BASE,
            strategy.getVariableRateSlope2() / BASE,
            strategy.getStableRateSlope1() / BASE,
            strategy.getStableRateSlope2() / BASE,
            strategy.getBaseStableBorrowRate() / BASE,
            strategy.getBaseVariableBorrowRate() / BASE,
            strategy.OPTIMAL_USAGE_RATIO() / BASE,
            Utils.MILLION -
                AAVEReserveConfigurationGetter.getReserveFactor(
                    reserve.configuration
                ) *
                100,
            0,
            strategy.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO() / BASE,
            strategy.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO() / BASE,
            strategy.MAX_EXCESS_USAGE_RATIO() / BASE
        );

        params.totalBorrowed =
            params.totalBorrowedStable +
            params.totalBorrowedVariable;
        params.stableToTotalDebtRatio = params.totalBorrowed > 0
            ? ((reserve.currentStableBorrowRate / BASE) * Utils.MILLION) /
                params.totalBorrowed
            : 0;

        if (
            params.stableToTotalDebtRatio > params.optimalStableToTotalDebtRatio
        ) {
            uint256 excessStableDebtRatio = ((params.stableToTotalDebtRatio -
                params.optimalStableToTotalDebtRatio) * Utils.MILLION) /
                params.maxExcessStableToTotalDebtRatio;
            params.baseS +=
                ((strategy.getStableRateExcessOffset() / BASE) *
                    excessStableDebtRatio) /
                Utils.MILLION;
        }
        return abi.encode(params);
    }

    function getCurrentSupplyRate(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        return
            LOGIC_STORAGE
                .pool()
                .getReserveData(replaceNative(_underlying))
                .currentLiquidityRate / BASE;
    }

    function getCurrentBorrowRate(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        return
            LOGIC_STORAGE
                .pool()
                .getReserveData(replaceNative(_underlying))
                .currentVariableBorrowRate / BASE;
    }

    function replaceNative(address _underlying)
        internal
        view
        returns (address)
    {
        if (_underlying == TransferHelper.ETH) {
            return LOGIC_STORAGE.wrappedNative();
        } else {
            return _underlying;
        }
    }
}
