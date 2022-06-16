// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.14;

import "./CTokenInterface.sol";
import "./IOracle.sol";

interface ComptrollerLensInterface {
    function markets(address) external view returns(bool, uint, bool);
    function accountAssets(address) external view returns(CTokenInterface[] memory);
    function oracle() external view returns (IOracle);
}