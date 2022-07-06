// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/TransferHelper.sol";

contract Vault is IVault, Ownable{

    constructor(address _owner){
        _transferOwnership(_owner);
    }

    receive() external payable{}

    function withdraw(address _underlying, address _to, uint _amount) external override onlyOwner{
        TransferHelper.transfer(_underlying, _to, _amount);
    }
}