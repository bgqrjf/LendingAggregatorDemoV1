// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../interfaces/IConfig.sol";
import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";

import "./UserAssetBitMap.sol";
import "../internals/Utils.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

library ExternalUtils {
    using Math for uint256;
    using UserAssetBitMap for uint256;

    event TotalLendingsUpdated(address indexed asset, uint256 newLending);

    function sync(
        address _asset,
        IProtocolsHandler _protocols,
        mapping(address => uint256) storage totalLendings
    ) internal {
        (uint256 totalLending, ) = _protocols.simulateLendings(
            _asset,
            totalLendings[_asset]
        );

        updateTotalLendings(_protocols, _asset, totalLending, totalLendings);
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
            uint256 totalSuppliedAmountWithFee,
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

        totalSuppliedAmountWithFee =
            protocolsSupplies +
            totalLending -
            redeemedAmount;
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

    // internal views
    function getUserDebts(
        address _account,
        uint256 _userConfig,
        address _quote,
        IPriceOracle priceOracle,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (uint256 amount) {
        uint256 length = underlyings.length;
        for (uint256 i = 0; i < length; ) {
            address underlying = underlyings[i];
            Types.Asset memory asset = assets[underlying];

            if (_userConfig.isBorrowing(asset.index)) {
                uint256 balance = assets[underlying].dToken.scaledDebtOf(
                    _account
                );

                amount += underlying == _quote
                    ? balance
                    : priceOracle.valueOfAsset(underlying, _quote, balance);
            }

            unchecked {
                ++i;
            }
        }
    }

    function borrowLimitInternal(
        uint256 _userConfig,
        uint256 _maxLTV,
        IPriceOracle _priceOracle,
        address _account,
        address _borrowAsset,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (uint256 amount) {
        uint256 length = underlyings.length;
        for (uint256 i = 0; i < length; ) {
            address underlying = underlyings[i];
            Types.Asset memory asset = assets[underlying];

            if (_userConfig.isUsingAsCollateral(asset.index) && !asset.paused) {
                uint256 collateralAmount = getCollateralValue(
                    underlying,
                    _account,
                    _borrowAsset,
                    _priceOracle,
                    asset
                );

                amount += (_maxLTV * collateralAmount) / Utils.MILLION;
            }

            unchecked {
                ++i;
            }
        }
    }

    function userStatus(
        address _account,
        address _quote,
        IPriceOracle _priceOracle,
        IConfig _config,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (uint256 collateralValue, uint256 borrowingValue) {
        uint256 userConfig = _config.userDebtAndCollateral(_account);
        uint256 length = underlyings.length;
        for (uint256 i = 0; i < length; ) {
            address underlying = underlyings[i];
            Types.Asset memory asset = assets[underlying];

            if (userConfig.isUsingAsCollateralOrBorrowing(asset.index)) {
                if (
                    userConfig.isUsingAsCollateral(asset.index) && !asset.paused
                ) {
                    collateralValue += getCollateralValue(
                        underlying,
                        _account,
                        _quote,
                        _priceOracle,
                        asset
                    );
                }

                if (userConfig.isBorrowing(asset.index)) {
                    borrowingValue += getDebtsValue(
                        underlying,
                        _account,
                        _quote,
                        _priceOracle,
                        asset
                    );
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    function isPositionHealthy(
        IConfig _config,
        IPriceOracle _priceOracle,
        address _account,
        address _underlying,
        address[] storage _underlyings,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (bool, uint256, uint256) {
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
            _underlying,
            _priceOracle,
            _underlyings,
            assets
        );

        return (currentDebts <= maxDebtAllowed, maxDebtAllowed, currentDebts);
    }

    function getCollateralValue(
        address _underlying,
        address _account,
        address _quote,
        IPriceOracle _priceOracle,
        Types.Asset memory asset
    ) internal view returns (uint256 amount) {
        if (!asset.paused) {
            uint256 balance = asset.sToken.scaledBalanceOf(_account);

            return
                _underlying == _quote
                    ? balance
                    : _priceOracle.valueOfAsset(_underlying, _quote, balance);
        }
    }

    function getDebtsValue(
        address _underlying,
        address _account,
        address _quote,
        IPriceOracle _priceOracle,
        Types.Asset memory asset
    ) internal view returns (uint256) {
        uint256 debts = asset.dToken.scaledDebtOf(_account);

        return
            _underlying == _quote
                ? debts
                : _priceOracle.valueOfAsset(_underlying, _quote, debts);
    }
}
