// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/internals/Types.sol";

interface IProtocol {
    event SupplyShareUpdated(address indexed, address indexed, uint256, bytes);

    event BorrowShareUpdated(address indexed, address indexed, uint256, bytes);

    function updateSupplyShare(address _underlying, uint256 _amount) external;

    function updateBorrowShare(address _underlying, uint256 _amount) external;

    function getAddAssetData(address _underlying)
        external
        view
        returns (Types.ProtocolData memory data);

    function getSupplyData(address _underlying, uint256 _amount)
        external
        view
        returns (Types.ProtocolData memory data);

    function getRedeemData(address _underlying, uint256 _amount)
        external
        view
        returns (Types.ProtocolData memory data);

    function getBorrowData(address _underlying, uint256 _amount)
        external
        view
        returns (Types.ProtocolData memory data);

    function getRepayData(address _underlying, uint256 _amount)
        external
        view
        returns (Types.ProtocolData memory data);

    function getCurrentSupplyRate(address _underlying)
        external
        view
        returns (uint256);

    function getCurrentBorrowRate(address _underlying)
        external
        view
        returns (uint256);

    function totalRewards(
        address _underlying,
        address _account,
        bool _isSupply
    ) external view returns (uint256 rewards);

    function claimRewards(address _account) external;

    function getUsageParams(address _underlying, uint256 _suppliesToRedeem)
        external
        view
        returns (bytes memory);

    function supplyOf(address _underlying, address _account)
        external
        view
        returns (uint256);

    function debtOf(address _underlying, address _account)
        external
        view
        returns (uint256);

    function totalColletralAndBorrow(address _account, address _quote)
        external
        view
        returns (uint256 totalCollateral, uint256 totalBorrowed);

    function supplyToTargetSupplyRate(uint256 _targetRate, bytes memory _params)
        external
        pure
        returns (int256);

    function borrowToTargetBorrowRate(uint256 _targetRate, bytes memory _params)
        external
        pure
        returns (int256);

    function lastSupplyInterest(address _underlying, address _account)
        external
        view
        returns (uint256);

    function lastBorrowInterest(address _underlying, address _account)
        external
        view
        returns (uint256);

    function rewardToken() external view returns (address);
}
