// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProtocol.sol";
import "../interfaces/IWETH.sol";

import "./IAAVEPool.sol";
import "./IAToken.sol";
import "./IVariableDebtToken.sol";
import "./IAAVEInterestRateStrategy.sol";
import "./IAAVEPriceOracleGetter.sol";

import "./AAVEDataTypes.sol";
import "./AAVEReserveConfigurationGetter.sol";
import "../libraries/Utils.sol";
import "../libraries/Math.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/Types.sol";

contract AAVELogic is IProtocol {
    using Math for uint256;

    struct SimulateData {
        uint256 amount;
        uint256 index;
    }

    // ray = 1e27 truncate to 1e6
    uint256 public immutable RAY = 1e27;
    uint256 public immutable BASE = 1e21;
    address payable public wrappedNative;
    address public aaveTokenAddress;
    address public rewardToken;
    IAAVEPool public pool;

    // mapping underlying , msg.sender to simulateData
    mapping(address => mapping(address => SimulateData))
        public lastSimulatedSupply;
    mapping(address => mapping(address => SimulateData))
        public lastSimulatedBorrow;

    receive() external payable {}

    constructor(
        address _pool,
        address payable _wrappedNative,
        address _aaveTokenAddress
    ) {
        pool = IAAVEPool(_pool);
        wrappedNative = _wrappedNative;
        aaveTokenAddress = _aaveTokenAddress;
    }

    function updateSupplyShare(address _underlying, uint256 _amount)
        external
        override
    {
        SimulateData memory data = SimulateData(
            _amount,
            pool.getReserveNormalizedIncome(_underlying)
        );

        lastSimulatedSupply[_underlying][msg.sender] = data;

        emit SupplyShareUpdated(
            msg.sender,
            _underlying,
            _amount,
            abi.encode(data)
        );
    }

    function updateBorrowShare(address _underlying, uint256 _amount)
        external
        override
    {
        SimulateData memory data = SimulateData(
            _amount,
            pool.getReserveNormalizedVariableDebt(_underlying)
        );

        lastSimulatedBorrow[_underlying][msg.sender] = data;

        emit BorrowShareUpdated(
            msg.sender,
            _underlying,
            _amount,
            abi.encode(data)
        );
    }

    function lastSupplyInterest(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        SimulateData memory data = lastSimulatedSupply[_underlying][_account];
        if (data.index == 0) {
            return 0;
        }

        uint256 deltaIndex = pool.getReserveNormalizedIncome(_underlying) -
            data.index;
        return (deltaIndex * data.amount) / data.index;
    }

    function lastBorrowInterest(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        SimulateData memory data = lastSimulatedBorrow[_underlying][_account];
        if (data.index == 0) {
            return 0;
        }

        uint256 deltaIndex = pool.getReserveNormalizedVariableDebt(
            _underlying
        ) - data.index;
        return (deltaIndex * data.amount) / data.index;
    }

    function getAddAssetData(address _underlying)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {}

    function getSupplyData(address _underlying, uint256 _amount)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = address(pool);
        data.approveTo = data.target;
        if (_underlying != TransferHelper.ETH) {
            data.encodedData = abi.encodeWithSelector(
                pool.supply.selector,
                _underlying,
                _amount,
                msg.sender,
                0
            );
        } else {
            data.weth = wrappedNative;
            data.encodedData = abi.encodeWithSelector(
                pool.supply.selector,
                data.weth,
                _amount,
                msg.sender,
                0
            );
        }

        data.initialized = true;
    }

    function getRedeemData(address _underlying, uint256 _amount)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = address(pool);

        if (_underlying == TransferHelper.ETH) {
            _underlying = wrappedNative;
            data.weth = payable(_underlying);
        }

        data.encodedData = abi.encodeWithSelector(
            pool.withdraw.selector,
            _underlying,
            _amount,
            msg.sender
        );
    }

    function getBorrowData(address _underlying, uint256 _amount)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = address(pool);
        if (_underlying != TransferHelper.ETH) {
            data.encodedData = abi.encodeWithSelector(
                pool.borrow.selector,
                _underlying,
                _amount,
                uint256(AAVEDataTypes.InterestRateMode.VARIABLE),
                0,
                msg.sender
            );
        } else {
            data.weth = wrappedNative;
            data.encodedData = abi.encodeWithSelector(
                pool.borrow.selector,
                data.weth,
                _amount,
                uint256(AAVEDataTypes.InterestRateMode.VARIABLE),
                0,
                msg.sender
            );
        }
    }

    function getRepayData(address _underlying, uint256 _amount)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = address(pool);
        data.approveTo = data.target;
        if (_underlying == TransferHelper.ETH) {
            _underlying = wrappedNative;
            data.weth = payable(_underlying);
        }

        data.encodedData = abi.encodeWithSelector(
            pool.repay.selector,
            _underlying,
            _amount,
            uint256(AAVEDataTypes.InterestRateMode.VARIABLE),
            msg.sender
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
        AAVEDataTypes.ReserveData memory reserve = pool.getReserveData(
            _underlying
        );
        return IERC20(reserve.aTokenAddress).balanceOf(_account);
    }

    function debtOf(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        _underlying = replaceNative(_underlying);
        AAVEDataTypes.ReserveData memory reserve = pool.getReserveData(
            _underlying
        );
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(_account);
    }

    function totalColletralAndBorrow(address _account, address _quote)
        external
        view
        override
        returns (uint256 collateralValue, uint256 borrowedValue)
    {
        _quote = replaceNative(_quote);
        (collateralValue, borrowedValue, , , , ) = pool.getUserAccountData(
            _account
        );
        IAAVEPriceOracleGetter priceOracle = IAAVEPriceOracleGetter(
            pool.ADDRESSES_PROVIDER().getPriceOracle()
        );
        uint256 priceQuote = priceOracle.getAssetPrice(_quote);

        AAVEDataTypes.ReserveConfigurationMap memory configuration = pool
            .getConfiguration(_quote);
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

        _targetRate = (_targetRate * Utils.MILLION).divCeil(
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
        uint256 supply = (a + Utils.MILLION * delta.sqrt()) /
            (2 * _targetRate * params.optimalLTV);

        if (params.totalBorrowed * Utils.MILLION > supply * params.optimalLTV) {
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
            supply = (delta.sqrt() - a / Utils.MILLION) / (2 * _targetRate);
        }

        return int256(supply) - int256(params.totalSupplied);
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

        uint256 borrow = (params.totalSupplied *
            (_targetRate - params.baseV) *
            params.optimalLTV) / (Utils.MILLION * params.slopeV1);

        if (borrow * Utils.MILLION > params.totalSupplied * params.optimalLTV) {
            params.baseV += params.slopeV1;
            params.slopeV2 =
                (params.slopeV2 * Utils.MILLION) /
                (params.maxExcessUsageRatio);
            borrow =
                (params.totalSupplied *
                    (_targetRate - params.baseV) *
                    Utils.MILLION +
                    params.optimalLTV *
                    params.slopeV2) /
                (Utils.MILLION * params.slopeV2);
        }

        return int256(borrow) - int256(params.totalBorrowed);
    }

    function totalRewards(
        address _underlying,
        address _account,
        bool _isSupply
    ) external view override returns (uint256 rewards) {}

    function getUsageParams(address _underlying, uint256 _suppliesToRedeem)
        external
        view
        override
        returns (bytes memory)
    {
        AAVEDataTypes.ReserveData memory reserve = pool.getReserveData(
            replaceNative(_underlying)
        );
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
            pool
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
            pool
                .getReserveData(replaceNative(_underlying))
                .currentVariableBorrowRate / BASE;
    }

    function replaceNative(address _underlying)
        internal
        view
        returns (address)
    {
        if (_underlying == TransferHelper.ETH) {
            return wrappedNative;
        } else {
            return _underlying;
        }
    }
}
