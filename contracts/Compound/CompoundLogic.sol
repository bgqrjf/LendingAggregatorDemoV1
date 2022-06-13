// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProvider.sol";

contract CompoundLogic is IProvider{
    // call by delegates public functions
    function supply (address _underlying, uint _amount) external override{

    }

    function withdraw(address _underlying, uint _amount) external override{

    }

    function withdrawAll(address _underlying) external override{

    }

    function borrow (address _underlying, uint _amount) external override{

    }

    function repay(address _underlying, uint _amount) external override{

    } 


    // return underlying Token
    // return data for caller
    function supplyOf(address _underlying) external view override returns (uint) {

    }

    function debtOf(address _underlying) external view override returns (uint) {

    }

    function getUsageParams(address _underlying) external view override returns (Types.UsageParams memory){

    }

}