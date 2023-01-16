// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IProtocol.sol";
import "./IStrategy.sol";
import "./IWETH.sol";

import "../libraries/internals/Types.sol";

interface IProtocolsHandler {
    event Supplied(address indexed asset, uint256 amount);
    event Redeemed(address indexed asset, uint256 amount);
    event Borrowed(address indexed asset, uint256 amount);
    event Repayed(address indexed asset, uint256 amount);

    function repayAndSupply(
        address _asset,
        uint256 _amount,
        uint256[] memory supplies,
        uint256 _totalSupplied
    ) external returns (uint256 repayed, uint256 supplied);

    function redeemAndBorrow(
        address _asset,
        uint256 _amount,
        uint256[] memory supplies,
        uint256 _totalSupplied,
        address _to
    ) external returns (uint256 redeemAmount, uint256 borrowAmount);

    function totalSupplied(address asset)
        external
        view
        returns (uint256[] memory amounts, uint256 totalAmount);

    function totalBorrowed(address asset)
        external
        view
        returns (uint256[] memory amounts, uint256 totalAmount);

    function simulateLendings(address _asset, uint256 _totalLending)
        external
        view
        returns (uint256 totalLending, uint256 newInterest);

    function updateSimulates(address _asset, uint256 _totalLending) external;

    function setRouter(address _router) external;

    function claimRewards(address _account, uint256[] memory _amounts) external;

    function addProtocol(IProtocol _protocol) external;

    function getProtocols() external view returns (IProtocol[] memory);
}
