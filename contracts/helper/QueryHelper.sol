// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MulticallHelper.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ISToken.sol";
import "../interfaces/IDToken.sol";
import "../interfaces/IRateGetter.sol";
import "../libraries/internals/Types.sol";

contract QueryHelper is MulticallHelper {
    struct Asset {
        uint8 index;
        bool collateralable;
        bool paused;
        ISToken sToken; // supply token address
        IDToken dToken; // debt token address
    }

    struct MarketInfo {
        uint256 totalSupplied;
        uint256 supplyRate;
        uint256 totalBorrowed;
        uint256 borrowRate;
        uint256 totalMatched;
    }

    struct UserSupplyInfo {
        address underlying;
        uint256 depositValue;
        uint256 depositApr;
        uint256 availableBalance;
        uint256 dailyEstProfit;
        bool collateral;
    }

    struct UserBorrowInfo {
        uint256 totalDeposit;
        uint256 totalBorrow;
        uint256 totalCollateralValue;
        uint256 borrowLimit;
    }

    function getSTokenConvertRate(ISToken sToken, IPriceOracle oracle)
        public
        view
        returns (uint256, uint256)
    {
        address underlying = sToken.underlying();
        uint256 rate = sToken.totalSupply() > 0
            ? sToken.scaledTotalSupply() / sToken.totalSupply()
            : 0;
        uint256 tokenPrice = oracle.getAssetPrice(underlying);
        uint256 sTokenPrice = (rate * tokenPrice) / 1e8;
        return (rate, sTokenPrice);
    }

    function getDTokenConvertRate(IDToken dToken, IPriceOracle oracle)
        public
        view
        returns (uint256, uint256)
    {
        address underlying = dToken.underlying();
        uint256 rate = dToken.totalSupply() > 0
            ? dToken.totalDebt() / dToken.totalSupply()
            : 0;
        uint256 tokenPrice = oracle.getAssetPrice(underlying);
        uint256 dTokenPrice = (rate * tokenPrice) / 1e8;
        return (rate, dTokenPrice);
    }

    function getPlatformInfo(IRouter router, IPriceOracle oracle)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 totalMatchAmount;
        uint256 supplyedAmount;
        uint256 borrowedAmount;
        uint256 matchAmount;
        uint256 tokenPrice;
        address[] memory _underlyings = router.getUnderlyings();
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            supplyedAmount = router.totalSupplied(_underlyings[i]);
            borrowedAmount = router.totalBorrowed(_underlyings[i]);
            (, , matchAmount, , ) = router.getSupplyStatus(_underlyings[i]);
            tokenPrice = oracle.getAssetPrice(_underlyings[i]);
            totalDeposited += (supplyedAmount * tokenPrice) / 1e8;
            totalBorrowed += (borrowedAmount * tokenPrice) / 1e8;
            totalMatchAmount += (matchAmount * tokenPrice) / 1e8;
        }
        return (totalDeposited, totalBorrowed, totalMatchAmount);
    }

    function getMarketsInfo(
        IRouter router,
        IPriceOracle oracle,
        IRateGetter rateGetter
    ) public view returns (MarketInfo[] memory markets) {
        address[] memory _underlyings = router.getUnderlyings();
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            uint256 tokenPrice = oracle.getAssetPrice(_underlyings[i]);
            markets[i].totalSupplied =
                (router.totalSupplied(_underlyings[i]) * tokenPrice) /
                1e8;
            markets[i].supplyRate = rateGetter.getSupplyRate(_underlyings[i]);
            markets[i].totalBorrowed =
                (router.totalBorrowed(_underlyings[i]) * tokenPrice) /
                1e8;
            markets[i].supplyRate = rateGetter.getBorrowRate(_underlyings[i]);
            (, , uint256 matchAmount, , ) = router.getSupplyStatus(
                _underlyings[i]
            );
            markets[i].totalMatched = (matchAmount * tokenPrice) / 1e8;
        }
    }

    function getUserInfo(
        IRouter router,
        address user,
        address _quote
    )
        public
        view
        returns (
            uint256 collateralValue,
            uint256 borrowingValue,
            uint256 borrowLimit
        )
    {
        (collateralValue, borrowingValue, ) = router.userStatus(user, _quote);
        borrowLimit = router.borrowLimit(user, _quote);
    }

    function getUserSupplied(
        IRouter router,
        IPriceOracle oracle,
        IRateGetter rateGetter,
        address user
    ) public view returns (UserSupplyInfo[] memory userSupplyInfo) {
        address[] memory _underlyings = router.getUnderlyings();
        Types.Asset[] memory _assets = router.getAssets();
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            Types.Asset memory _asset = _assets[i];
            uint256 depositAmount = _asset.sToken.scaledBalanceOf(user);
            if (depositAmount == 0) {
                continue;
            }
            uint256 tokenPrice = oracle.getAssetPrice(_underlyings[i]);
            uint256 depositApr = rateGetter.getSupplyRate(_underlyings[i]);

            userSupplyInfo[i].underlying = _underlyings[i];
            userSupplyInfo[i].depositValue = (depositAmount * tokenPrice) / 1e8;
            userSupplyInfo[i].depositApr = depositApr;
            userSupplyInfo[i].availableBalance = IERC20(_underlyings[i])
                .balanceOf(user);
            userSupplyInfo[i].dailyEstProfit =
                (((depositAmount * tokenPrice) / 1e8) * depositApr) /
                365; //maybe wrong,will check later
            userSupplyInfo[i].collateral = router.isUsingAsCollateral(
                _underlyings[i],
                user
            );
        }
    }
}
