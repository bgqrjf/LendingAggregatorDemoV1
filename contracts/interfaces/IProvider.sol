// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IProvider{
    function setInitialized(address _underlying) external;
    function getAddAssetData(address _underlying) external view returns(Types.ProviderData memory data);

    function getSupplyData(address _underlying, uint _amount) external view returns(Types.ProviderData memory data);
    function getWithdrawData(address _underlying, uint _amount) external view returns(Types.ProviderData memory data);
    function getWithdrawAllData(address _underlying) external view returns(Types.ProviderData memory data);
    function getBorrowData(address _underlying, uint _amount) external view returns(Types.ProviderData memory data);
    function getRepayData(address _underlying, uint _amount) external view returns(Types.ProviderData memory data);
    function getClaimRewardData(address _rewardToken) external view returns(Types.ProviderData memory data);
    function getAmountToClaim(address _underlying, Types.UserShare memory _share, bytes memory _params) external view returns (bytes memory, uint amount);

    function getCurrentSupplyRate(address _underlying) external view returns (uint);
    function getCurrentBorrowRate(address _underlying) external view returns (uint);
    function getUsageParams(address _underlying) external view returns(bytes memory);
    function getRewardSupplyData(address _underlying, Types.UserShare memory _share, bytes memory _params) external view returns (bytes memory);
    function getRewardBorrowData(address _underlying, Types.UserShare memory _share, bytes memory _params) external view returns (bytes memory);

    function supplyOf(address _underlying, address _account) external view returns (uint);
    function debtOf(address _underlying, address _account) external view returns (uint);
    function totalColletralAndBorrow(address _account, address _quote) external view returns(uint totalCollateral, uint totalBorrowed);
    function supplyToTargetSupplyRate(uint _targetRate, bytes memory _params) external pure returns (int);
    function borrowToTargetBorrowRate(uint _targetRate, bytes memory _params) external pure returns (int);
}