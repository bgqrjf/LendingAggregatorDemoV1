// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IProtocol {
    event SupplyShareUpdated(address indexed, uint256, bytes);

    event BorrowShareUpdated(address indexed, uint256, bytes);

    // delegate calls
    function updateSupplyShare(address _underlying, uint256 _amount) external;

    function updateBorrowShare(address _underlying, uint256 _amount) external;

    function supply(address _underlying, uint256 _amount) external;

    function redeem(address _underlying, uint256 _amount) external;

    function borrow(address _underlying, uint256 _amount) external;

    function repay(address _underlying, uint256 _amount) external;

    // static calls
    function getCurrentSupplyRate(
        address _underlying
    ) external view returns (uint256);

    function getCurrentBorrowRate(
        address _underlying
    ) external view returns (uint256);

    function claimRewards(
        address _underlying,
        address _account,
        bool _isSupply
    ) external returns (uint256 newRewards);

    function getUsageParams(
        address _underlying,
        uint256 _suppliesToRedeem
    ) external view returns (bytes memory);

    function supplyOf(
        address _underlying,
        address _account
    ) external view returns (uint256);

    function debtOf(
        address _underlying,
        address _account
    ) external view returns (uint256);

    function totalColletralAndBorrow(
        address _account,
        address _quote
    ) external view returns (uint256 totalCollateral, uint256 totalBorrowed);

    function supplyToTargetSupplyRate(
        uint256 _targetRate,
        bytes memory _params
    ) external pure returns (int256);

    function borrowToTargetBorrowRate(
        uint256 _targetRate,
        bytes memory _params
    ) external pure returns (int256);

    function lastSupplyInterest(
        address _underlying
    ) external view returns (uint256);

    function lastBorrowInterest(
        address _underlying
    ) external view returns (uint256);

    function rewardToken() external view returns (address);
}
