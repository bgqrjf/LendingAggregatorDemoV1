// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./RatesHelper.sol";
import "../interfaces/IRouter.sol";
import "../libraries/internals/Types.sol";

contract QueryHelper is RateGetter {
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
        address underlying;
        uint256 borrowValue;
        uint256 borrowApr;
        uint256 borrowLimit;
        uint256 dailyEstInterest;
    }

    struct TokenInfoWithUser {
        address underlying;
        uint256 tokenPrice;
        uint256 depositAmount;
        uint256 borrowAmount;
        uint256 maxLTV;
        uint256 liquidationThreshold;
    }

    struct SupplyMarket {
        address underlying;
        uint256 supplyAmount;
        uint256 supplyValue;
        uint256 matchAmount;
        uint256[] supplies;
    }

    struct BorrowMarket {
        address underlying;
        uint256 borrowAmount;
        uint256 borrowValue;
        uint256 matchAmount;
        uint256[] borrows;
    }

    IProtocol public aaveLogic;
    IProtocol public compoundLogic;

    constructor(
        address _router,
        address _aaveLogic,
        address _compoundLogic
    ) RateGetter(_router) {
        aaveLogic = IProtocol(_aaveLogic);
        compoundLogic = IProtocol(_compoundLogic);
    }

    function getSTokenConvertRate(address _underlying)
        public
        view
        returns (uint256, uint256)
    {
        ISToken sToken = router.getAsset(_underlying).sToken;
        uint256 rate = sToken.totalSupply() > 0
            ? (sToken.scaledTotalSupply() * 1e18) / sToken.totalSupply()
            : 0;
        uint256 tokenPrice = router.priceOracle().getAssetPrice(_underlying);
        uint256 sTokenPrice = (rate * tokenPrice) / 1e8;
        return (rate, sTokenPrice);
    }

    function getDTokenConvertRate(address _underlying)
        public
        view
        returns (uint256, uint256)
    {
        IDToken dToken = router.getAsset(_underlying).dToken;
        uint256 rate = dToken.totalSupply() > 0
            ? (dToken.totalDebt() * 1e18) / dToken.totalSupply()
            : 0;
        uint256 tokenPrice = router.priceOracle().getAssetPrice(_underlying);
        uint256 dTokenPrice = (rate * tokenPrice) / 1e8;
        return (rate, dTokenPrice);
    }

    function getPlatformInfo()
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
            tokenPrice = router.priceOracle().getAssetPrice(_underlyings[i]);
            totalDeposited += (supplyedAmount * tokenPrice) / 1e8;
            totalBorrowed += (borrowedAmount * tokenPrice) / 1e8;
            totalMatchAmount += (matchAmount * tokenPrice) / 1e8;
        }
        return (totalDeposited, totalBorrowed, totalMatchAmount);
    }

    function getCurrentSupplyRates(address _underlying)
        public
        view
        returns (
            uint256 aggSupplyRate,
            uint256 aaveSupplyRate,
            uint256 compSupplyRate
        )
    {
        aggSupplyRate = getCurrentSupplyRate(_underlying);
        aaveSupplyRate = aaveLogic.getCurrentSupplyRate(_underlying);
        compSupplyRate = compoundLogic.getCurrentSupplyRate(_underlying);
    }

    function getCurrentBorrowRates(address _underlying)
        public
        view
        returns (
            uint256 aggBorrowRate,
            uint256 aaveBorrowRate,
            uint256 compBorrowRate
        )
    {
        aggBorrowRate = getCurrentBorrowRate(_underlying);
        aaveBorrowRate = aaveLogic.getCurrentBorrowRate(_underlying);
        compBorrowRate = compoundLogic.getCurrentBorrowRate(_underlying);
    }

    function getMarketsInfo(address[] memory _underlyings)
        public
        view
        returns (MarketInfo[] memory markets)
    {
        markets = new MarketInfo[](_underlyings.length);
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            markets[i] = getMarketInfo(_underlyings[i]);
        }
    }

    function getMarketInfo(address underlying)
        public
        view
        returns (MarketInfo memory market)
    {
        uint256 tokenPrice = router.priceOracle().getAssetPrice(underlying);
        market.totalSupplied =
            (router.totalSupplied(underlying) * tokenPrice) /
            1e8;
        market.supplyRate = getCurrentSupplyRate(underlying);
        market.totalBorrowed =
            (router.totalBorrowed(underlying) * tokenPrice) /
            1e8;
        market.borrowRate = getCurrentBorrowRate(underlying);
        (, , uint256 matchAmount, , ) = router.getSupplyStatus(underlying);
        market.totalMatched = (matchAmount * tokenPrice) / 1e8;
    }

    function getUserInfo(address user, address _quote)
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

    function getUserSupplied(address user, address quote)
        public
        view
        returns (UserSupplyInfo[] memory userSupplyInfos)
    {
        address[] memory _underlyings = router.getUnderlyings();
        UserSupplyInfo[] memory userSupplyInfo = new UserSupplyInfo[](
            _underlyings.length
        );
        Types.Asset[] memory _assets = router.getAssets();

        uint256 countValid;
        IPriceOracle priceOracle = router.priceOracle();
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            Types.Asset memory _asset = _assets[i];
            uint256 depositAmount = _asset.sToken.scaledBalanceOf(user);
            if (depositAmount == 0) {
                continue;
            }
            uint256 depositApr = getCurrentSupplyRate(_underlyings[i]);

            userSupplyInfo[i].underlying = _underlyings[i];
            userSupplyInfo[i].depositValue = priceOracle.valueOfAsset(
                _underlyings[i],
                quote,
                depositAmount
            );
            userSupplyInfo[i].depositApr = depositApr;
            userSupplyInfo[i].availableBalance = IERC20(_underlyings[i])
                .balanceOf(user);
            userSupplyInfo[i].dailyEstProfit =
                (userSupplyInfo[i].depositValue * depositApr) /
                365; //maybe wrong,will check later
            userSupplyInfo[i].collateral = router.isUsingAsCollateral(
                _underlyings[i],
                user
            );
            ++countValid;
        }

        userSupplyInfos = new UserSupplyInfo[](countValid);
        uint256 j = 0;
        for (uint256 i = 0; i < userSupplyInfo.length && j < countValid; ++i) {
            if (userSupplyInfo[i].underlying != address(0)) {
                userSupplyInfos[j] = userSupplyInfo[i];
                ++j;
            }
        }
    }

    function getUserBorrowed(address user, address quote)
        public
        view
        returns (UserBorrowInfo[] memory userBorrowInfos)
    {
        address[] memory _underlyings = router.getUnderlyings();
        UserBorrowInfo[] memory userBorrowInfoTemp = new UserBorrowInfo[](
            _underlyings.length
        );
        Types.Asset[] memory _assets = router.getAssets();
        IPriceOracle priceOracle = router.priceOracle();
        uint256 countValid;
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            Types.Asset memory _asset = _assets[i];
            uint256 borrowAmount = _asset.dToken.scaledDebtOf(user);
            if (borrowAmount == 0) {
                continue;
            }
            uint256 borrowApr = getCurrentBorrowRate(_underlyings[i]);

            userBorrowInfoTemp[i].underlying = _underlyings[i];
            userBorrowInfoTemp[i].borrowValue = priceOracle.valueOfAsset(
                _underlyings[i],
                quote,
                borrowAmount
            );
            userBorrowInfoTemp[i].borrowApr = borrowApr;
            userBorrowInfoTemp[i].borrowLimit = router.borrowLimit(
                user,
                _underlyings[i]
            );
            userBorrowInfoTemp[i].dailyEstInterest =
                (userBorrowInfoTemp[i].borrowValue * borrowApr) /
                365; //maybe wrong,will check later

            ++countValid;
        }

        userBorrowInfos = new UserBorrowInfo[](countValid);
        uint256 j;
        for (
            uint256 i = 0;
            i < userBorrowInfoTemp.length && j < countValid;
            ++i
        ) {
            if (userBorrowInfoTemp[i].underlying != address(0)) {
                userBorrowInfos[j] = userBorrowInfoTemp[i];
                ++j;
            }
        }
    }

    function getTokenInfoWithUser(address user)
        public
        view
        returns (TokenInfoWithUser[] memory tokenInfoWithUser)
    {
        address[] memory _underlyings = router.getUnderlyings();
        tokenInfoWithUser = new TokenInfoWithUser[](_underlyings.length);
        Types.Asset[] memory _assets = router.getAssets();
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            Types.Asset memory _asset = _assets[i];
            Types.AssetConfig memory _conifg = router.config().assetConfigs(
                _underlyings[i]
            );
            uint256 depositAmount = _asset.sToken.scaledBalanceOf(user);
            uint256 borrowAmount = _asset.dToken.scaledDebtOf(user);
            uint256 tokenPrice = router.priceOracle().getAssetPrice(
                _underlyings[i]
            );

            tokenInfoWithUser[i].underlying = _underlyings[i];
            tokenInfoWithUser[i].tokenPrice = tokenPrice;
            tokenInfoWithUser[i].depositAmount = depositAmount;
            tokenInfoWithUser[i].borrowAmount = borrowAmount;
            tokenInfoWithUser[i].maxLTV = _conifg.maxLTV;
            tokenInfoWithUser[i].liquidationThreshold = _conifg.liquidateLTV;
        }
    }

    function getSupplyMarkets()
        public
        view
        returns (SupplyMarket[] memory supplyMarket)
    {
        address[] memory _underlyings = router.getUnderlyings();
        supplyMarket = new SupplyMarket[](_underlyings.length);

        for (uint256 i = 0; i < _underlyings.length; ++i) {
            (
                uint256[] memory supplies,
                ,
                uint256 totalLending,
                uint256 totalSuppliedAmountWithFee,

            ) = router.getSupplyStatus(_underlyings[i]);

            uint256 tokenPrice = router.priceOracle().getAssetPrice(
                _underlyings[i]
            );

            supplyMarket[i].underlying = _underlyings[i];
            supplyMarket[i].supplyAmount = totalSuppliedAmountWithFee;
            supplyMarket[i].supplyValue =
                (totalSuppliedAmountWithFee * tokenPrice) /
                1e8;
            supplyMarket[i].matchAmount = totalLending;
            supplyMarket[i].supplies = supplies;
        }
    }

    function getBorrowMarkets()
        public
        view
        returns (BorrowMarket[] memory borrowMarket)
    {
        address[] memory _underlyings = router.getUnderlyings();
        borrowMarket = new BorrowMarket[](_underlyings.length);
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            (
                uint256[] memory borrows,
                uint256 totalBorrowedAmount,
                uint256 totalLending,

            ) = router.getBorrowStatus(_underlyings[i]);

            uint256 tokenPrice = router.priceOracle().getAssetPrice(
                _underlyings[i]
            );
            borrowMarket[i].underlying = _underlyings[i];
            borrowMarket[i].borrowAmount = totalBorrowedAmount;
            borrowMarket[i].borrowValue =
                (totalBorrowedAmount * tokenPrice) /
                1e8;
            borrowMarket[i].matchAmount = totalLending;
            borrowMarket[i].borrows = borrows;
        }
    }
}
