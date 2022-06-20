// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/ITreasury.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/TransferHelper.sol";

contract Treasury is ITreasury, Ownable{

    constructor(address _owner){
        _transferOwnership(_owner);
    }

    receive() external payable{}

    function withdraw(address _underlying, uint _amount) external override onlyOwner{
        TransferHelper.transfer(_underlying, owner(), _amount);
    }
}