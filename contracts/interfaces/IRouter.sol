// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IConfig.sol";
import "./IFactory.sol";
import "./IPriceOracle.sol";
import "./IProtocolsHandler.sol";
import "./IRewards.sol";
import "./IStrategy.sol";

import "../libraries/Types.sol";

interface IRouter {
    function supply(Types.UserAssetParams memory, bool) external payable;

    function redeem(Types.UserAssetParams memory, bool) external;

    function borrow(Types.UserAssetParams memory) external;

    function repay(Types.UserAssetParams memory) external payable;

    function liquidate(
        Types.UserAssetParams memory,
        Types.UserAssetParams memory
    ) external payable;

    function userStatus(address, address)
        external
        view
        returns (uint256, uint256);

    function protocols() external view returns (IProtocolsHandler);

    // --- admin functions
    function addAsset(Types.NewAssetParams memory _newAsset)
        external
        returns (Types.Asset memory asset);

    function updateConfig(IConfig _config) external;

    function updateFactory(IFactory _factory) external;

    function updateProtocolsHandler(IProtocolsHandler _protocolsHandler)
        external;

    function updatePriceOracle(IPriceOracle _priceOracle) external;

    function updateStrategy(IStrategy _strategy) external;
}
