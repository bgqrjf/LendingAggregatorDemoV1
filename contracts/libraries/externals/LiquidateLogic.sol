// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./RedeemLogic.sol";
import "./RepayLogic.sol";

library LiquidateLogic {
    using UserAssetBitMap for uint256;

    event Liquidated(
        address indexed liquidator,
        Types.UserAssetParams repayParams,
        Types.UserAssetParams redeemParams
    );

    // _redeemParams.amount is the minAmount to redeem which is used as slippage validation
    function liquidate(
        Types.LiquidateParams memory _params,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets,
        mapping(address => uint256) storage totalLendings
    ) external {
        // actionNotPaused(_repayParams.asset, Action.liquidate);
        require(_params.actionNotPaused, "LiquidateLogic: action paused");

        require(
            assets[_params.redeemParams.asset].sToken != ISToken(address(0)),
            "LiquidateLogic redeemParams asset not exists"
        );

        // repay
        _params.repayParams.amount = validateLiquidatation(
            _params,
            underlyings,
            assets
        );

        _params.repayParams.amount = RepayLogic.repayInternal(
            Types.RepayParams(
                _params.repayParams,
                true,
                true,
                _params.feeCollector,
                _params.protocols,
                _params.reservePool,
                _params.config,
                _params.priceOracle,
                assets[_params.repayParams.asset]
            ),
            totalLendings
        );

        // redeem
        (
            ,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 totalsupplies,
            uint256 newInterest
        ) = ExternalUtils.getSupplyStatus(
                _params.redeemParams.asset,
                _params.reservePool,
                _params.protocols,
                totalLendings
            );

        // preprocessing data
        {
            uint256 assetValue = _params.priceOracle.valueOfAsset(
                _params.repayParams.asset,
                _params.redeemParams.asset,
                _params.repayParams.amount
            );

            uint256 redeemAmount = (assetValue *
                _params
                    .config
                    .assetConfigs(_params.redeemParams.asset)
                    .liquidateRewardRatio) / Utils.MILLION;

            require(
                redeemAmount >= _params.redeemParams.amount,
                "LiquidateLogic: insufficient redeem amount"
            );

            _params.redeemParams.amount = redeemAmount;
        }

        _params.redeemParams.amount = RedeemLogic.recordRedeemInternal(
            Types.RecordRedeemParams(
                _params.redeemParams,
                totalsupplies,
                newInterest,
                _params.repayParams.to,
                true
            ),
            assets
        );

        RedeemLogic.executeRedeemInternal(
            Types.ExecuteRedeemParams(
                _params.redeemParams,
                _params.protocols,
                protocolsSupplies,
                totalLending
            ),
            totalLendings
        );

        Types.Asset memory redeemAsset = assets[_params.redeemParams.asset];

        if (
            !redeemAsset.collateralable ||
            redeemAsset.sToken.balanceOf(_params.repayParams.to) == 0
        ) {
            _params.config.setUsingAsCollateral(
                _params.repayParams.to,
                _params.redeemParams.asset,
                false
            );
        }

        emit Liquidated(msg.sender, _params.repayParams, _params.redeemParams);
    }

    function getLiquidationData(
        address _account,
        address _repayAsset,
        IConfig _config,
        IPriceOracle _priceOracle,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets
    )
        external
        view
        returns (
            uint256 liquidationAmount,
            uint256 maxLiquidationAmount,
            bool blackListed
        )
    {
        return
            getLiquidationDataInternal(
                _account,
                _repayAsset,
                _config,
                _priceOracle,
                underlyings,
                assets
            );
    }

    function validateLiquidatation(
        Types.LiquidateParams memory _params,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (uint256) {
        uint256 userConfig = _params.config.userDebtAndCollateral(
            _params.repayParams.to
        );
        Types.Asset memory repayAsset = assets[_params.repayParams.asset];
        Types.Asset memory redeemAsset = assets[_params.redeemParams.asset];

        uint256 debtsValue = ExternalUtils.getUserDebts(
            _params.repayParams.to,
            userConfig,
            _params.repayParams.asset,
            _params.priceOracle,
            underlyings,
            assets
        );

        (
            uint256 liquidationThreshold,
            uint256 maxLiquidationAmount,
            bool blackListed
        ) = getLiquidationDataInternal(
                _params.repayParams.to,
                _params.repayParams.asset,
                _params.config,
                _params.priceOracle,
                underlyings,
                assets
            );

        require(
            assets[_params.redeemParams.asset].paused == blackListed,
            "LiquidateLogic: Paused token not liquidated"
        );

        require(
            userConfig.isUsingAsCollateral(redeemAsset.index),
            "LiquidateLogic: Token is not using as collateral"
        );

        require(
            userConfig.isBorrowing(repayAsset.index),
            "LiquidateLogic: Token is not borrowing"
        );

        require(
            debtsValue > liquidationThreshold,
            "LiquidateLogic: Liquidate not allowed"
        );

        return
            _params.repayParams.amount < maxLiquidationAmount
                ? _params.repayParams.amount
                : maxLiquidationAmount;
    }

    function getLiquidationDataInternal(
        address _account,
        address _repayAsset,
        IConfig _config,
        IPriceOracle _priceOracle,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets
    )
        internal
        view
        returns (
            uint256 liquidationAmount,
            uint256 maxLiquidationAmount,
            bool blackListed
        )
    {
        uint256 userConfig = _config.userDebtAndCollateral(_account);

        // stack overflowed if cache underlyings.length
        // uint256 length = underlyings.length;
        for (uint256 i = 0; i < underlyings.length; ) {
            address underlying = underlyings[i];
            Types.Asset memory asset = assets[underlying];

            if (userConfig.isUsingAsCollateral(asset.index)) {
                if (asset.paused) {
                    blackListed = true;
                } else {
                    uint256 collateralAmount = ExternalUtils.getCollateralValue(
                        underlying,
                        _account,
                        _repayAsset,
                        _priceOracle,
                        asset
                    );

                    Types.AssetConfig memory collateralConfig = _config
                        .assetConfigs(underlying);

                    maxLiquidationAmount +=
                        (collateralConfig.maxLiquidateRatio *
                            collateralAmount) /
                        Utils.MILLION;

                    liquidationAmount +=
                        (collateralConfig.liquidateLTV * collateralAmount) /
                        Utils.MILLION;
                }
            }

            unchecked {
                ++i;
            }
        }
    }
}
