// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../internals/Types.sol";
import "../internals/UserAssetBitMap.sol";

library RewardLogic {
    using UserAssetBitMap for uint256;

    function claimRewards(
        Types.ClaimRewardsParams memory _params,
        mapping(address => Types.Asset) storage assets
    ) external {
        require(_params.actionNotPaused, "Rewards: action paused");
        uint256 userConfig = _params.config.userDebtAndCollateral(
            _params.account
        );
        uint256[] memory rewardsToClaim;

        for (uint256 i = 0; i < _params.underlyings.length; ++i) {
            if (userConfig.isUsingAsCollateralOrBorrowing(i)) {
                Types.Asset memory asset = assets[_params.underlyings[i]];

                if (userConfig.isUsingAsCollateral(asset.index)) {
                    address underlying = asset.sToken.underlying();
                    uint256[] memory amounts = _params.rewards.claim(
                        underlying,
                        _params.account,
                        asset.sToken.totalSupply()
                    );

                    for (uint256 j = 0; j < amounts.length; j++) {
                        rewardsToClaim[j] += amounts[j];
                    }
                }

                if (userConfig.isBorrowing(asset.index)) {
                    address underlying = asset.dToken.underlying();
                    uint256[] memory amounts = _params.rewards.claim(
                        underlying,
                        _params.account,
                        asset.dToken.totalSupply()
                    );
                    for (uint256 j = 0; j < amounts.length; j++) {
                        rewardsToClaim[j] += amounts[j];
                    }
                }
            }
        }

        _params.protocols.claimRewards(_params.account, rewardsToClaim);
    }
}
