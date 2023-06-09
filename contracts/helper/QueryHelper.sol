// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./RatesHelper.sol";
import "../libraries/internals/Types.sol";
import "../libraries/internals/ExternalUtils.sol";

contract QueryHelper is RatesHelper {
    using Math for uint256;
    using UserAssetBitMap for uint256;

    constructor(address _router) RatesHelper(_router) {}

    function simulateRebalance(
        address _underlying
    ) external returns (uint256 rate, uint256[] memory protocolsRates) {
        router.protocols().rebalanceAllProtocols(_underlying);
        return getCurrentSupplyRates(_underlying);
    }

    function getRewardAPY(
        address _account,
        address _quote
    ) external returns (uint256) {
        uint256 userConfig = router.config().userDebtAndCollateral(_account);
        IPriceOracle priceOracle = router.priceOracle();
        Types.Asset[] memory assets = router.getAssets();

        uint256 collateralValue;
        uint256 reward;

        address[] memory underlyings = router.getUnderlyings();
        uint256 length = underlyings.length;
        for (uint256 i = 0; i < length; ) {
            address underlying = underlyings[i];
            Types.Asset memory asset = assets[i];

            if (userConfig.isUsingAsCollateral(asset.index) && !asset.paused) {
                collateralValue += ExternalUtils.getCollateralValue(
                    underlying,
                    _account,
                    _quote,
                    priceOracle,
                    asset
                );

                reward +=
                    asset.sToken.claimRewards(_account) +
                    asset.dToken.claimRewards(_account);
            }

            unchecked {
                ++i;
            }
        }

        address rewardToken = router.rewards().rewardsToken(address(0), 0);

        return
            (priceOracle.valueOfAsset(rewardToken, _quote, reward) *
                Utils.MILLION) / collateralValue;
    }

    function maxRedeem(
        address _account,
        address _underlying
    ) external view returns (uint256) {
        Types.Asset memory asset = router.getAsset(_underlying);
        if (router.isUsingAsCollateral(_underlying, _account)) {
            (uint256 collateral, uint256 borrowed) = router.userStatus(
                _account,
                _underlying
            );

            uint256 liquidateLTV = router
                .config()
                .assetConfigs(_underlying)
                .liquidateLTV;
            uint256 minCollateral = (borrowed * Utils.MILLION).ceilDiv(
                liquidateLTV
            );
            uint256 maxRedeemAllowed = collateral > minCollateral
                ? collateral - minCollateral
                : 0;

            return
                Math.min(
                    maxRedeemAllowed,
                    asset.sToken.scaledBalanceOf(_account)
                );
        } else {
            return asset.sToken.scaledBalanceOf(_account);
        }
    }
}
