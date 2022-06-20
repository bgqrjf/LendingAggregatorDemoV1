// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IProvider{
    function getSupplyData(address _underlying, uint _amount) external view returns(address target, bytes memory encodedData, address payable weth);
    function getWithdrawData(address _underlying, uint _amount) external view returns(address target, bytes memory encodedData, address payable weth);
    function getWithdrawAllData(address _underlying) external view returns(address target, bytes memory encodedData, address payable weth);
    function getBorrowData(address _underlying, uint _amount) external view returns(address target, bytes memory encodedData, address payable weth);
    function getRepayData(address _underlying, uint _amount) external view returns(address target, bytes memory encodedData, address payable weth);

    function supplyOf(address _underlying, address _account) external view returns (uint);
    function debtOf(address _underlying, address _account) external view returns (uint);
    function getUsageParams(address _underlying) external view returns (Types.UsageParams memory);
    function totalColletralAndBorrow(address _account, address _quote) external view returns(uint totalCollateral, uint totalBorrowed);
}