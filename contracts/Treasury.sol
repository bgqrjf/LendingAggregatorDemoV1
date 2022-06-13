// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/ITreasury.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/TransferHelper.sol";

contract Treasury is ITreasury, Ownable{

    function withdraw(address _underlying, uint _amount) external override onlyOwner{
        TransferHelper.transferERC20(_underlying, owner(), _amount);
    }
}