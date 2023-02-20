// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "../libraries/internals/Utils.sol";

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
}
