// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./RatesHelper.sol";
import "../interfaces/IRouter.sol";
import "../libraries/internals/Types.sol";

contract QueryHelper is RateGetter {
    struct MarketInfo {
        address underlying;
        uint256 totalSupplied;
        uint256 supplyRate;
        uint256 totalBorrowed;
        uint256 borrowRate;
        uint256 totalMatched;
    }

    struct UserSupplyInfo {
        address underlying;
        uint256 depositAmount;
        uint256 depositValue;
        uint256 depositApr;
        uint256 availableBalance;
        uint256 dailyEstProfit;
        bool collateral;
    }

    struct UserBorrowInfo {
        address underlying;
        uint256 borrowAmount;
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

    function getPlatformsInfo(address[] memory _underlyings, address _quote)
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
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            (
                uint256 depositedValue,
                uint256 totalBorrowedValue,
                uint256 matchAmountValue
            ) = getPlatformInfo(_underlyings[i], _quote);
            totalDeposited += depositedValue;
            totalBorrowed += totalBorrowedValue;
            totalMatchAmount += matchAmountValue;
        }
        return (totalDeposited, totalBorrowed, totalMatchAmount);
    }

    function getPlatformInfo(address _underlying, address _quote)
        public
        view
        returns (
            uint256 depositedValue,
            uint256 totalBorrowedValue,
            uint256 matchAmountValue
        )
    {
        uint256 matchAmount;
        IPriceOracle priceOracle = router.priceOracle();
        (, , matchAmount, , ) = router.getSupplyStatus(_underlying);

        depositedValue = priceOracle.valueOfAsset(
            _underlying,
            _quote,
            router.totalSupplied(_underlying)
        );
        totalBorrowedValue = priceOracle.valueOfAsset(
            _underlying,
            _quote,
            router.totalBorrowed(_underlying)
        );
        matchAmountValue = priceOracle.valueOfAsset(
            _underlying,
            _quote,
            matchAmount
        );
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

    function getMarketsInfo(address[] memory _underlyings, address _quote)
        public
        view
        returns (MarketInfo[] memory markets)
    {
        markets = new MarketInfo[](_underlyings.length);
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            markets[i] = getMarketInfo(_underlyings[i], _quote);
        }
    }

    function getMarketInfo(address _underlying, address _quote)
        public
        view
        returns (MarketInfo memory market)
    {
        IPriceOracle priceOracle = router.priceOracle();

        market.underlying = _underlying;
        market.totalSupplied = priceOracle.valueOfAsset(
            _underlying,
            _quote,
            router.totalSupplied(_underlying)
        );
        market.supplyRate = getCurrentSupplyRate(_underlying);
        market.totalBorrowed = priceOracle.valueOfAsset(
            _underlying,
            _quote,
            router.totalBorrowed(_underlying)
        );
        market.borrowRate = getCurrentBorrowRate(_underlying);
        (, , uint256 matchAmount, , ) = router.getSupplyStatus(_underlying);
        market.totalMatched = priceOracle.valueOfAsset(
            _underlying,
            _quote,
            matchAmount
        );
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

            userSupplyInfo[i] = UserSupplyInfo(
                _underlyings[i],
                depositAmount,
                priceOracle.valueOfAsset(_underlyings[i], quote, depositAmount),
                getCurrentSupplyRate(_underlyings[i]),
                IERC20(_underlyings[i]).balanceOf(user),
                0,
                router.isUsingAsCollateral(_underlyings[i], user)
            );

            userSupplyInfo[i].dailyEstProfit =
                (userSupplyInfo[i].depositValue *
                    userSupplyInfo[i].depositApr) /
                (Utils.MILLION * 365);

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

            userBorrowInfoTemp[i] = UserBorrowInfo(
                _underlyings[i],
                borrowAmount,
                priceOracle.valueOfAsset(_underlyings[i], quote, borrowAmount),
                getCurrentBorrowRate(_underlyings[i]),
                router.borrowLimit(user, _underlyings[i]),
                0
            );

            userBorrowInfoTemp[i].dailyEstInterest =
                (userBorrowInfoTemp[i].borrowValue *
                    userBorrowInfoTemp[i].borrowApr) /
                (365 * Utils.MILLION);

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

    function getSupplyMarkets(address _quote)
        public
        view
        returns (SupplyMarket[] memory supplyMarket)
    {
        address[] memory _underlyings = router.getUnderlyings();
        supplyMarket = new SupplyMarket[](_underlyings.length);
        IPriceOracle priceOracle = router.priceOracle();

        for (uint256 i = 0; i < _underlyings.length; ++i) {
            (
                uint256[] memory supplies,
                ,
                uint256 totalLending,
                uint256 totalSuppliedAmountWithFee,

            ) = router.getSupplyStatus(_underlyings[i]);

            supplyMarket[i].underlying = _underlyings[i];
            supplyMarket[i].supplyAmount = totalSuppliedAmountWithFee;
            supplyMarket[i].supplyValue = priceOracle.valueOfAsset(
                _underlyings[i],
                _quote,
                totalSuppliedAmountWithFee
            );
            supplyMarket[i].matchAmount = totalLending;
            supplyMarket[i].supplies = supplies;
        }
    }

    function getBorrowMarkets(address _quote)
        public
        view
        returns (BorrowMarket[] memory borrowMarket)
    {
        address[] memory _underlyings = router.getUnderlyings();
        borrowMarket = new BorrowMarket[](_underlyings.length);
        IPriceOracle priceOracle = router.priceOracle();
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            (
                uint256[] memory borrows,
                uint256 totalBorrowedAmount,
                uint256 totalLending,

            ) = router.getBorrowStatus(_underlyings[i]);

            borrowMarket[i].underlying = _underlyings[i];
            borrowMarket[i].borrowAmount = totalBorrowedAmount;
            borrowMarket[i].borrowValue = priceOracle.valueOfAsset(
                _underlyings[i],
                _quote,
                totalBorrowedAmount
            );
            borrowMarket[i].matchAmount = totalLending;
            borrowMarket[i].borrows = borrows;
        }
    }
}
