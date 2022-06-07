// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../Types.sol";

interface IProvider{

    // deposit for msg.sender
    function deposit (address _underlying, uint _amount) external;

    function withdraw(address _underlying, uint _amount) external;

    function borrow (address _underlying, uint _amount) external;

    function repay(address _underlying, uint _amount) external;

    // return underlying Token
    function balanceOf(address _underlying, address _acount) external view returns (uint);

    function minSupplyNeeded(address _underlying) external view returns(uint);

    function maxToWithdraw(address _underlying) external view returns(uint);

    function getUsageParams(address _underlying) external view returns (Types.UsageParams memory);
}