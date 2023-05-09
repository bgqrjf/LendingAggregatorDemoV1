// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./interfaces/IStrategy.sol";

import "./libraries/internals/Utils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract Strategy is IStrategy, Ownable {
    uint256 public maxLTV; // max loan to value

    function getSupplyStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory supplyAmounts) {
        uint256 length = _protocols.length;
        supplyAmounts = new uint256[](length);

        // if shortage on supply
        for (uint256 i = 0; i < length; ) {
            (uint256 currentCollateral, uint256 currentBorrowed) = _protocols[i]
                .totalColletralAndBorrow(msg.sender, _asset);

            if (currentBorrowed * Utils.MILLION > maxLTV * currentCollateral) {
                supplyAmounts[i] = Math.min(
                    (currentBorrowed * Utils.MILLION) /
                        maxLTV -
                        currentCollateral,
                    _amount
                );
                _amount -= supplyAmounts[i];
            }

            unchecked {
                ++i;
            }
        }

        if (_amount > 0) {
            uint256 bestPoolID;
            uint256 maxRate;
            for (uint256 i = 0; i < length; ) {
                uint256 rate = _protocols[i].getCurrentSupplyRate(_asset);
                if (rate > maxRate) {
                    bestPoolID = i;
                    maxRate = rate;
                }

                unchecked {
                    ++i;
                }
            }

            supplyAmounts[bestPoolID] += _amount;
        }
    }

    function getSimulateSupplyStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory amounts) {
        uint256 length = _protocols.length;

        amounts = new uint256[](length);

        uint256 bestPoolID;
        uint256 maxRate;
        for (uint256 i = 0; i < length; ) {
            if (_protocols[i].getCurrentSupplyRate(_asset) > maxRate) {
                bestPoolID = i;
            }

            unchecked {
                ++i;
            }
        }

        amounts[bestPoolID] = _amount;
    }

    function getRedeemStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory redeemAmounts) {
        uint256 length = _protocols.length;
        redeemAmounts = new uint256[](length);

        uint256[] memory rates = new uint256[](length);
        uint256[] memory maxRedeems = new uint256[](length);
        for (uint256 i = 0; i < length; ) {
            maxRedeems[i] = _maxRedeemAmount(_protocols[i], _asset);
            rates[i] = maxRedeems[i] > 0
                ? _protocols[i].getCurrentSupplyRate(_asset)
                : Utils.MAX_UINT;
            unchecked {
                ++i;
            }
        }

        redeemAmounts = calculateAmountOut(_amount, maxRedeems, rates);
    }

    function getBorrowStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory amounts) {
        uint256 length = _protocols.length;

        uint256[] memory rates = new uint256[](length);
        uint256[] memory maxBorrows = new uint256[](length);
        for (uint256 i = 0; i < length; ) {
            (uint256 currentCollateral, uint256 currentBorrowed) = _protocols[i]
                .totalColletralAndBorrow(msg.sender, _asset);

            uint256 maxBorrow = (currentCollateral * maxLTV) / Utils.MILLION;
            maxBorrows[i] = currentBorrowed < maxBorrow
                ? currentCollateral - currentBorrowed
                : 0;

            rates[i] = _protocols[i].getCurrentBorrowRate(_asset);
            unchecked {
                ++i;
            }
        }

        amounts = calculateAmountOut(_amount, maxBorrows, rates);
    }

    function getSimulateBorrowStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory amounts) {
        uint256 length = _protocols.length;

        uint256[] memory rates = new uint256[](length);
        uint256[] memory maxBorrows = new uint256[](length);

        for (uint256 i = 0; i < length; ) {
            rates[i] = _protocols[i].getCurrentBorrowRate(_asset);
            maxBorrows[i] = Utils.MAX_UINT;

            unchecked {
                ++i;
            }
        }

        amounts = calculateAmountOut(_amount, maxBorrows, rates);
    }

    function getRepayStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory repayAmounts) {
        uint256 length = _protocols.length;
        uint256[] memory maxRepays = new uint256[](length);
        uint256[] memory minRepays = new uint256[](length);
        uint256[] memory rates = new uint256[](length);
        for (uint256 i = 0; i < length; ) {
            (uint256 currentCollateral, uint256 currentBorrowed) = _protocols[i]
                .totalColletralAndBorrow(msg.sender, _asset);

            if (currentBorrowed * Utils.MILLION > maxLTV * currentCollateral) {
                minRepays[i] = Math.min(
                    currentBorrowed - maxLTV * currentCollateral,
                    _amount
                );
                _amount -= minRepays[i];
            }

            maxRepays[i] = currentBorrowed;
            rates[i] = _protocols[i].getCurrentBorrowRate(_asset);
            unchecked {
                ++i;
            }
        }

        repayAmounts = calculateRepayAmounts(_amount, maxRepays, rates);

        for (uint256 i = 0; i < length; ) {
            repayAmounts[i] += minRepays[i];
            unchecked {
                ++i;
            }
        }
    }

    function calculateRepayAmounts(
        uint256 _amount,
        uint256[] memory _maxRepays,
        uint256[] memory _rates
    ) internal pure returns (uint256[] memory amounts) {
        uint256 length = _rates.length;
        amounts = new uint256[](length);

        uint256 bestPoolID;
        if (_amount > 0) {
            uint256 maxRate;
            for (uint256 i = 0; i < length; ) {
                if (_rates[i] > maxRate) {
                    bestPoolID = i;
                    maxRate = _rates[i];
                }
                unchecked {
                    ++i;
                }
            }

            uint256 repayAmount = Math.min(_amount, _maxRepays[bestPoolID]);
            amounts[bestPoolID] += repayAmount;
            _amount -= repayAmount;
        }

        if (_amount > 0) {
            _rates[bestPoolID] = 0;
            uint256[] memory nextRoundAmounts = calculateRepayAmounts(
                _amount,
                _maxRepays,
                _rates
            );

            for (uint256 i = 0; i < length; ) {
                amounts[i] += nextRoundAmounts[i];
                unchecked {
                    ++i;
                }
            }
        }
    }

    function getRebalanceStrategy(
        IProtocol[] memory _protocols,
        address _asset
    )
        external
        view
        override
        returns (uint256[] memory redeemAmounts, uint256[] memory supplyAmounts)
    {
        uint256 length = _protocols.length;
        uint256[] memory maxRedeemAmounts = new uint256[](length);
        uint256[] memory targetAmounts;

        bytes[] memory usageParams = new bytes[](length);
        uint256 maxRate;
        uint256 bestPoolToAddExtra;
        uint256 targetAmount;

        for (uint256 i = 0; i < length; ) {
            IProtocol protocol = _protocols[i];

            maxRedeemAmounts[i] = _maxRedeemAmount(protocol, _asset);
            usageParams[i] = _protocols[i].getUsageParams(
                _asset,
                maxRedeemAmounts[i]
            );

            uint256 rate = protocol.getCurrentSupplyRate(_asset);
            if (rate > maxRate) {
                bestPoolToAddExtra = i;
                maxRate = rate;
            }

            targetAmount += maxRedeemAmounts[i];
            unchecked {
                ++i;
            }
        }

        targetAmounts = calculateRebalanceAmount(
            _protocols,
            targetAmount,
            bestPoolToAddExtra,
            maxRate,
            usageParams
        );

        supplyAmounts = new uint256[](length);
        redeemAmounts = new uint256[](length);

        for (uint256 i = 0; i < length; ) {
            if (targetAmounts[i] < maxRedeemAmounts[i]) {
                redeemAmounts[i] = maxRedeemAmounts[i] - targetAmounts[i];
            } else {
                supplyAmounts[i] = targetAmounts[i] - maxRedeemAmounts[i];
            }
            unchecked {
                ++i;
            }
        }
    }

    function calculateAmountOut(
        uint256 _amount,
        uint256[] memory _maxAmount,
        uint256[] memory _rates
    ) internal pure returns (uint256[] memory amounts) {
        uint256 length = _rates.length;
        uint256 minRate = Utils.MAX_UINT;
        uint256 bestPoolID;
        for (uint256 i = 0; i < length; ) {
            if (_rates[i] < minRate) {
                minRate = _rates[i];
                bestPoolID = i;
            }

            unchecked {
                ++i;
            }
        }

        if (_amount > _maxAmount[bestPoolID]) {
            uint256 amountLeft = _amount - _maxAmount[bestPoolID];
            _rates[bestPoolID] = Utils.MAX_UINT;
            amounts = calculateAmountOut(amountLeft, _maxAmount, _rates);
            amounts[bestPoolID] = _maxAmount[bestPoolID];
        } else {
            amounts = new uint256[](length);
            amounts[bestPoolID] = _amount;
        }
    }

    function _maxRedeemAmount(
        IProtocol _protocol,
        address _quote
    ) internal view returns (uint256 maxRedeem) {
        (uint256 currentCollateral, uint256 currentBorrowed) = _protocol
            .totalColletralAndBorrow(msg.sender, _quote);

        uint256 minCollateral = (currentBorrowed * Utils.MILLION) / maxLTV;
        maxRedeem = Math.min(
            currentCollateral > minCollateral
                ? currentCollateral - minCollateral
                : 0,
            _protocol.supplyOf(_quote, msg.sender)
        );
    }

    function setMaxLTV(uint256 _maxLTV) external onlyOwner {
        maxLTV = _maxLTV;
    }

    function calculateRebalanceAmount(
        IProtocol[] memory _protocols,
        uint256 _targetAmount,
        uint256 _bestPoolToAddExtra,
        uint256 _maxRate,
        bytes[] memory _usageParams
    ) internal pure returns (uint256[] memory amounts) {
        uint256 length = _protocols.length;
        amounts = new uint256[](length);
        uint256 totalAmountToSupply;

        uint256 minRate;
        while (_maxRate > minRate + 1) {
            totalAmountToSupply = 0;
            uint256 targetRate = (_maxRate + minRate) / 2;
            for (uint256 i = 0; i < length; ) {
                amounts[i] = getAmountToSupply(
                    _protocols[i],
                    targetRate,
                    _usageParams[i]
                );
                totalAmountToSupply += amounts[i];

                unchecked {
                    ++i;
                }
            }

            if (totalAmountToSupply < _targetAmount) {
                _maxRate = targetRate;
            } else if (totalAmountToSupply > _targetAmount) {
                minRate = targetRate;
            } else {
                break;
            }
        }

        if (totalAmountToSupply <= _targetAmount) {
            amounts[_bestPoolToAddExtra] += _targetAmount - totalAmountToSupply;
        } else {
            amounts[_bestPoolToAddExtra] -= totalAmountToSupply - _targetAmount;
        }

        return amounts;
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
}
