// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IRateGetter {
    function getSupplyRate(address _underlying) external view returns (uint256);

    function getBorrowRate(address _underlying) external view returns (uint256);

    function getLendingRate(address _underlying)
        external
        view
        returns (uint256 lendingRate);
}
