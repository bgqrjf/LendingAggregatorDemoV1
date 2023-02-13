// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../internals/ExternalUtils.sol";
import "../internals/TransferHelper.sol";
import "../internals/Types.sol";

import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";
import "../../interfaces/IConfig.sol";

library RedeemLogic {
    using UserAssetBitMap for uint256;

    event Redeemed(
        address indexed supplier,
        address indexed asset,
        uint256 amount
    );

    function redeem(
        Types.RedeemParams memory _params,
        mapping(address => uint256) storage totalLendings,
        mapping(address => uint256) storage accFees,
        mapping(address => Types.Asset) storage assets
    ) external {
        require(_params.actionNotPaused, "RedeemLogic: action paused");

        if (address(_params.reservePool) != address(0)) {
            _params.reservePool.redeem(
                _params.userParams,
                msg.sender,
                _params.collateralable,
                _params.executeNow
            );
        } else {
            (
                uint256[] memory supplies,
                uint256 protocolsSupplies,
                uint256 totalLending,
                uint256 totalBorrowedAmountWithFee,
                uint256 newInterest
            ) = ExternalUtils.getSupplyStatus(
                    _params.userParams.asset,
                    _params.reservePool,
                    _params.protocols,
                    totalLendings
                );

            uint256 uncollectedFee;
            (_params.userParams.amount, uncollectedFee) = recordRedeemInternal(
                _params,
                totalBorrowedAmountWithFee,
                newInterest,
                msg.sender,
                accFees,
                assets
            );

            executeRedeemInternal(
                _params,
                supplies,
                protocolsSupplies,
                totalLending,
                uncollectedFee,
                totalLendings
            );
        }
    }

    function redeemAllowed(
        Types.RedeemParams memory _params,
        address _redeemFrom,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (bool) {
        uint256 userConfig = _params.config.userDebtAndCollateral(_redeemFrom);

        Types.Asset memory redeemAsset = assets[_params.userParams.asset];
        if (!userConfig.isUsingAsCollateral(redeemAsset.index)) {
            return true;
        }
        uint256 maxDebtAllowed = ExternalUtils.borrowLimitInternal(
            _params.config,
            _params.priceOracle,
            _redeemFrom,
            _params.userParams.asset,
            _params.underlyings,
            assets
        );

        uint256 currentDebts = ExternalUtils.getUserDebts(
            _redeemFrom,
            _params.config.userDebtAndCollateral(_redeemFrom),
            _params.underlyings,
            _params.userParams.asset,
            _params.priceOracle,
            assets
        );

        return currentDebts <= maxDebtAllowed;
    }

    function recordRedeem(
        Types.RedeemParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        address _redeemFrom,
        mapping(address => uint256) storage accFees,
        mapping(address => Types.Asset) storage assets
    ) external returns (uint256 underlyingAmount, uint256 fee) {
        return
            recordRedeemInternal(
                _params,
                _totalSupplies,
                _newInterest,
                _redeemFrom,
                accFees,
                assets
            );
    }

    function executeRedeem(
        Types.RedeemParams memory _params,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending,
        uint256 _uncollectedFee,
        mapping(address => uint256) storage totalLendings
    ) external {
        executeRedeemInternal(
            _params,
            _supplies,
            _protocolsSupplies,
            _totalLending,
            _uncollectedFee,
            totalLendings
        );
    }

    function recordRedeemInternal(
        Types.RedeemParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        address _redeemFrom,
        mapping(address => uint256) storage accFees,
        mapping(address => Types.Asset) storage assets
    ) internal returns (uint256 underlyingAmount, uint256 fee) {
        uint256 accFee = ExternalUtils.updateAccFee(
            _params.userParams.asset,
            _newInterest,
            _params.config,
            accFees
        ) - _params.collectedFee;

        Types.Asset memory redeemAsset = assets[_params.userParams.asset];
        uint256 sTokenAmount = redeemAsset.sToken.unscaledAmount(
            _params.userParams.amount,
            _totalSupplies
        );

        // to prevent stack too deep
        {
            uint256 sTokenBalance = redeemAsset.sToken.balanceOf(_redeemFrom);
            if (sTokenAmount >= sTokenBalance) {
                sTokenAmount = sTokenBalance;
                _params.collateralable = false;
            }
        }

        (_params.userParams.amount, fee) = redeemAsset.sToken.burn(
            _redeemFrom,
            sTokenAmount,
            _totalSupplies,
            accFee
        );

        underlyingAmount = _params.userParams.amount;

        _params.rewards.stopMiningSupplyReward(
            _params.userParams.asset,
            _redeemFrom,
            sTokenAmount,
            redeemAsset.sToken.totalSupply() + sTokenAmount
        );

        _params.config.setUsingAsCollateral(
            _redeemFrom,
            redeemAsset.index,
            redeemAsset.collateralable && _params.collateralable
        );

        require(
            redeemAllowed(_params, _redeemFrom, assets),
            "RedeemLogic: insufficient collateral"
        );

        emit Redeemed(_redeemFrom, _params.userParams.asset, underlyingAmount);
    }

    function executeRedeemInternal(
        Types.RedeemParams memory _params,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending,
        uint256 _uncollectedFee,
        mapping(address => uint256) storage totalLendings
    ) internal {
        IProtocolsHandler protocolsCache = _params.protocols;

        (, uint256 borrowed) = protocolsCache.redeemAndBorrow(
            _params.userParams.asset,
            _params.userParams.amount,
            _supplies,
            _protocolsSupplies,
            _params.userParams.to
        );

        uint256 totalLendingDelta = borrowed + _uncollectedFee;
        if (totalLendingDelta > 0) {
            //  uncollectedFee may cause underflow
            _totalLending = _totalLending > totalLendingDelta
                ? _totalLending - totalLendingDelta
                : 0;
            ExternalUtils.updateTotalLendings(
                protocolsCache,
                _params.userParams.asset,
                _totalLending,
                totalLendings
            );
        }
    }
}
