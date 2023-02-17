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
        address borrower,
        address liquidator,
        address repayedToken,
        uint256 repayedAmount,
        address redeemedToken,
        uint256 redeemedAmount,
        uint256 penaltyRatio
    );

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
        require(_params.actionNotPaused, "LiquidateLogic: action paused");

        _params.repayParams.userParams.amount = validateLiquidatation(
            _params,
            assets
        );

        _params.repayParams.userParams.amount = RepayLogic.repayInternal(
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
                "LiquidateLogic: insufficient redeem amount"
            );
            _params.redeemParams.userParams.amount = redeemAmount;
        }
        (_params.redeemParams.userParams.amount, ) = RedeemLogic
            .recordRedeemInternal(
                _params.redeemParams,
                protocolsSupplies + totalLending,
                0,
                _params.repayParams.userParams.to,
                accFees,
                assets
            );

        RedeemLogic.executeRedeemInternal(
            _params.redeemParams,
            supplies,
            protocolsSupplies,
            totalLending,
            totalLendings
        );

        // emit Liquidated(
        //    msg.sender,
        //     _params.redeemParams.to,
        //     _params.redeemedAmount.asset,
        //     _params.redeemedAmount.amount,
        // );
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
        ) = getLiquidationDataInternal(
                _params.repayParams.userParams.to,
                _params.repayParams.userParams.asset,
                _params.underlyings,
                _params.repayParams.config,
                _params.repayParams.priceOracle,
                assets
            );

        require(
            assets[_params.redeemParams.userParams.asset].paused == blackListed,
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
            _params.repayParams.userParams.amount < maxLiquidationAmount
                ? _params.repayParams.userParams.amount
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
