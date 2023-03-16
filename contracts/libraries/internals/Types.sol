// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../../interfaces/ISToken.sol";
import "../../interfaces/IDToken.sol";

import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IPriceOracle.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";
import "../../interfaces/IConfig.sol";

library Types {
    struct AssetConfig {
        uint256 maxLTV;
        uint256 liquidateLTV;
        uint256 maxLiquidateRatio;
        uint256 liquidateRewardRatio;
        uint256 feeRate;
    }

    struct Asset {
        uint8 index;
        bool collateralable;
        bool paused;
        ISToken sToken; // supply token address
        IDToken dToken; // debt token address
    }

    struct NewAssetParams {
        address underlying;
        uint8 decimals;
        bool collateralable;
        string sTokenName;
        string sTokenSymbol;
        string dTokenName;
        string dTokenSymbol;
        AssetConfig config;
        uint256 maxReserve;
        uint256 executeSupplyThreshold;
    }

    struct AAVEV2UsageParams {
        uint256 totalSupplied; // not balance
        uint256 totalBorrowed;
        uint256 totalBorrowedStable;
        uint256 totalBorrowedVariable;
        uint256 slopeV1;
        uint256 slopeV2;
        uint256 slopeS1;
        uint256 slopeS2;
        uint256 baseV;
        uint256 optimalLTV;
        uint256 reserveFactor;
        uint256 maxExcessUsageRatio;
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

    struct RouterCompRewardData {
        RouterCompReward supply;
        RouterCompReward borrow;
    }

    struct RouterCompReward {
        uint256 rewardPerShare;
        uint256 index;
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

    struct SupplyParams {
        UserAssetParams userParams;
        bool collateralable;
        bool executeNow;
        bool actionNotPaused;
        IProtocolsHandler protocols;
        IReservePool reservePool;
        IRewards rewards;
        IConfig config;
        Asset asset;
    }

    struct RedeemParams {
        UserAssetParams userParams;
        bool collateralable;
        bool executeNow;
        bool actionNotPaused;
        IProtocolsHandler protocols;
        IReservePool reservePool;
        IRewards rewards;
        IConfig config;
        IPriceOracle priceOracle;
        uint256 collectedFee;
        address[] underlyings;
    }

    struct BorrowParams {
        UserAssetParams userParams;
        bool executeNow;
        bool actionNotPaused;
        IProtocolsHandler protocols;
        IReservePool reservePool;
        IRewards rewards;
        IConfig config;
        IPriceOracle priceOracle;
        uint256 collectedFee;
        address[] underlyings;
    }

    struct RepayParams {
        UserAssetParams userParams;
        bool executeNow;
        bool actionNotPaused;
        address feeCollector;
        IProtocolsHandler protocols;
        IReservePool reservePool;
        IRewards rewards;
        IConfig config;
        IPriceOracle priceOracle;
        uint256 collectedFee;
        uint256 userFeeIndexes;
        Asset asset;
    }

    struct RecordRepayParams {
        UserAssetParams userParams;
        IConfig config;
        IRewards rewards;
        uint256 userFeeIndexes;
        Asset asset;
    }

    struct RecordBorrowParams {
        UserAssetParams userParams;
        uint256 newInterest;
        uint256 totalBorrows;
        address borrowBy;
        IConfig config;
        IRewards rewards;
    }

    struct LiquidateParams {
        RepayParams repayParams;
        RedeemParams redeemParams;
        bool actionNotPaused;
        address[] underlyings;
    }

    struct ClaimRewardsParams {
        bool actionNotPaused;
        address account;
        IProtocolsHandler protocols;
        IConfig config;
        IRewards rewards;
        address[] underlyings;
    }
}
