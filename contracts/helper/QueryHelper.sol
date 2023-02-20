// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./MulticallHelper.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ISToken.sol";
import "../interfaces/IDToken.sol";

contract QueryHelper is MulticallHelper {
    function getSTokenConvertRate(ISToken sToken, IPriceOracle oracle)
        public
        view
        returns (uint256, uint256)
    {
        address underlying = sToken.underlying();
        uint256 rate = sToken.totalSupply() > 0
            ? sToken.scaledTotalSupply() / sToken.totalSupply()
            : 0;
        uint256 tokenPrice = IPriceOracle(oracle).getAssetPrice(underlying);
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
        uint256 tokenPrice = IPriceOracle(oracle).getAssetPrice(underlying);
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
        address[] memory _underlyings = IRouter(router).getUnderlyings();
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            supplyedAmount = IRouter(router).totalSupplied(_underlyings[i]);
            borrowedAmount = IRouter(router).totalBorrowed(_underlyings[i]);
            (, , matchAmount, , ) = IRouter(router).getSupplyStatus(
                _underlyings[i]
            );
            tokenPrice = IPriceOracle(oracle).getAssetPrice(_underlyings[i]);
            totalDeposited += (supplyedAmount * tokenPrice) / 1e8;
            totalBorrowed += (borrowedAmount * tokenPrice) / 1e8;
            totalMatchAmount += (matchAmount * tokenPrice) / 1e8;
        }
        return (totalDeposited, totalBorrowed, totalMatchAmount);
    }
}
