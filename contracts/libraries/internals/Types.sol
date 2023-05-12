// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../interfaces/IConfig.sol";
import "../../interfaces/IDToken.sol";
import "../../interfaces/IPriceOracle.sol";
import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";
import "../../interfaces/ISToken.sol";

library Types {
    struct SupplyParams {
        UserAssetParams userParams;
        bool collateralable;
        bool executeNow;
        bool actionNotPaused;
        IProtocolsHandler protocols;
        IReservePool reservePool;
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
        uint256 protocolsSupplies;
    }

    struct RedeemParams {
        UserAssetParams userParams;
        bool collateralable;
        bool executeNow;
        bool actionNotPaused;
        IProtocolsHandler protocols;
        IReservePool reservePool;
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
    }

    struct ExecuteRedeemParams {
        UserAssetParams userParams;
        IProtocolsHandler protocols;
        uint256 protocolsSupplies;
        uint256 totalLending;
    }

    struct BorrowParams {
        UserAssetParams userParams;
        bool executeNow;
        bool actionNotPaused;
        IProtocolsHandler protocols;
        IReservePool reservePool;
        IConfig config;
        IPriceOracle priceOracle;
    }

    struct RecordBorrowParams {
        UserAssetParams userParams;
        uint256 newInterest;
        uint256 totalBorrows;
        address borrowBy;
    }

    struct RepayParams {
        UserAssetParams userParams;
        bool executeNow;
        bool actionNotPaused;
        address feeCollector;
        IProtocolsHandler protocols;
        IReservePool reservePool;
        IConfig config;
        IPriceOracle priceOracle;
        Asset asset;
    }

    struct RecordRepayParams {
        UserAssetParams userParams;
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
        uint256 minBorrow;
        AssetConfig config;
        uint256 maxReserve;
        uint256 executeSupplyThreshold;
    }

    struct UserAssetParams {
        address asset;
        uint256 amount;
        address to;
    }
}
