// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./IProtocol.sol";
import "./IStrategy.sol";
import "./IWETH.sol";

import "../libraries/internals/Types.sol";

interface IProtocolsHandler {
    event Supplied(address indexed asset, uint256 amount);
    event Redeemed(address indexed asset, uint256 amount);
    event Borrowed(address indexed asset, uint256 amount);
    event Repaid(address indexed asset, uint256 amount);
    event AutoRebalanceToggled(bool);
    event Rebalanced(
        IProtocol[] protocols,
        uint256[] redeemAmounts,
        uint256[] supplyAmounts
    );

    function rebalanceAllProtocols(address _asset) external;

    function repayAndSupply(
        address _asset,
        uint256 _amount
    ) external returns (uint256 repayed, uint256 supplied);

    function redeemAndBorrow(
        address _asset,
        uint256 _amount,
        uint256 _totalSupplied,
        address _to
    ) external returns (uint256 redeemAmount, uint256 borrowAmount);

    function totalSupplied(
        address asset
    ) external view returns (uint256[] memory amounts, uint256 totalAmount);

    function totalBorrowed(
        address asset
    ) external view returns (uint256[] memory amounts, uint256 totalAmount);

    function getRates(
        address _underlying
    ) external view returns (uint256, uint256);

    function simulateLendings(
        address _asset,
        uint256 _totalLending
    ) external view returns (uint256 totalLending, uint256 newInterest);

    function updateSimulates(address _asset, uint256 _totalLending) external;

    function addProtocol(IProtocol _protocol) external;

    function updateProtocol(IProtocol _old, IProtocol _new) external;

    function getProtocols() external view returns (IProtocol[] memory);

    function toggleAutoRebalance() external;

    function distributeRewards(
        address _rewardToken,
        address _account,
        uint256 _amount
    ) external;
}
