// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.6.0;

library Utils{
    uint constant million       = 1000000;                  // 10 ** 6
    uint constant billion       = 1000000000;               // 10 ** 9
    uint constant trillion      = 1000000000000;            // 10 ** 12
    uint constant Quadrillion   = 1000000000000000;         // 10 ** 15
    uint constant Quintillion   = 1000000000000000000;      // 10 ** 18
    uint constant Nonillion     = 1000000000000000000000;   // 10 ** 21

    function minOf(uint a, uint b) internal pure returns (uint){
        return a < b ? a : b;
    }

    function maxOf(uint a, uint b) internal pure returns (uint){
        return a > b ? a : b;
    }

    function delegateCall(address _contract, bytes memory _encodedData) internal{
        (bool success, bytes memory returnData) = _contract.delegatecall(_encodedData);
        if (!success){
            if (returnData.length > 0){
                assembly{
                    let returndataSize := mload(returnData)
                    revert(add(32, returnData), returndataSize)
                }
            }else{
                revert("call reverted");
            }
        }
    }
}