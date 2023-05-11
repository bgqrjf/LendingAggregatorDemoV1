// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./RatesHelper.sol";
import "../interfaces/IRouter.sol";
import "../libraries/internals/Types.sol";

contract QueryHelper is RatesHelper {
    IProtocolsHandler public protocolsHandler;

    constructor(
        address _router,
        address _protocolsHandler
    ) RatesHelper(_router) {
        protocolsHandler = IProtocolsHandler(_protocolsHandler);
    }

    function simulateRebalance(
        address _underlying
    ) external returns (uint256 rate, uint256[] memory protocolsRates) {
        protocolsHandler.rebalanceAllProtocols(_underlying);
        rate = getCurrentSupplyRate(_underlying);
        (rate, ) = protocolsHandler.getRates(_underlying);

        IProtocol[] memory protocols = protocolsHandler.getProtocols();
        protocolsRates = new uint256[](protocols.length);
        for (uint i = 0; i < protocols.length; ++i) {
            protocolsRates[i] = protocols[i].getCurrentSupplyRate(_underlying);
        }
    }
}
