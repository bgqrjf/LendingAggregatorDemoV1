// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IStrategy.sol";

import "./libraries/StrategyCalculations.sol";

contract Strategy is IStrategy {
    using StrategyCalculations for Types.StrategyParams;

    uint256 public maxLTV;

    constructor(uint256 _maxLTV) {
        maxLTV = _maxLTV;
    }

    function getSupplyStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256[] memory _currentSupplies,
        uint256 _amount
    )
        external
        view
        override
        returns (uint256[] memory supplyAmounts, uint256[] memory redeemAmounts)
    {
        Types.StrategyParams memory params;
        params.usageParams = new bytes[](_protocols.length);
        params.minAmounts = new uint256[](_protocols.length);

        for (uint256 i = 0; i < _protocols.length; i++) {
            params.usageParams[i] = _protocols[i].getUsageParams(
                _asset,
                _currentSupplies[i]
            );
            params.minAmounts[i] = minSupplyNeeded(
                _protocols[i],
                _asset,
                msg.sender
            );

            uint256 rate = _protocols[i].getCurrentSupplyRate(_asset);
            params.maxRate = uint128(Utils.maxOf(rate, params.maxRate));
        }

        params.targetAmount = _amount;
        uint256[] memory amounts = params.calculateAmountsToSupply(_protocols);

        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] < _currentSupplies[i]) {
                redeemAmounts[i] = _currentSupplies[i] - amounts[i];
            } else {
                supplyAmounts[i] = amounts[i] - _currentSupplies[i];
            }
        }
    }

    function getSimulateSupplyStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory amounts) {
        Types.StrategyParams memory params;
        params.usageParams = new bytes[](_protocols.length);
        params.minAmounts = new uint256[](_protocols.length);

        for (uint256 i = 0; i < _protocols.length; i++) {
            params.usageParams[i] = _protocols[i].getUsageParams(_asset, 0);
            params.minAmounts[i] = 0;

            uint256 rate = _protocols[i].getCurrentSupplyRate(_asset);
            params.maxRate = uint128(Utils.maxOf(rate, params.maxRate));
        }

        params.targetAmount = _amount;
        amounts = params.calculateAmountsToSupply(_protocols);
    }

    function getBorrowStrategy(
        IProtocol[] memory _protocols,
        Types.UserAssetParams memory _params
    ) external view override returns (uint256[] memory amounts) {
        Types.StrategyParams memory params;
        params.usageParams = new bytes[](_protocols.length);
        params.maxAmounts = new uint256[](_protocols.length);
        uint256 maxBorrowAmount;

        for (uint256 i = 0; i < _protocols.length; i++) {
            params.usageParams[i] = _protocols[i].getUsageParams(
                _params.asset,
                0
            );

            params.maxAmounts[i] = maxBorrowAllowed(
                _protocols[i],
                _params.asset,
                _params.to
            );
            maxBorrowAmount += params.maxAmounts[i];

            uint256 rate = _protocols[i].getCurrentBorrowRate(_params.asset);
            params.minRate = uint128(Utils.minOf(rate, params.minRate));
        }

        require(
            maxBorrowAmount >= _params.amount,
            "Strategy: insufficient balance"
        );
        params.targetAmount = _params.amount;

        amounts = params.calculateAmountsToBorrow(_protocols);
    }

    function getSimulateBorrowStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory amounts) {
        Types.StrategyParams memory params;
        params.usageParams = new bytes[](_protocols.length);
        params.minAmounts = new uint256[](_protocols.length);

        for (uint256 i = 0; i < _protocols.length; i++) {
            params.usageParams[i] = _protocols[i].getUsageParams(_asset, 0);
            params.maxAmounts[i] = Utils.MAX_UINT;

            uint256 rate = _protocols[i].getCurrentBorrowRate(_asset);
            params.minRate = uint128(Utils.minOf(rate, params.minRate));
        }

        params.targetAmount = _amount;
        amounts = params.calculateAmountsToBorrow(_protocols);
    }

    function getRepayStrategy(
        IProtocol[] memory _protocols,
        Types.UserAssetParams memory _params
    ) external view override returns (uint256[] memory amounts) {
        Types.StrategyParams memory params;
        params.usageParams = new bytes[](_protocols.length);

        params.minAmounts = new uint256[](_protocols.length);
        params.maxAmounts = new uint256[](_protocols.length);

        uint256 minRepayAmount;
        for (
            uint256 i = 0;
            i < _protocols.length && _params.amount > minRepayAmount;
            i++
        ) {
            params.usageParams[i] = _protocols[i].getUsageParams(
                _params.asset,
                0
            );

            params.minAmounts[i] = Utils.minOf(
                _params.amount - _protocols.length,
                minRepayNeeded(_protocols[i], _params.asset, _params.to)
            );
            minRepayAmount += params.minAmounts[i];

            params.maxAmounts[i] = _protocols[i].debtOf(
                _params.asset,
                msg.sender
            );

            uint256 rate = _protocols[i].getCurrentBorrowRate(_params.asset);
            params.maxRate = uint128(Utils.maxOf(rate, params.maxRate));
        }

        if (_params.amount > _protocols.length) {
            uint256[] memory strategyAmounts = params.calculateAmountsToRepay(
                _protocols
            );

            if (_protocols.length > 0) {
                for (uint256 i = 0; i < _protocols.length; i++) {
                    params.minAmounts[i] += strategyAmounts[i];
                }
            } else {
                return strategyAmounts;
            }
        }
    }

    function minSupplyNeeded(
        IProtocol _protocol,
        address _underlying,
        address _account
    ) public view override returns (uint256 amount) {
        (uint256 collateral, uint256 borrowed) = _protocol
            .totalColletralAndBorrow(_account, _underlying);
        uint256 minCollateralNeeded = (borrowed * Utils.MILLION) / maxLTV;
        return
            minCollateralNeeded > collateral
                ? minCollateralNeeded - collateral
                : 0;
    }

    function maxRedeemAllowed(
        IProtocol _protocol,
        address _underlying,
        address _account
    ) public view override returns (uint256 amount) {
        (uint256 collateral, uint256 borrowed) = _protocol
            .totalColletralAndBorrow(_account, _underlying);
        uint256 minCollateralNeeded = (borrowed * Utils.MILLION) / maxLTV;
        return
            minCollateralNeeded < collateral
                ? Utils.minOf(
                    collateral - minCollateralNeeded,
                    _protocol.supplyOf(_underlying, _account)
                )
                : 0;
    }

    function maxBorrowAllowed(
        IProtocol _protocol,
        address _underlying,
        address _account
    ) public view override returns (uint256 amount) {
        (uint256 collateral, uint256 borrowed) = _protocol
            .totalColletralAndBorrow(_account, _underlying);
        uint256 maxDebtAllowed = (collateral * maxLTV) / Utils.MILLION;
        return maxDebtAllowed > borrowed ? maxDebtAllowed - borrowed : 0;
    }

    function minRepayNeeded(
        IProtocol _protocol,
        address _underlying,
        address _account
    ) public view override returns (uint256 amount) {
        (uint256 collateral, uint256 borrowed) = _protocol
            .totalColletralAndBorrow(_account, _underlying);
        uint256 maxDebtAllowed = (collateral * maxLTV) / Utils.MILLION;
        return maxDebtAllowed < borrowed ? borrowed - maxDebtAllowed : 0;
    }
}
