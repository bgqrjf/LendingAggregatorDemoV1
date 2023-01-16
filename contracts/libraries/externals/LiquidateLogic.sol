// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./RedeemLogic.sol";
import "./RepayLogic.sol";
import "../internals/ExternalUtils.sol";
import "../internals/TransferHelper.sol";
import "../internals/Types.sol";
import "../internals/UserAssetBitMap.sol";

import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";
import "../../interfaces/IConfig.sol";

library LiquidateLogic {
    using UserAssetBitMap for uint256;

    // _redeemParams.amount is the minAmount redeem which is used as slippage validation
    function liquidate(
        Types.LiquidateParams memory _params,
        mapping(address => Types.Asset) storage assets,
        mapping(address => uint256) storage totalLendings,
        mapping(address => uint256) storage accFees,
        mapping(address => uint256) storage collectedFees,
        mapping(address => uint256) storage feeIndexes
    ) external {
        // actionNotPaused(_repayParams.asset, Action.liquidate);
        require(_params.actionNotPaused, "LiquidateLogic: actionPaused");

        _params.repayParams.userParams.amount = validateLiquidatation(
            _params,
            assets
        );

        _params.repayParams.userParams.amount = RepayLogic.repay(
            _params.repayParams,
            totalLendings,
            accFees,
            collectedFees,
            feeIndexes
        );

        (uint256[] memory supplies, uint256 protocolsSupplies) = _params
            .redeemParams
            .protocols
            .totalSupplied(_params.redeemParams.userParams.asset);

        (uint256 totalLending, ) = _params
            .redeemParams
            .protocols
            .simulateLendings(
                _params.redeemParams.userParams.asset,
                totalLendings[_params.redeemParams.userParams.asset]
            );

        // preprocessing data
        {
            uint256 assetValue = _params.repayParams.priceOracle.valueOfAsset(
                _params.repayParams.userParams.asset,
                _params.redeemParams.userParams.asset,
                _params.repayParams.userParams.amount
            );

            uint256 redeemAmount = (assetValue *
                _params
                    .redeemParams
                    .config
                    .assetConfigs(_params.redeemParams.userParams.asset)
                    .liquidateRewardRatio) / Utils.MILLION;

            require(
                redeemAmount >= _params.redeemParams.userParams.amount,
                "insufficient redeem amount"
            );
            _params.redeemParams.userParams.amount = redeemAmount;
        }
        uint256 uncollectedFee;
        (
            _params.redeemParams.userParams.amount,
            uncollectedFee
        ) = _recordLiquidateRedeem(
            _params.redeemParams,
            protocolsSupplies + totalLending,
            accFees[_params.redeemParams.userParams.asset],
            collectedFees[_params.redeemParams.userParams.asset]
        );

        RedeemLogic.executeRedeem(
            _params.redeemParams,
            supplies,
            protocolsSupplies,
            totalLending,
            uncollectedFee,
            totalLendings
        );
    }

    function validateLiquidatation(
        Types.LiquidateParams memory _params,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (uint256) {
        uint256 userConfig = _params.repayParams.config.userDebtAndCollateral(
            _params.repayParams.userParams.to
        );
        Types.Asset memory repayAsset = assets[
            _params.repayParams.userParams.asset
        ];
        Types.Asset memory redeemAsset = assets[
            _params.redeemParams.userParams.asset
        ];

        uint256 debtsValue = ExternalUtils.getUserDebts(
            _params.repayParams.userParams.to,
            userConfig,
            _params.underlyings,
            _params.repayParams.userParams.asset,
            _params.repayParams.priceOracle,
            assets
        );

        (
            uint256 liquidationThreshold,
            uint256 maxLiquidationAmount,
            bool blackListed
        ) = getLiquidationData(
                _params.repayParams.userParams.to,
                _params.repayParams.userParams.asset,
                _params.underlyings,
                _params.repayParams.config,
                _params.repayParams.priceOracle,
                assets
            );

        require(
            assets[_params.redeemParams.userParams.asset].paused == blackListed,
            "Router: Paused token not liquidated"
        );

        require(
            userConfig.isUsingAsCollateral(redeemAsset.index),
            "Router: Token is not using as collateral"
        );

        require(
            userConfig.isBorrowing(repayAsset.index),
            "Router: Token is not borrowing"
        );

        require(
            debtsValue > liquidationThreshold,
            "Router: Liquidate not allowed"
        );

        return
            _params.repayParams.userParams.amount < maxLiquidationAmount
                ? _params.repayParams.userParams.amount
                : maxLiquidationAmount;
    }

    function _recordLiquidateRedeem(
        Types.RedeemParams memory _params,
        uint256 totalSupplies,
        uint256 accFee,
        uint256 collectedFee
    ) internal returns (uint256 underlyingAmount, uint256 fee) {
        uint256 totalSupply = _params.asset.sToken.totalSupply();

        uint256 sTokenAmount = _params.asset.sToken.unscaledAmount(
            _params.userParams.amount,
            totalSupplies
        );

        uint256 sTokenBalance = _params.asset.sToken.balanceOf(
            _params.userParams.to
        );

        if (sTokenAmount > sTokenBalance) {
            sTokenAmount = sTokenBalance;
            _params.config.setUsingAsCollateral(
                msg.sender,
                _params.asset.index,
                false
            );
        }

        (underlyingAmount, fee) = _params.asset.sToken.burn(
            _params.userParams.to,
            sTokenAmount,
            totalSupplies,
            accFee - collectedFee
        );

        _params.rewards.stopMiningSupplyReward(
            _params.userParams.asset,
            msg.sender,
            underlyingAmount,
            totalSupply
        );
    }

    function getLiquidationData(
        address _account,
        address _repayAsset,
        address[] memory _underlyings,
        IConfig _config,
        IPriceOracle _priceOracle,
        mapping(address => Types.Asset) storage assets
    )
        public
        view
        returns (
            uint256 liquidationAmount,
            uint256 maxLiquidationAmount,
            bool blackListed
        )
    {
        uint256 userConfig = _config.userDebtAndCollateral(_account);

        for (uint256 i = 0; i < _underlyings.length; ++i) {
            if (userConfig.isUsingAsCollateral(i)) {
                address underlying = _underlyings[i];

                uint256 collateralAmount;
                {
                    uint256 sTokenBalance = assets[underlying]
                        .sToken
                        .scaledBalanceOf(_account);

                    collateralAmount = underlying == _repayAsset
                        ? sTokenBalance
                        : _priceOracle.valueOfAsset(
                            underlying,
                            _repayAsset,
                            sTokenBalance
                        );
                }

                Types.AssetConfig memory collateralConfig = _config
                    .assetConfigs(underlying);

                {
                    (uint256 maxLiquidationAmountNew, ) = ExternalUtils
                        .calculateAmountByRatio(
                            underlying,
                            collateralAmount,
                            collateralConfig.maxLiquidateRatio,
                            assets
                        );

                    maxLiquidationAmount += maxLiquidationAmountNew;
                }

                (
                    uint256 liquidationAmountNew,
                    bool blackListedNew
                ) = ExternalUtils.calculateAmountByRatio(
                        underlying,
                        collateralAmount,
                        collateralConfig.liquidateLTV,
                        assets
                    );

                liquidationAmount += liquidationAmountNew;
                if (!blackListed && blackListedNew) {
                    blackListed = true;
                }
            }
        }
    }
}
