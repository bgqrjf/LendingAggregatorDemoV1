// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/UserAssetBitMap.sol";

contract MockLibraryTest{
    function isUsingAsCollateralOrBorrowing(uint _userConfig, uint256 _reserveIndex) public pure returns (bool) {
        return UserAssetBitMap.isUsingAsCollateralOrBorrowing(_userConfig, _reserveIndex);
    }

    function isBorrowing(uint _userConfig, uint _reserveIndex) public pure returns (bool){
        return UserAssetBitMap.isBorrowing(_userConfig, _reserveIndex);
    }

    function isUsingAsCollateral(uint _userConfig, uint256 _reserveIndex) public pure returns (bool){
        return UserAssetBitMap.isUsingAsCollateral(_userConfig, _reserveIndex);
    }
}