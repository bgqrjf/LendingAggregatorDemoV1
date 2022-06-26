// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.14;

import "./CTokenInterface.sol";

interface IOracle {
    function getUnderlyingPrice(CTokenInterface cToken) external view returns (uint);
}


