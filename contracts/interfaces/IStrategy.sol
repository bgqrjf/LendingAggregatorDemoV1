// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IProtocol.sol";

interface IStrategy {
    function getSupplyStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view returns (uint256[] memory supplyAmounts);

    function getRedeemStrategy(
        IProtocol[] memory _protocols,
        address _asset,
        uint256 _amount
    ) external view returns (uint256[] memory redeemAmounts);

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

    function getRebalanceStrategy(
        IProtocol[] memory _protocols,
        address _asset
    )
        external
        view
        returns (
            uint256[] memory redeemAmounts,
            uint256[] memory supplyAmounts
        );
}
