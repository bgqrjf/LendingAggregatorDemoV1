// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "./Utils.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../interfaces/IProtocol.sol";

library StrategyCalculations {
    using Math for uint256;
    uint256 constant PRECISION = 1;

    struct StrategyParams {
        uint256 targetAmount;
        uint128 maxRate;
        uint128 minRate;
        uint256 bestPoolToAddExtra;
        uint256[] minAmounts;
        uint256[] maxAmounts;
        bytes[] usageParams;
    }

    function calculateAmountsToSupply(
        StrategyParams memory _params,
        IProtocol[] memory _protocols
    ) internal pure returns (uint256[] memory amounts) {
        uint256 length = _protocols.length;
        amounts = new uint256[](length);
        uint256 totalAmountToSupply;
        while (_params.maxRate > PRECISION + _params.minRate) {
            totalAmountToSupply = 0;
            uint128 targetRate = (_params.maxRate + _params.minRate) / 2;
            for (uint256 i = 0; i < length; ) {
                amounts[i] = getAmountToSupply(
                    _protocols[i],
                    targetRate,
                    _params.usageParams[i]
                );
                totalAmountToSupply += amounts[i];
                unchecked {
                    ++i;
                }
            }

            if (totalAmountToSupply < _params.targetAmount) {
                _params.maxRate = targetRate;
            } else if (totalAmountToSupply > _params.targetAmount) {
                _params.minRate = targetRate;
            } else {
                break;
            }
        }

        if (totalAmountToSupply <= _params.targetAmount) {
            amounts[_params.bestPoolToAddExtra] +=
                _params.targetAmount -
                totalAmountToSupply;
            return amounts;
        }

        // find protocols which allowed to reduce supply
        for (
            uint256 i = 0;
            i < length && totalAmountToSupply > _params.targetAmount;

        ) {
            uint256 amount = Math.min(
                totalAmountToSupply - _params.targetAmount,
                amounts[i] - _params.minAmounts[i]
            );
            amounts[i] -= amount;
            totalAmountToSupply -= amount;

            unchecked {
                ++i;
            }
        }

        if (totalAmountToSupply == _params.targetAmount) {
            return amounts;
        }

        // No protocol is allowed to reduce any more tokens. Set insecure supplies based on the current state to minimize the possibility of liquidations.
        for (
            (uint256 i, uint256 amountToReduce) = (
                0,
                totalAmountToSupply - _params.targetAmount
            );
            i < length && totalAmountToSupply > _params.targetAmount;

        ) {
            amounts[i] -= Math.min(
                (amounts[i] * amountToReduce).ceilDiv(totalAmountToSupply),
                totalAmountToSupply - _params.targetAmount
            );
            totalAmountToSupply -= amounts[i];

            unchecked {
                ++i;
            }
        }
    }

    function calculateAmountsToBorrow(
        StrategyParams memory _params,
        IProtocol[] memory _protocols
    ) internal pure returns (uint256[] memory amounts) {
        uint256 length = _protocols.length;
        amounts = new uint256[](length);

        uint256 totalAmountToBorrow;
        while (
            _params.maxRate > _params.minRate + PRECISION ||
            _params.maxRate == 0
        ) {
            totalAmountToBorrow = 0;
            uint128 targetRate = _params.maxRate == 0
                ? _params.minRate + _params.minRate + 1
                : (_params.maxRate + _params.minRate) / 2;

            for (uint256 i = 0; i < length; ) {
                uint256 amount = Math.min(
                    getAmountToBorrow(
                        _protocols[i],
                        targetRate,
                        _params.usageParams[i]
                    ),
                    _params.maxAmounts[i]
                );
                amounts[i] = totalAmountToBorrow < _params.targetAmount
                    ? Math.min(
                        amount,
                        _params.targetAmount - totalAmountToBorrow
                    )
                    : 0;
                totalAmountToBorrow += amount;
                unchecked {
                    ++i;
                }
            }

            if (totalAmountToBorrow < _params.targetAmount) {
                _params.minRate = targetRate;
            } else if (totalAmountToBorrow > _params.targetAmount) {
                _params.maxRate = targetRate;
            } else {
                break;
            }
        }

        if (totalAmountToBorrow < _params.targetAmount) {
            uint256 amountLeft = _params.targetAmount - totalAmountToBorrow;
            for (uint256 i = 0; i < length && amountLeft > 0; ) {
                if (amounts[i] < _params.maxAmounts[i]) {
                    uint256 amountDelta = Math.min(
                        amountLeft,
                        _params.maxAmounts[i] - amounts[i]
                    );
                    amounts[i] += amountDelta;
                    amountLeft -= amountDelta;
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    function calculateAmountsToRepay(
        StrategyParams memory _params,
        IProtocol[] memory _protocols
    ) internal pure returns (uint256[] memory amounts) {
        uint256 length = _protocols.length;
        amounts = new uint256[](length);

        uint256 totalAmountToRepay;
        uint256 totalAmount;
        while (_params.maxRate > PRECISION + _params.minRate) {
            totalAmountToRepay = 0;
            totalAmount = 0;
            uint128 targetRate = (_params.maxRate + _params.minRate) / 2;
            for (uint256 i = 0; i < length; ) {
                uint256 amount = getAmountToRepay(
                    _protocols[i],
                    targetRate,
                    _params.usageParams[i]
                );

                amounts[i] = Math.max(_params.minAmounts[i], amount);

                if (totalAmountToRepay < _params.targetAmount) {
                    amounts[i] = Math.min(
                        amounts[i],
                        _params.targetAmount - totalAmountToRepay
                    );
                }

                amounts[i] = Math.min(_params.maxAmounts[i], amounts[i]);
                totalAmountToRepay += amount;
                totalAmount += amounts[i];

                unchecked {
                    ++i;
                }
            }

            if (totalAmountToRepay < _params.targetAmount) {
                _params.maxRate = targetRate;
            } else if (totalAmountToRepay > _params.targetAmount) {
                _params.minRate = targetRate;
            } else {
                break;
            }
        }

        if (totalAmount < _params.targetAmount) {
            uint256 amountLeft = _params.targetAmount - totalAmount;
            for (uint256 i = 0; i < length && amountLeft > 0; ) {
                if (amounts[i] < _params.maxAmounts[i]) {
                    uint256 amountDelta = Math.min(
                        amountLeft,
                        _params.maxAmounts[i] - amounts[i]
                    );
                    amounts[i] += amountDelta;
                    amountLeft -= amountDelta;
                }
                unchecked {
                    ++i;
                }
            }
        }
    }

    function getAmountToSupply(
        IProtocol _protocol,
        uint256 _targetRate,
        bytes memory _usageParams
    ) internal pure returns (uint256) {
        int256 amount = _protocol.supplyToTargetSupplyRate(
            _targetRate,
            _usageParams
        );
        return amount > 0 ? uint256(amount) : 0;
    }

    function getAmountToBorrow(
        IProtocol _protocol,
        uint256 _targetRate,
        bytes memory _usageParams
    ) internal pure returns (uint256) {
        int256 amount = _protocol.borrowToTargetBorrowRate(
            _targetRate,
            _usageParams
        );
        return amount > 0 ? uint256(amount) : 0;
    }

    function getAmountToRepay(
        IProtocol _protocol,
        uint256 _targetRate,
        bytes memory _usageParams
    ) internal pure returns (uint256) {
        int256 amount = _protocol.borrowToTargetBorrowRate(
            _targetRate,
            _usageParams
        );
        return amount < 0 ? uint256(-amount) : 0;
    }
}
