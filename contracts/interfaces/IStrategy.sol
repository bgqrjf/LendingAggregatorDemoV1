// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IStrategy{
    function getSupplyStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts);
    function getWithdrawStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts);
    function getBorrowStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts);
    function getRepayStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts);
    function minSupplyNeeded(address _provider, address _underlying) external view returns (uint amount);
    function minRepayNeeded(address _provider, address _underlying) external view returns (uint amount);
    function maxWithdrawAllowed(address _provider, address _underlying) external view returns (uint amount);
    function maxBorrowAllowed(address _provider, address _underlying) external view returns (uint amount);
}