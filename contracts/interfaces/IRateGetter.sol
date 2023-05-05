// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IRateGetter {
    function getCurrentSupplyRate(address _underlying)
        external
        view
        returns (uint256);

    function getCurrentBorrowRate(address _underlying)
        external
        view
        returns (uint256);

    function getLendingRate(address _underlying)
        external
        view
        returns (uint256 lendingRate);
}
