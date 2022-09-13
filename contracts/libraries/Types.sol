// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/ISToken.sol";
import "../interfaces/IDToken.sol";

library Types {
    struct BorrowConfig {
        uint256 maxLTV;
        uint256 liquidateLTV;
        uint256 maxLiquidateRatio;
        uint256 liquidateRewardRatio;
    }

    struct Asset {
        uint8 index;
        ISToken sToken; // supply token address
        IDToken dToken; // debt token address
        bool collateralable;
    }

    struct NewAssetParams {
        address underlying;
        uint8 decimals;
        bool collateralable;
        string sTokenName;
        string sTokenSymbol;
        string dTokenName;
        string dTokenSymbol;
        BorrowConfig borrowConfig;
    }

    struct AAVEUsageParams {
        uint256 totalSupplied; // not balance
        uint256 totalBorrowed;
        uint256 totalBorrowedStable;
        uint256 totalBorrowedVariable;
        uint256 unbacked;
        uint256 slopeV1;
        uint256 slopeV2;
        uint256 slopeS1;
        uint256 slopeS2;
        uint256 baseS; // actual base * 10^6
        uint256 baseV;
        uint256 optimalLTV;
        uint256 reserveFactor;
        uint256 stableToTotalDebtRatio;
        uint256 optimalStableToTotalDebtRatio;
        uint256 maxExcessStableToTotalDebtRatio;
        uint256 maxExcessUsageRatio;
    }

    struct CompoundUsageParams {
        uint256 totalSupplied; // not balance
        uint256 totalBorrowed;
        uint256 slope1;
        uint256 slope2;
        uint256 base;
        uint256 optimalLTV;
        uint256 reserveFactor;
    }

    struct ProtocolData {
        bool initialized;
        address target;
        address approveTo;
        address payable weth;
        address rewardToken;
        uint256 rewardBalance;
        bytes encodedData;
    }

    struct UserCompRewardData {
        UserCompReward supply;
        UserCompReward borrow;
    }

    struct UserCompReward {
        uint256 rewardPerShare;
        uint256 rewardAccured;
        uint256 rewardCollected;
    }

    struct RouterCompRewardData {
        RouterCompReward supply;
        RouterCompReward borrow;
    }

    struct RouterCompReward {
        uint256 rewardPerShare;
        uint256 index;
    }

    struct UserShare {
        uint256 amount;
        uint256 total;
    }

    struct StrategyParams {
        uint256 targetAmount;
        uint128 maxRate;
        uint128 minRate;
        uint256[] minAmounts;
        uint256[] maxAmounts;
        bytes[] usageParams;
    }

    struct UserAssetParams {
        address asset;
        uint256 amount;
        address to;
    }
}
