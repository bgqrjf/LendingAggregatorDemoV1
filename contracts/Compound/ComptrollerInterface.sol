// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.14;

import "./CTokenInterface.sol";
import "./IOracle.sol";

interface ComptrollerInterface {
    function enterMarkets(address[] memory cTokens) external returns (uint[] memory);

    function markets(address cToken) external view returns(bool, uint, bool);
    function getAssetsIn(address account) external view returns (CTokenInterface[] memory);
    function oracle() external view returns (IOracle);
}