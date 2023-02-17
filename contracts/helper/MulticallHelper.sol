// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

// NOTE: Deploy this contract first
contract MulticallHelper{
    function multicall(address[] memory _targets, bytes[] memory data) public view returns (bytes[] memory results){
        results = new bytes[](_targets.length);
        for(uint i = 0; i < _targets.length ; i++){
            results[i] = lowLevelStaticCall(_targets[i],data[i]);
        }
    }

    function lowLevelStaticCall(address _contract, bytes memory _encodedData)
        internal
        view
        returns (bytes memory)
    {
        (bool success, bytes memory returnData) = _contract.staticcall(
            _encodedData
        );
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returndataSize := mload(returnData)
                    revert(add(32, returnData), returndataSize)
                }
            } else {
                revert("call reverted");
            }
        }

        return returnData;
    }

}