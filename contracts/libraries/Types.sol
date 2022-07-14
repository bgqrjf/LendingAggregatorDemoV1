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

    struct AAVEUsageParams{
        uint totalSupplied; // not balance
        uint totalBorrowed;
        uint totalBorrowedStable;
        uint totalBorrowedVariable;
        uint unbacked;
        uint slopeV1;
        uint slopeV2;
        uint slopeS1;
        uint slopeS2;
        uint baseS;  // actual base * 10^6
        uint baseV;
        uint optimalLTV;
        uint reserveFactor;
        uint stableToTotalDebtRatio;
        uint optimalStableToTotalDebtRatio;
        uint maxExcessStableToTotalDebtRatio;
        uint maxExcessUsageRatio;
    }

    struct CompoundUsageParams{
        uint totalSupplied; // not balance
        uint totalBorrowed;
        uint slope1;
        uint slope2;
        uint base;
        uint optimalLTV;
        uint reserveFactor;
    }

    struct ProviderData{
        bool initialized;
        address target;
        address approveTo;
        address payable weth;
        address rewardToken;
        uint rewardBalance;
        bytes encodedData;
    }

    struct CompRewardData{
        uint supplierIndex;
        uint borrowerIndex;
        uint compAccured;
    }

    struct UserShare{
        uint sTokenAmount;
        uint sTokenTotalSupply;
        uint dTokenAmount;
        uint dTokenTotalSupply;
    }

    struct StrategyParams{
        uint targetAmount;
        uint targetRate0;
        uint targetIndex;
        bytes[] usageParams;
        address[] providers;
    }
}