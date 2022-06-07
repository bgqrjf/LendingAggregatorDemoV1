// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./SToken.sol";
import "./DToken.sol";

contract Types{
    struct BorrowConfig{
        uint maxLTV;
        uint liquidateLTV;
        uint maxLiquidateRatio;
        uint liquidateRewardRatio;
    }

    struct Asset{
        uint8 index;
        SToken sToken; // supply token address
        DToken dToken; // debt token address
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
        uint slope1;
        uint slope2;
        uint base;
        uint totalBorrowed;
        uint apy;
    }
}