// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

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
        address[] storage underlyings,
        mapping(address => uint256) storage totalLendings,
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
                ,
                uint256 protocolsSupplies,
                uint256 totalLending,
                uint256 totalsupplies,
                uint256 newInterest
            ) = ExternalUtils.getSupplyStatus(
                    _params.userParams.asset,
                    _params.reservePool,
                    _params.protocols,
                    totalLendings
                );

            _params.userParams.amount = recordRedeemInternal(
                Types.RecordRedeemParams(
                    _params.userParams,
                    totalsupplies,
                    newInterest,
                    msg.sender,
                    true,
                    _params.collateralable
                ),
                assets
            );

            executeRedeemInternal(
                Types.ExecuteRedeemParams(
                    _params.userParams,
                    _params.protocols,
                    protocolsSupplies,
                    totalLending
                ),
                totalLendings
            );
        }

        bool useAsCollateral = _params.collateralable;
        if (useAsCollateral) {
            Types.Asset memory asset = assets[_params.userParams.asset];
            useAsCollateral =
                asset.collateralable &&
                asset.sToken.balanceOf(msg.sender) != 0;
        }

        _params.config.setUsingAsCollateral(
            msg.sender,
            _params.userParams.asset,
            useAsCollateral
        );

        (bool isHealthy, , ) = ExternalUtils.isPositionHealthy(
            _params.config,
            _params.priceOracle,
            msg.sender,
            _params.userParams.asset,
            underlyings,
            assets
        );

        require(isHealthy, "RedeemLogic: insufficient collateral");
    }

    function recordRedeem(
        Types.RecordRedeemParams memory _params,
        mapping(address => Types.Asset) storage assets
    ) external returns (uint256 underlyingAmount) {
        return recordRedeemInternal(_params, assets);
    }

    function executeRedeem(
        Types.ExecuteRedeemParams memory _params,
        mapping(address => uint256) storage totalLendings
    ) external {
        executeRedeemInternal(_params, totalLendings);
    }

    function recordRedeemInternal(
        Types.RecordRedeemParams memory _params,
        mapping(address => Types.Asset) storage assets
    ) internal returns (uint256 burntAmount) {
        Types.Asset memory asset = assets[_params.userParams.asset];

        uint256 uncollectedFee = asset.dToken.updateNewFee(_params.newInterest);

        burntAmount = asset.sToken.burn(
            _params.redeemFrom,
            _params.notLiquidate,
            _params.userParams.amount,
            _params.totalUnderlying - uncollectedFee
        );

        emit Redeemed(
            _params.redeemFrom,
            _params.userParams.asset,
            burntAmount
        );
    }

    function executeRedeemInternal(
        Types.ExecuteRedeemParams memory _params,
        mapping(address => uint256) storage totalLendings
    ) internal {
        IProtocolsHandler protocolsCache = _params.protocols;

        (, uint256 borrowed) = protocolsCache.redeemAndBorrow(
            _params.userParams.asset,
            _params.userParams.amount,
            _params.protocolsSupplies,
            _params.userParams.to
        );

        ExternalUtils.updateTotalLendings(
            protocolsCache,
            _params.userParams.asset,
            _params.totalLending - borrowed,
            totalLendings
        );
    }
}
