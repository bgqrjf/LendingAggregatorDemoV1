// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IStrategy.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/internals/Utils.sol";

contract ETHStrategy is IStrategy, Ownable {
    uint256 public maxLTV;

    function getSupplyStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256[] memory,
        uint256 _amount
    )
        external
        view
        override
        returns (uint256[] memory supplyAmounts, uint256[] memory redeemAmounts)
    {
        supplyAmounts = new uint256[](_protocols.length);
        redeemAmounts = new uint256[](_protocols.length);

        // if shortage on supply
        for (uint256 i = 0; i < _protocols.length; ++i) {
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
        }

        if (_amount > 0) {
            uint256 bestPoolID;
            uint256 maxRate;
            for (uint256 i = 0; i < _protocols.length; ++i) {
                uint256 rate = _protocols[i].getCurrentSupplyRate(_asset);
                if (rate > maxRate) {
                    bestPoolID = i;
                    maxRate = rate;
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
        amounts = new uint256[](_protocols.length);

        uint256 bestPoolID;
        uint256 maxRate;
        for (uint256 i = 0; i < _protocols.length; ++i) {
            if (_protocols[i].getCurrentSupplyRate(_asset) > maxRate) {
                bestPoolID = i;
            }
        }

        amounts[bestPoolID] = _amount;
    }

    function getRedeemStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256[] memory,
        uint256 _amount
    )
        external
        view
        override
        returns (uint256[] memory supplyAmounts, uint256[] memory redeemAmounts)
    {
        supplyAmounts = new uint256[](_protocols.length);
        redeemAmounts = new uint256[](_protocols.length);

        // if shortage on supply
        uint256[] memory rates = new uint256[](_protocols.length);
        uint256[] memory maxRedeems = new uint256[](_protocols.length);
        for (uint256 i = 0; i < _protocols.length; ++i) {
            (uint256 currentCollateral, uint256 currentBorrowed) = _protocols[i]
                .totalColletralAndBorrow(msg.sender, _asset);

            uint256 minCollateral = (currentBorrowed * Utils.MILLION) / maxLTV;
            maxRedeems[i] = currentCollateral > minCollateral
                ? currentCollateral - minCollateral
                : 0;

            rates[i] = _protocols[i].getCurrentSupplyRate(_asset);
        }

        redeemAmounts = calculateAmountOut(_amount, maxRedeems, rates);
    }

    function getBorrowStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory amounts) {
        uint256[] memory rates = new uint256[](_protocols.length);
        uint256[] memory maxBorrows = new uint256[](_protocols.length);
        for (uint256 i = 0; i < _protocols.length; ++i) {
            (uint256 currentCollateral, uint256 currentBorrowed) = _protocols[i]
                .totalColletralAndBorrow(msg.sender, _asset);

            uint256 maxBorrow = (currentCollateral * maxLTV) / Utils.MILLION;
            maxBorrows[i] = currentBorrowed < maxBorrow
                ? currentCollateral - currentBorrowed
                : 0;

            rates[i] = _protocols[i].getCurrentBorrowRate(_asset);
        }

        amounts = calculateAmountOut(_amount, maxBorrows, rates);
    }

    function getSimulateBorrowStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory amounts) {
        uint256[] memory rates = new uint256[](_protocols.length);
        uint256[] memory maxBorrows = new uint256[](_protocols.length);

        for (uint256 i = 0; i < _protocols.length; ++i) {
            rates[i] = _protocols[i].getCurrentBorrowRate(_asset);
            maxBorrows[i] = Utils.MAX_UINT;
        }

        amounts = calculateAmountOut(_amount, maxBorrows, rates);
    }

    function getRepayStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](_protocols.length);

        // if shortage on supply
        for (uint256 i = 0; i < _protocols.length; ++i) {
            (uint256 currentCollateral, uint256 currentBorrowed) = _protocols[i]
                .totalColletralAndBorrow(msg.sender, _asset);

            if (currentBorrowed * Utils.MILLION > maxLTV * currentCollateral) {
                amounts[i] = Math.min(
                    currentBorrowed - maxLTV * currentCollateral,
                    _amount
                );
                _amount -= amounts[i];
            }
        }

        if (_amount > 0) {
            uint256 bestPoolID;
            uint256 maxRate;
            for (uint256 i = 0; i < _protocols.length; ++i) {
                uint256 rate = _protocols[i].getCurrentBorrowRate(_asset);
                if (rate > maxRate) {
                    bestPoolID = i;
                    maxRate = rate;
                }
            }

            amounts[bestPoolID] += _amount;
        }
    }

    function calculateAmountOut(
        uint256 _amount,
        uint256[] memory _maxAmount,
        uint256[] memory _rates
    ) internal pure returns (uint256[] memory amounts) {
        uint256 minRate;
        uint256 bestPoolID;
        for (uint256 i = 0; i < _rates.length; i++) {
            if (_rates[i] < minRate) {
                minRate = _rates[i];
                bestPoolID = i;
            }
        }

        if (_amount < _maxAmount[bestPoolID]) {
            amounts[bestPoolID] = _amount;
        } else {
            uint256 amountLeft = _amount - _maxAmount[bestPoolID];
            _rates[bestPoolID] = Utils.MAX_UINT;
            amounts = calculateAmountOut(amountLeft, _maxAmount, _rates);
            amounts[bestPoolID] = _maxAmount[bestPoolID];
        }
    }

    function setMaxLTVs(uint256 _maxLTV) external onlyOwner {
        maxLTV = _maxLTV;
    }
}
