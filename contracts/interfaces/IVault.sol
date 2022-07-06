// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IVault{
    function withdraw(address _underlying, address _to, uint _amount) external;
}