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

    struct RecordSupplyParams {
        UserAssetParams userParams;
        ISToken sToken;
        IDToken dToken;
        uint256 totalUnderlying;
        uint256 newInterest;
    }

    struct ExecuteSupplyParams {
        address asset;
        uint256 amount;
        uint256 totalLending;
        uint256[] supplies;
        uint256 protocolsSupplies;
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
    }

    struct RecordRedeemParams {
        UserAssetParams userParams;
        uint256 totalUnderlying;
        uint256 newInterest;
        address redeemFrom;
        bool notLiquidate;
        bool collateralable;
        IRewards rewards;
    }

    struct ExecuteRedeemParams {
        UserAssetParams userParams;
        IProtocolsHandler protocols;
        uint256[] supplies;
        uint256 protocolsSupplies;
        uint256 totalLending;
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
    }

    struct RecordBorrowParams {
        UserAssetParams userParams;
        uint256 newInterest;
        uint256 totalBorrows;
        address borrowBy;
        IRewards rewards;
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
        Asset asset;
    }

    struct RecordRepayParams {
        UserAssetParams userParams;
        IRewards rewards;
        Asset asset;
        uint256 newInterest;
        uint256 totalBorrows;
    }

    struct LiquidateParams {
        UserAssetParams repayParams;
        UserAssetParams redeemParams;
        address feeCollector;
        IProtocolsHandler protocols;
        IReservePool reservePool;
        IRewards rewards;
        IConfig config;
        IPriceOracle priceOracle;
        bool actionNotPaused;
    }

    struct AssetConfig {
        uint256 maxLTV;
        uint256 liquidateLTV;
        uint256 maxLiquidateRatio;
        uint256 liquidateRewardRatio;
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
        uint256 feeRate;
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
        uint256 bestPoolToAddExtra;
        uint256[] minAmounts;
        uint256[] maxAmounts;
        bytes[] usageParams;
    }

    struct UserAssetParams {
        address asset;
        uint256 amount;
        address to;
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
