// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/ISToken.sol";
import "../interfaces/IDToken.sol";

library Types{
    struct BorrowConfig{
        uint maxLTV;
        uint liquidateLTV;
        uint maxLiquidateRatio;
        uint liquidateRewardRatio;
    }

    struct Asset{
        uint8 index;
        ISToken sToken; // supply token address
        IDToken dToken; // debt token address
        bool collateralable; 
        uint sReserve;
        uint dReserve;
    }

    struct NewAssetParams{
        address underlying;
        uint8 decimals;
        bool collateralable;
        string sTokenName;
        string sTokenSymbol;
        string dTokenName;
        string dTokenSymbol;
        BorrowConfig borrowConfig;
    }

    struct UsageParams{
        uint totalSupplied; // not balance
        uint totalBorrowed;
        uint32 slope1;
        uint32 slope2;
        uint32 base;  // actual base * 10^6
        uint32 optimalLTV;
        uint32 rate; // block percentange yield
        uint32 reserveFactor;
    }
}