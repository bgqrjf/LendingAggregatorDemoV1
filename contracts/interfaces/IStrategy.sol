// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IProtocol.sol";

import "../libraries/Types.sol";

interface IStrategy{
    function getSupplyStrategy(IProtocol[] memory _protocols, address _asset, uint[] memory _currentSupplies, uint _amount) external view returns (uint[] memory supplyAmounts, uint[] memory redeemAmounts);
    // function getRedeemStrategy(IProtocol[] memory _protocols, Types.UserAssetParams memory _params) external view returns (uint[] memory amounts);
    function getBorrowStrategy(IProtocol[] memory _providers, Types.UserAssetParams memory _params) external view returns (uint[] memory amounts);
    function getRepayStrategy(IProtocol[] memory _providers, Types.UserAssetParams memory _params) external view returns (uint[] memory amounts);
    // function rebalanceSupplies(IProtocol[] memory _protocols, address _underlying) external view returns (uint[] memory currentSupplies, uint[] memory newSupplies);
    function minSupplyNeeded(IProtocol _provider, address _underlying, address _account) external view returns (uint amount);
    function minRepayNeeded(IProtocol _provider, address _underlying, address _account) external view returns (uint amount);
    function maxRedeemAllowed(IProtocol _provider, address _underlying, address _account) external view returns (uint amount);
    function maxBorrowAllowed(IProtocol _provider, address _underlying, address _account) external view returns (uint amount);

    function getSimulateSupplyStrategy(IProtocol[] memory _protocols, address _asset, uint _amount) external view returns (uint[] memory amounts);
    function getSimulateBorrowStrategy(IProtocol[] memory _protocols, address _asset, uint _amount) external view returns (uint[] memory amounts);
}