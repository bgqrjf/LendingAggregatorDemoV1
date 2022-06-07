// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.0;

library math{
    function divCeil(uint x, uint y) internal pure returns (uint){
        return (x + y - 1) / y;
    }

}