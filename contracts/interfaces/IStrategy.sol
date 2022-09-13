// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IProtocol.sol";

import "../libraries/Types.sol";

interface IStrategy {
    function getSupplyStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256[] memory _currentSupplies,
        uint256 _amount
    )
        external
        view
        returns (
            uint256[] memory supplyAmounts,
            uint256[] memory redeemAmounts
        );

    // function getRedeemStrategy(IProtocol[] memory _protocols, Types.UserAssetParams memory _params) external view returns (uint[] memory amounts);
    function getBorrowStrategy(
        IProtocol[] memory _providers,
        Types.UserAssetParams memory _params
    ) external view returns (uint256[] memory amounts);

    function getRepayStrategy(
        IProtocol[] memory _providers,
        Types.UserAssetParams memory _params
    ) external view returns (uint256[] memory amounts);

    // function rebalanceSupplies(IProtocol[] memory _protocols, address _underlying) external view returns (uint[] memory currentSupplies, uint[] memory newSupplies);
    function minSupplyNeeded(
        IProtocol _provider,
        address _underlying,
        address _account
    ) external view returns (uint256 amount);

    function minRepayNeeded(
        IProtocol _provider,
        address _underlying,
        address _account
    ) external view returns (uint256 amount);

    function maxRedeemAllowed(
        IProtocol _provider,
        address _underlying,
        address _account
    ) external view returns (uint256 amount);

    function maxBorrowAllowed(
        IProtocol _provider,
        address _underlying,
        address _account
    ) external view returns (uint256 amount);

    function getSimulateSupplyStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view returns (uint256[] memory amounts);

    function getSimulateBorrowStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view returns (uint256[] memory amounts);
}
