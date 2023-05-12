// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./RatesHelper.sol";
import "../libraries/internals/Types.sol";

contract QueryHelper is RatesHelper {
    constructor(address _router) RatesHelper(_router) {}

    function simulateRebalance(
        address _underlying
    ) external returns (uint256 rate, uint256[] memory protocolsRates) {
        router.protocols().rebalanceAllProtocols(_underlying);
        return getCurrentSupplyRates(_underlying);
    }
}
