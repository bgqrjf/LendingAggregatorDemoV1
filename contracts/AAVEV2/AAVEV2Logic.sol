// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./IAAVEPriceOracleGetter.sol";
import "./ILendingPool.sol";
import "./IReserveInterestRateStrategy.sol";
import "../interfaces/IProtocol.sol";
import "../interfaces/IWETH.sol";

import "./DataTypes.sol";
import "./ReserveConfiguration.sol";
import "../libraries/internals/TransferHelper.sol";
import "../libraries/internals/Types.sol";
import "../libraries/internals/Utils.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./AAVEV2LogicStorage.sol";

contract AAVEV2Logic is IProtocol {
    using Math for uint256;

    struct UsageParams {
        uint256 totalSupplied; // not balance
        uint256 totalBorrowed;
        uint256 totalBorrowedStable;
        uint256 totalBorrowedVariable;
        uint256 slopeV1;
        uint256 slopeV2;
        uint256 slopeS1;
        uint256 slopeS2;
        uint256 baseV;
        uint256 optimalLTV;
        uint256 reserveFactor;
        uint256 maxExcessUsageRatio;
    }

    AAVEV2LogicStorage public immutable LOGIC_STORAGE;
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
        LOGIC_STORAGE = new AAVEV2LogicStorage(
            _protocolsHandler,
            _pool,
            _wrappedNative
        );
    }

    function updateSupplyShare(
        address _underlying,
        uint256 _amount
    ) external override {
        AAVEV2LogicStorage.SimulateData memory data = AAVEV2LogicStorage
            .SimulateData(
                _amount,
                LOGIC_STORAGE.pool().getReserveNormalizedIncome(_underlying)
            );

        LOGIC_STORAGE.setLastSimulatedSupply(_underlying, data);

        emit SupplyShareUpdated(_underlying, _amount, abi.encode(data));
    }

    function updateBorrowShare(
        address _underlying,
        uint256 _amount
    ) external override {
        AAVEV2LogicStorage.SimulateData memory data = AAVEV2LogicStorage
            .SimulateData(
                _amount,
                LOGIC_STORAGE.pool().getReserveNormalizedVariableDebt(
                    _underlying
                )
            );

        LOGIC_STORAGE.setLastSimulatedBorrow(_underlying, data);

        emit BorrowShareUpdated(_underlying, _amount, abi.encode(data));
    }

    function lastSupplyInterest(
        address _underlying
    ) external view override returns (uint256) {
        AAVEV2LogicStorage.SimulateData memory data = LOGIC_STORAGE
            .getLastSimulatedSupply(_underlying);

        if (data.index == 0) {
            return 0;
        }

        uint256 deltaIndex = LOGIC_STORAGE.pool().getReserveNormalizedIncome(
            _underlying
        ) - data.index;
        return (deltaIndex * data.amount) / data.index;
    }

    function lastBorrowInterest(
        address _underlying
    ) external view override returns (uint256) {
        AAVEV2LogicStorage.SimulateData memory data = LOGIC_STORAGE
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
        ILendingPool aPool = LOGIC_STORAGE.pool();
        if (_underlying == TransferHelper.ETH) {
            _underlying = LOGIC_STORAGE.wrappedNative();
            IWETH(payable(_underlying)).deposit{value: _amount}();
        }

        TransferHelper.approve(_underlying, address(aPool), _amount);
        aPool.deposit(_underlying, _amount, address(this), 0);
    }

    function redeem(address _underlying, uint256 _amount) external {
        ILendingPool aPool = LOGIC_STORAGE.pool();

        if (_underlying == TransferHelper.ETH) {
            _underlying = LOGIC_STORAGE.wrappedNative();
            aPool.withdraw(_underlying, _amount, address(this));
            IWETH(payable(_underlying)).withdraw(_amount);
        } else {
            aPool.withdraw(_underlying, _amount, address(this));
        }
    }

    function borrow(address _underlying, uint256 _amount) external {
        ILendingPool aPool = LOGIC_STORAGE.pool();
        if (_underlying != TransferHelper.ETH) {
            aPool.borrow(
                _underlying,
                _amount,
                uint256(DataTypes.InterestRateMode.VARIABLE),
                0,
                address(this)
            );
        } else {
            _underlying = LOGIC_STORAGE.wrappedNative();
            aPool.borrow(
                _underlying,
                _amount,
                uint256(DataTypes.InterestRateMode.VARIABLE),
                0,
                address(this)
            );
            IWETH(payable(_underlying)).withdraw(_amount);
        }
    }

    function repay(address _underlying, uint256 _amount) external {
        ILendingPool aPool = LOGIC_STORAGE.pool();
        if (_underlying == TransferHelper.ETH) {
            _underlying = LOGIC_STORAGE.wrappedNative();
            IWETH(payable(_underlying)).deposit{value: _amount}();
        }

        TransferHelper.approve(_underlying, address(aPool), _amount);
        aPool.repay(
            _underlying,
            _amount,
            uint256(DataTypes.InterestRateMode.VARIABLE),
            address(this)
        );
    }

    function claimRewards(
        address _underlying,
        address _account,
        bool _isSupply
    ) external override returns (uint256 newRewards) {}

    function update(address _newLogic) external override {}

    function supplyOf(
        address _underlying,
        address _account
    ) external view override returns (uint256) {
        _underlying = replaceNative(_underlying);
        DataTypes.ReserveData memory reserve = LOGIC_STORAGE
            .pool()
            .getReserveData(_underlying);
        return IERC20(reserve.aTokenAddress).balanceOf(_account);
    }

    function debtOf(
        address _underlying,
        address _account
    ) external view override returns (uint256) {
        _underlying = replaceNative(_underlying);
        DataTypes.ReserveData memory reserve = LOGIC_STORAGE
            .pool()
            .getReserveData(_underlying);
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(_account);
    }

    function totalColletralAndBorrow(
        address _account,
        address _quote
    )
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
            LOGIC_STORAGE.pool().getAddressesProvider().getPriceOracle()
        );
        uint256 priceQuote = priceOracle.getAssetPrice(_quote);

        DataTypes.ReserveConfigurationMap memory configuration = LOGIC_STORAGE
            .pool()
            .getConfiguration(_quote);
        (, , , uint256 decimals, ) = ReserveConfiguration.getParams(
            configuration
        );
        uint256 unit = 10 ** (decimals);

        collateralValue = (collateralValue * unit) / priceQuote;
        borrowedValue = (borrowedValue * unit) / priceQuote;
    }

    function supplyToTargetSupplyRate(
        uint256 _targetRate,
        bytes memory _params
    ) external pure override returns (int256) {
        UsageParams memory params = abi.decode(_params, (UsageParams));
        _targetRate = (_targetRate * Utils.MILLION).ceilDiv(
            params.reserveFactor
        );
        uint256 a = params.optimalLTV *
            (params.baseV * params.totalBorrowedVariable);
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
            // params.baseS += params.slopeS1;
            params.baseV += params.slopeV1;
            params.slopeS2 =
                (params.slopeS2 * Utils.MILLION) /
                params.maxExcessUsageRatio;
            params.slopeV2 =
                (params.slopeV2 * Utils.MILLION) /
                params.maxExcessUsageRatio;
            a =
                params.optimalLTV *
                (params.slopeS2 *
                    params.totalBorrowedStable +
                    params.slopeV2 *
                    params.totalBorrowedVariable) -
                Utils.MILLION *
                (params.totalBorrowedStable *
                    params.slopeS1 +
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

    function borrowToTargetBorrowRate(
        uint256 _targetRate,
        bytes memory _params
    ) external pure override returns (int256) {
        UsageParams memory params = abi.decode(_params, (UsageParams));

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

    function pool() external view returns (ILendingPool) {
        return LOGIC_STORAGE.pool();
    }

    function rewardToken() external view override returns (address) {
        return LOGIC_STORAGE.rewardToken();
    }

    function wrappedNative() external view returns (address) {
        return LOGIC_STORAGE.wrappedNative();
    }

    function lastSimulatedSupply(
        address _asset
    ) external view returns (AAVEV2LogicStorage.SimulateData memory) {
        return LOGIC_STORAGE.getLastSimulatedSupply(_asset);
    }

    function lastSimulatedBorrow(
        address _asset
    ) external view returns (AAVEV2LogicStorage.SimulateData memory) {
        return LOGIC_STORAGE.getLastSimulatedBorrow(_asset);
    }

    function getUsageParams(
        address _underlying,
        uint256 _suppliesToRedeem
    ) external view override returns (bytes memory) {
        DataTypes.ReserveData memory reserve = LOGIC_STORAGE
            .pool()
            .getReserveData(replaceNative(_underlying));
        IReserveInterestRateStrategy strategy = IReserveInterestRateStrategy(
            reserve.interestRateStrategyAddress
        );

        UsageParams memory params = UsageParams(
            IERC20(reserve.aTokenAddress).totalSupply() - _suppliesToRedeem,
            0,
            IERC20(reserve.stableDebtTokenAddress).totalSupply(),
            IERC20(reserve.variableDebtTokenAddress).totalSupply(),
            strategy.variableRateSlope1() / BASE,
            strategy.variableRateSlope2() / BASE,
            strategy.stableRateSlope1() / BASE,
            strategy.stableRateSlope2() / BASE,
            strategy.baseVariableBorrowRate() / BASE,
            strategy.OPTIMAL_UTILIZATION_RATE() / BASE,
            Utils.MILLION -
                ReserveConfiguration.getReserveFactor(reserve.configuration) *
                100,
            strategy.EXCESS_UTILIZATION_RATE() / BASE
        );

        params.totalBorrowed =
            params.totalBorrowedStable +
            params.totalBorrowedVariable;

        return abi.encode(params);
    }

    function getCurrentSupplyRate(
        address _underlying
    ) external view override returns (uint256) {
        return
            LOGIC_STORAGE
                .pool()
                .getReserveData(replaceNative(_underlying))
                .currentLiquidityRate / BASE;
    }

    function getCurrentBorrowRate(
        address _underlying
    ) external view override returns (uint256) {
        return
            LOGIC_STORAGE
                .pool()
                .getReserveData(replaceNative(_underlying))
                .currentVariableBorrowRate / BASE;
    }

    function replaceNative(
        address _underlying
    ) internal view returns (address) {
        if (_underlying == TransferHelper.ETH) {
            return LOGIC_STORAGE.wrappedNative();
        } else {
            return _underlying;
        }
    }
}
