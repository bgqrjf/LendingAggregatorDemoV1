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

    function getBorrowStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view returns (uint256[] memory amounts);

    function getRepayStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view returns (uint256[] memory amounts);

    function minSupply(
        IProtocol _protocol,
        address _underlying,
        address _account
    ) external view returns (uint256 amount);

    function minRepay(
        IProtocol _protocol,
        address _underlying,
        address _account
    ) external view returns (uint256 amount);

    function maxRedeemAllowed(
        IProtocol _protocol,
        address _underlying,
        address _account
    ) external view returns (uint256 amount);

    function maxBorrowAllowed(
        IProtocol _protocol,
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
