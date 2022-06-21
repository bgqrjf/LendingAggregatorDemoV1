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

    function supplyOf(address _underlying, address _account) external view returns (uint);
    function debtOf(address _underlying, address _account) external view returns (uint);
    function getUsageParams(address _underlying) external view returns (Types.UsageParams memory);
    function totalColletralAndBorrow(address _account, address _quote) external view returns(uint totalCollateral, uint totalBorrowed);
}