// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IProtocol{
    function setInitialized(address _underlying) external;
    function updateSupplyShare(address _underlying, uint _amount) external;
    function updateBorrowShare(address _underlying, uint _amount) external;

    function getAddAssetData(address _underlying) external view returns(Types.ProtocolData memory data);
    function getSupplyData(address _underlying, uint _amount) external view returns(Types.ProtocolData memory data);
    function getRedeemData(address _underlying, uint _amount) external view returns(Types.ProtocolData memory data);
    function getRedeemAllData(address _underlying) external view returns(Types.ProtocolData memory data);
    function getBorrowData(address _underlying, uint _amount) external view returns(Types.ProtocolData memory data);
    function getRepayData(address _underlying, uint _amount) external view returns(Types.ProtocolData memory data);
    function getClaimRewardData(address _rewardToken) external view returns(Types.ProtocolData memory data);
    function getClaimUserRewardData(address _underlying, Types.UserShare memory _share, bytes memory _user, bytes memory _router) external view returns (bytes memory, bytes memory, address, uint);

    function getCurrentSupplyRate(address _underlying) external view returns (uint);
    function getCurrentBorrowRate(address _underlying) external view returns (uint);
    function getUsageParams(address _underlying, uint _suppliesToRedeem) external view returns(bytes memory);
    function getRewardSupplyData(address _underlying, Types.UserShare memory _share, bytes memory _user, bytes memory _router) external view returns (bytes memory, bytes memory);
    function getRouterRewardSupplyData(address _underlying, uint totalShare, bytes memory _router) external view returns(bytes memory);
    function getRewardBorrowData(address _underlying, Types.UserShare memory _share, bytes memory _user, bytes memory _router) external view returns (bytes memory, bytes memory);

    function supplyOf(address _underlying, address _account) external view returns (uint);
    function debtOf(address _underlying, address _account) external view returns (uint);
    function totalColletralAndBorrow(address _account, address _quote) external view returns(uint totalCollateral, uint totalBorrowed);
    function supplyToTargetSupplyRate(uint _targetRate, bytes memory _params) external pure returns (int);
    function borrowToTargetBorrowRate(uint _targetRate, bytes memory _params) external pure returns (int);

    function lastSupplyInterest(address _underlying) external view returns (uint);
    function lastBorrowInterest(address _underlying) external view returns (uint);
}