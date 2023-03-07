// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../../interfaces/IConfig.sol";
import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";

import "./UserAssetBitMap.sol";
import "../internals/Utils.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

library ExternalUtils {
    using Math for uint256;
    using UserAssetBitMap for uint256;

    event AccFeeUpdated(address indexed asset, uint256 newAccFee);
    event AccFeeOffsetUpdated(address indexed asset, uint256 newIndex);
    event FeeIndexUpdated(address indexed asset, uint256 newIndex);
    event UserFeeIndexUpdated(
        address indexed account,
        address indexed asset,
        uint256 newIndex
    );

    event TotalLendingsUpdated(address indexed asset, uint256 newLending);

    function sync(
        address _asset,
        IProtocolsHandler _protocols,
        IConfig _config,
        mapping(address => uint256) storage totalLendings,
        mapping(address => uint256) storage accFees
    ) internal {
        (uint256 totalLending, uint256 newInterest) = _protocols
            .simulateLendings(_asset, totalLendings[_asset]);

        updateTotalLendings(_protocols, _asset, totalLending, totalLendings);
        updateAccFee(_asset, newInterest, _config, accFees);
    }

    function updateTotalLendings(
        IProtocolsHandler _protocol,
        address _asset,
        uint256 _new,
        mapping(address => uint256) storage totalLendings
    ) internal {
        _protocol.updateSimulates(_asset, _new);
        totalLendings[_asset] = _new;
        emit TotalLendingsUpdated(_asset, _new);
    }

    function updateAccFee(
        address _asset,
        uint256 _newInterest,
        IConfig config,
        mapping(address => uint256) storage accFees
    ) internal returns (uint256 accFee) {
        if (_newInterest > 0) {
            accFee = accFees[_asset];

            accFee +=
                (_newInterest * config.assetConfigs(_asset).feeRate) /
                Utils.MILLION;

            accFees[_asset] = accFee;
            emit AccFeeUpdated(_asset, accFee);
        }
    }

    function updateFeeIndex(
        address _underlying,
        uint256 _totalSupply,
        uint256 _accFee,
        mapping(address => uint256) storage feeIndexes
    ) internal returns (uint256 newIndex) {
        if (_totalSupply > 0) {
            newIndex = (_accFee * Utils.QUINTILLION) / _totalSupply;
            feeIndexes[_underlying] = newIndex;
            emit FeeIndexUpdated(_underlying, newIndex);
        } else {
            newIndex = feeIndexes[_underlying];
        }
    }

    function updateAccFeeOffset(
        address _asset,
        uint256 _feeIndex,
        uint256 _newOffset,
        mapping(address => uint256) storage accFeeOffsets
    ) internal {
        if (_newOffset > 0) {
            uint256 newFeeOffset = accFeeOffsets[_asset] +
                (_feeIndex * _newOffset).ceilDiv(Utils.QUINTILLION);

            accFeeOffsets[_asset] = newFeeOffset;

            emit AccFeeOffsetUpdated(_asset, newFeeOffset);
        }
    }

    function updateUserFeeIndex(
        address _underlying,
        address _account,
        uint256 _dTokenBalance,
        uint256 _newAmount,
        uint256 _feeIndex,
        mapping(address => mapping(address => uint256)) storage userFeeIndexes
    ) internal returns (uint256 newIndex) {
        if (_newAmount > 0) {
            newIndex =
                (userFeeIndexes[_account][_underlying] *
                    (_dTokenBalance - _newAmount) +
                    _feeIndex *
                    _newAmount) /
                _dTokenBalance;

            userFeeIndexes[_account][_underlying] = newIndex;

            emit UserFeeIndexUpdated(_account, _underlying, newIndex);
        } else {
            newIndex = userFeeIndexes[_account][_underlying];
        }
    }

    // views
    function getSupplyStatus(
        address _underlying,
        IReservePool reservePool,
        IProtocolsHandler protocols,
        mapping(address => uint256) storage totalLendings
    )
        internal
        view
        returns (
            uint256[] memory supplies,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 totalSuppliedAmount,
            uint256 newInterest
        )
    {
        (supplies, protocolsSupplies) = protocols.totalSupplied(_underlying);
        (totalLending, newInterest) = protocols.simulateLendings(
            _underlying,
            totalLendings[_underlying]
        );

        uint256 redeemedAmount;
        if (address(reservePool) != address(0)) {
            redeemedAmount = reservePool.redeemedAmounts(_underlying);
        }

        totalSuppliedAmount = protocolsSupplies + totalLending - redeemedAmount;
    }

    function getBorrowStatus(
        address _underlying,
        IReservePool reservePool,
        IProtocolsHandler protocols,
        mapping(address => uint256) storage totalLendings
    )
        internal
        view
        returns (
            uint256[] memory borrows,
            uint256 totalBorrowed,
            uint256 totalLending,
            uint256 newInterest
        )
    {
        IProtocolsHandler protocolsCache = protocols;
        uint256 protocolsBorrows;
        (borrows, protocolsBorrows) = protocolsCache.totalBorrowed(_underlying);
        (totalLending, newInterest) = protocolsCache.simulateLendings(
            _underlying,
            totalLendings[_underlying]
        );

        uint256 reservePoolLentAmount;
        uint256 reservePoolPendingRepayAmount;
        if (address(reservePool) != address(0)) {
            reservePoolLentAmount = reservePool.lentAmounts(_underlying);
            reservePoolPendingRepayAmount = reservePool.pendingRepayAmounts(
                _underlying
            );
        }

        return (
            borrows,
            protocolsBorrows +
                totalLending +
                reservePoolLentAmount -
                reservePoolPendingRepayAmount,
            totalLending,
            newInterest
        );
    }

    // deprecating
    function calculateAmountByRatio(
        address _underlying,
        uint256 _amount,
        uint256 _ratio,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (uint256 amount, bool blackListed) {
        if (assets[_underlying].paused) {
            blackListed = true;
        } else {
            amount = (_ratio * _amount) / Utils.MILLION;
        }
    }

    // internal views
    function getUserDebts(
        address _account,
        uint256 _userConfig,
        address[] memory _underlyings,
        address _quote,
        IPriceOracle priceOracle,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (uint256 amount) {
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            address underlying = _underlyings[i];
            Types.Asset memory asset = assets[underlying];

            if (_userConfig.isBorrowing(asset.index)) {
                uint256 balance = assets[underlying].dToken.scaledDebtOf(
                    _account
                );

                amount += underlying == _quote
                    ? balance
                    : priceOracle.valueOfAsset(underlying, _quote, balance);
            }
        }
    }

    function getUserCollateral(
        address _account,
        uint256 _userConfig,
        address[] memory _underlyings,
        address _quote,
        IPriceOracle _priceOracle,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (uint256 amount) {
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            address underlying = _underlyings[i];
            Types.Asset memory asset = assets[underlying];

            if (_userConfig.isUsingAsCollateral(asset.index)) {
                uint256 balance = asset.sToken.scaledBalanceOf(_account);

                if (!assets[underlying].paused) {
                    amount += underlying == _quote
                        ? balance
                        : _priceOracle.valueOfAsset(
                            underlying,
                            _quote,
                            balance
                        );
                }
            }
        }
    }

    function borrowLimitInternal(
        uint256 _userConfig,
        uint256 _maxLTV,
        IPriceOracle _priceOracle,
        address _account,
        address _borrowAsset,
        address[] memory _underlyings,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (uint256 amount) {
        // uint256 userConfig = _config.userDebtAndCollateral(_account);
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            address underlying = _underlyings[i];
            Types.Asset memory asset = assets[underlying];

            if (_userConfig.isUsingAsCollateral(asset.index) && !asset.paused) {
                uint256 collateralAmount = underlying == _borrowAsset
                    ? asset.sToken.scaledBalanceOf(_account)
                    : _priceOracle.valueOfAsset(
                        underlying,
                        _borrowAsset,
                        asset.sToken.scaledBalanceOf(_account)
                    );

                amount +=
                    // (_config.assetConfigs(underlying).maxLTV *
                    (_maxLTV * collateralAmount) /
                    Utils.MILLION;
            }
        }
    }

    function userStatus(
        address _account,
        address _quote,
        IPriceOracle _priceOracle,
        IConfig _config,
        address[] memory _underlyings,
        mapping(address => Types.Asset) storage assets
    )
        internal
        view
        returns (
            uint256 collateralValue,
            uint256 borrowingValue,
            bool blackListedCollateral
        )
    {
        uint256 userConfig = _config.userDebtAndCollateral(_account);
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            address underlying = _underlyings[i];
            Types.Asset memory asset = assets[underlying];

            if (userConfig.isUsingAsCollateralOrBorrowing(asset.index)) {
                if (userConfig.isUsingAsCollateral(asset.index)) {
                    uint256 balance = asset.sToken.scaledBalanceOf(_account);

                    if (assets[underlying].paused) {
                        blackListedCollateral = true;
                    } else {
                        collateralValue += underlying == _quote
                            ? balance
                            : _priceOracle.valueOfAsset(
                                underlying,
                                _quote,
                                balance
                            );
                    }
                }

                if (userConfig.isBorrowing(asset.index)) {
                    uint256 balance = asset.dToken.scaledDebtOf(_account);

                    borrowingValue += underlying == _quote
                        ? balance
                        : _priceOracle.valueOfAsset(
                            underlying,
                            _quote,
                            balance
                        );
                }
            }
        }
    }

    function isPositionHealthy(
        IConfig _config,
        IPriceOracle _priceOracle,
        address _account,
        address _underlying,
        address[] memory _underlyings,
        mapping(address => Types.Asset) storage assets
    )
        internal
        view
        returns (
            bool,
            uint256,
            uint256
        )
    {
        uint256 maxDebtAllowed = ExternalUtils.borrowLimitInternal(
            _config.userDebtAndCollateral(_account),
            _config.assetConfigs(_underlying).liquidateLTV,
            _priceOracle,
            _account,
            _underlying,
            _underlyings,
            assets
        );

        uint256 currentDebts = ExternalUtils.getUserDebts(
            _account,
            _config.userDebtAndCollateral(_account),
            _underlyings,
            _underlying,
            _priceOracle,
            assets
        );

        return (currentDebts <= maxDebtAllowed, maxDebtAllowed, currentDebts);
    }
}
