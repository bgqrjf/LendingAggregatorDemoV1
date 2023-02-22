// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0;

library Utils {
    uint256 constant MILLION = 1000000; // 10 ** 6
    uint256 constant BILLION = 1000000000; // 10 ** 9
    uint256 constant TRILLION = 1000000000000; // 10 ** 12
    uint256 constant QUADRILLION = 1000000000000000; // 10 ** 15
    uint256 constant QUINTILLION = 1000000000000000000; // 10 ** 18
    uint256 constant NONILLION = 1000000000000000000000; // 10 ** 21
    uint256 constant UNDECILLION = 1000000000000000000000000000000000000; // 10 ** 36

    uint8 constant MAC_UINT8 = 0xff;
    uint16 constant MAX_UINT16 = 0xffff;
    uint32 constant MAX_UINT32 = 0xffffffff;
    uint64 constant MAX_UINT64 = 0xffffffffffffffff;
    uint128 constant MAX_UINT128 = 0xffffffffffffffffffffffffffffffff;
    uint256 constant MAX_UINT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    function minOf(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function maxOf(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function sumOf(uint256[] memory a) internal pure returns (uint256 sum) {
        uint256 i;
        while (i < a.length) {
            sum = sum + a[i];
            ++i;
        }
    }

    function lowLevelCall(
        address _contract,
        bytes memory _encodedData,
        uint256 _amount
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = _contract.call{
            value: _amount
        }(_encodedData);
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

    function delegateCall(address _contract, bytes memory _encodedData)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returnData) = _contract.delegatecall(
            _encodedData
        );
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returndataSize := mload(returnData)
                    revert(add(32, returnData), returndataSize)
                }
            } else {
                revert("delegatecall reverted");
            }
        }

        return returnData;
    }
}
