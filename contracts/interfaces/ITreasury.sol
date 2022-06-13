// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface ITreasury{
    function withdraw(address _underlying, uint _amount) external;
}