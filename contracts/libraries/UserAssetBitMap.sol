// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library UserAssetBitMap{
    uint public constant MAX_RESERVES_COUNT = 128;

    function isUsingAsCollateralOrBorrowing(uint _userConfig, uint256 _reserveIndex) internal pure returns (bool) {
        return (_userConfig >> (_reserveIndex << 1)) & 3 != 0;
    }

    function isBorrowing(uint _userConfig, uint _reserveIndex) internal pure returns (bool){
        return (_userConfig >> (_reserveIndex << 1)) & 1 != 0;
    }

    function isUsingAsCollateral(uint _userConfig, uint256 _reserveIndex) internal pure returns (bool){
        return (_userConfig >> ((_reserveIndex << 1) + 1)) & 1 != 0;
    }

}