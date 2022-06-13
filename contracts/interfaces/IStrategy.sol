// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IStrategy{
    function getSupplyStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts);
    function getWithdrawStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts);
    function getBorrowStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts);
    function getRepayStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts);
    function minSupplyNeeded(Types.UsageParams memory _params) external view returns (uint amount);
    function minRepayNeeded(Types.UsageParams memory _params) external view returns (uint amount);
    function maxWithdrawAllowed(Types.UsageParams memory _params) external view returns (uint amount);
    function maxBorrowAllowed(Types.UsageParams memory _params) external view returns (uint amount);
}