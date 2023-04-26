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

    event Liquidated(
        address indexed liquidator,
        Types.UserAssetParams repayParams,
        Types.UserAssetParams redeemParams
    );

    // _redeemParams.amount is the minAmount redeem which is used as slippage validation
    function liquidate(
        Types.LiquidateParams memory _params,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets,
        mapping(address => uint256) storage totalLendings
    ) external {
        // actionNotPaused(_repayParams.asset, Action.liquidate);
        require(_params.actionNotPaused, "LiquidateLogic: action paused");

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

        if (
            assets[_params.repayParams.asset].dToken.balanceOf(msg.sender) == 0
        ) {
            _params.config.setBorrowing(
                msg.sender,
                _params.repayParams.asset,
                false
            );
        }

        // redeem
        (
            uint256[] memory supplies,
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
                false,
                true
            ),
            assets
        );

        RedeemLogic.executeRedeemInternal(
            Types.ExecuteRedeemParams(
                _params.redeemParams,
                _params.protocols,
                supplies,
                protocolsSupplies,
                totalLending
            ),
            totalLendings
        );

        Types.Asset memory redeemAsset = assets[_params.redeemParams.asset];

        if (
            !redeemAsset.collateralable ||
            redeemAsset.sToken.balanceOf(msg.sender) == 0
        ) {
            _params.config.setUsingAsCollateral(
                msg.sender,
                _params.redeemParams.asset,
                false
            );
        }

        emit Liquidated(msg.sender, _params.repayParams, _params.redeemParams);
    }

    function getLiquidationData(
        address _account,
        address _repayAsset,
        address[] memory _underlyings,
        IConfig _config,
        IPriceOracle _priceOracle,
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
                _underlyings,
                _config,
                _priceOracle,
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
            underlyings,
            _params.repayParams.asset,
            _params.priceOracle,
            assets
        );

        (
            uint256 liquidationThreshold,
            uint256 maxLiquidationAmount,
            bool blackListed
        ) = getLiquidationDataInternal(
                _params.repayParams.to,
                _params.repayParams.asset,
                underlyings,
                _params.config,
                _params.priceOracle,
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
        address[] memory _underlyings,
        IConfig _config,
        IPriceOracle _priceOracle,
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

        for (uint256 i = 0; i < _underlyings.length; ++i) {
            if (userConfig.isUsingAsCollateral(i)) {
                address underlying = _underlyings[i];

                uint256 sTokenBalance = assets[underlying]
                    .sToken
                    .scaledBalanceOf(_account);

                uint256 collateralAmount = underlying == _repayAsset
                    ? sTokenBalance
                    : _priceOracle.valueOfAsset(
                        underlying,
                        _repayAsset,
                        sTokenBalance
                    );

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

                blackListed = blackListed || blackListedNew;
            }
        }
    }
}
