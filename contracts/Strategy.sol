// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./Types.sol";

contract Strategy{

    function calculateAmountsToSupply(uint _targetAmount, uint _maxApy, Types.UsageParams[] memory _params) external pure returns (uint[] memory amounts){
        uint providerCount = _params.length;
        amounts = new uint[](providerCount);
        uint minApy;
        while(_maxApy - minApy > 1){
            uint delta = _maxApy - minApy;
            uint targetRate = minApy + delta / 2;
            uint totalAmountToSupply;
            for (uint i = 0; i < providerCount; i++){
                amounts[i]= calculateAmountToSupply(targetRate, _params[i]);
                totalAmountToSupply += amounts[i];
            }

            if (totalAmountToSupply < _targetAmount){
                _maxApy = targetRate;
            }else if (totalAmountToSupply > _targetAmount){
                minApy = targetRate;
            }else{
                break;
            }
        }
    }

    function calculateAmountsToWithdraw(uint _targetAmount, uint _maxApy, uint _minApy, Types.UsageParams[] memory _params, uint[] memory _maxToWithdraw) external pure returns (uint[] memory amounts){


    }

    function calculateAmountToSupply(uint _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){

    }

}