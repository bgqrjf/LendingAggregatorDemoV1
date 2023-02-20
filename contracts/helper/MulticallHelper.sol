// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "../libraries/internals/Utils.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPriceOracle.sol";

contract MulticallHelper {
    function multicall(address[] memory _targets, bytes[] memory data)
        public
        view
        returns (bytes[] memory results)
    {
        results = new bytes[](_targets.length);
        for (uint256 i = 0; i < _targets.length; i++) {
            results[i] = Utils.lowLevelStaticCall(_targets[i], data[i]);
        }
    }

    function getTotalDepositedAndBorrowed(IRouter router, IPriceOracle oracle)
        public
        view
        returns (uint256, uint256)
    {
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 supplyedAmount;
        uint256 borrowedAmount;
        uint256 tokenPrice;
        address[] memory _underlyings = IRouter(router).getUnderlyings();
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            supplyedAmount = IRouter(router).totalSupplied(_underlyings[i]);
            borrowedAmount = IRouter(router).totalBorrowed(_underlyings[i]);
            tokenPrice = IPriceOracle(oracle).getAssetPrice(_underlyings[i]);
            totalDeposited += (_supplyedAmount * _tokenPrice) / 1e18;
            totalBorrowed += (borrowedAmount * _tokenPrice) / 1e18;
        }
        return (totalDeposited, totalBorrowed);
    }
}
