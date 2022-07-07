// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.0;

import "./Types.sol";
import "./Utils.sol";
import "./Math.sol";

import "../interfaces/IProvider.sol";

library StrategyCalculations{
    uint constant precision = 1;

    function calculateAmountsToSupply(
        Types.StrategyParams memory _params,
        uint _maxRate
    ) internal pure returns (uint[] memory amounts){
        amounts = new uint[](_params.providers.length);
        uint minRate;

        // only 1 provider activated
        if (_params.targetRate0 == 0) {
            amounts[_params.targetIndex] = _params.targetAmount;
            return amounts;
        } else {
            uint amount = getAmountToSupply(_params.providers[_params.targetIndex], _params.targetRate0, _params.usageParams[_params.targetIndex]);
            if (amount >= _params.targetAmount){
                amounts[_params.targetIndex] = _params.targetAmount;
                return amounts;
            }else{
                _maxRate = _params.targetRate0;
            }
        }

        uint totalAmountToSupply;
        while(_maxRate - minRate > precision){
            totalAmountToSupply = 0;
            uint targetRate = (_maxRate + minRate) / 2;
            for (uint i = 0; i < _params.providers.length; i++){
                uint amount = getAmountToSupply(_params.providers[i], targetRate, _params.usageParams[i]);
                amounts[i] = totalAmountToSupply < _params.targetAmount ? Utils.minOf(amount, _params.targetAmount - totalAmountToSupply) : 0;
                totalAmountToSupply += amount;
            }

            if (totalAmountToSupply < _params.targetAmount){
                _maxRate = targetRate;
            }else if (totalAmountToSupply > _params.targetAmount){
                minRate = targetRate;
            }else{
                break;
            }
        }

        if (totalAmountToSupply < _params.targetAmount){
            amounts[0] += _params.targetAmount - totalAmountToSupply;
        }
    }

    function calculateAmountsToWithdraw(
        Types.StrategyParams memory _params,
        uint _minRate, 
        uint[] memory _maxToWithdraw
    ) internal pure returns (uint[] memory amounts){
        amounts = new uint[](_params.providers.length);
        uint maxRate;

        // only 1 provider activated
        if (_params.targetRate0 == 0) {
            amounts[_params.targetIndex] = _params.targetAmount;
            return amounts;
        } else {
            uint amount = Utils.minOf(getAmountToWithdraw(_params.providers[_params.targetIndex], _params.targetRate0, _params.usageParams[_params.targetIndex]), _maxToWithdraw[_params.targetIndex]);
            if (amount >= _params.targetAmount){
                amounts[_params.targetIndex] = _params.targetAmount;
                return amounts;
            }else{
                _minRate = _params.targetRate0;
            }
        }

        uint totalAmountToWithdraw;
        while(maxRate > _minRate + precision || maxRate == 0){
            totalAmountToWithdraw = 0;
            uint targetRate = maxRate == 0 ? _minRate + _minRate + 1 : (maxRate + _minRate) / 2;

            for (uint i = 0; i < _params.providers.length; i++){
                uint amount = Utils.minOf(getAmountToWithdraw(_params.providers[i], targetRate, _params.usageParams[i]), _maxToWithdraw[i]);
                amounts[i] = totalAmountToWithdraw < _params.targetAmount ? Utils.minOf(amount, _params.targetAmount - totalAmountToWithdraw) : 0;
                totalAmountToWithdraw += amount;
            }

            if (totalAmountToWithdraw < _params.targetAmount){
                _minRate = targetRate;
            }else if (totalAmountToWithdraw > _params.targetAmount){
                maxRate = targetRate;
            }else{
                break;
            }
        }

        if (totalAmountToWithdraw < _params.targetAmount){
            uint amountLeft = _params.targetAmount - totalAmountToWithdraw;
            for (uint i = 0; i < amounts.length && amountLeft > 0; i++){
                if (amounts[i] < _maxToWithdraw[i]){
                    uint amountDelta = Utils.minOf(amountLeft,  _maxToWithdraw[i] - amounts[i]);
                    amounts[i] += amountDelta;
                    amountLeft -= amountDelta;
                }
            }
        }
    }

    function calculateAmountsToBorrow(
        Types.StrategyParams memory _params,
        uint _minRate, 
        uint[] memory _maxToBorrow
    ) internal pure returns (uint[] memory amounts){
        amounts = new uint[](_params.providers.length);
        uint maxRate;

        // only 1 provider activated
        if (_params.targetRate0 == 0) {
            amounts[_params.targetIndex] = _params.targetAmount;
            return amounts;
        } else {
            uint amount = Utils.minOf(getAmountToBorrow(_params.providers[_params.targetIndex], _params.targetRate0, _params.usageParams[_params.targetIndex]), _maxToBorrow[_params.targetIndex]);
            if (amount >= _params.targetAmount){
                amounts[_params.targetIndex] = _params.targetAmount;
                return amounts;
            }else{
                _minRate = _params.targetRate0;
            }
        }

        uint totalAmountToBorrow;
        while(maxRate > _minRate + precision || maxRate == 0){
            totalAmountToBorrow = 0;
            uint targetRate = maxRate == 0 ? _minRate + _minRate + 1: (maxRate + _minRate) / 2;

            for (uint i = 0; i < _params.providers.length; i++){
                uint amount = Utils.minOf(getAmountToBorrow(_params.providers[i], targetRate, _params.usageParams[i]), _maxToBorrow[i]);
                amounts[i] = totalAmountToBorrow < _params.targetAmount ? Utils.minOf(amount, _params.targetAmount - totalAmountToBorrow) : 0;
                totalAmountToBorrow += amount;
            }

            if (totalAmountToBorrow < _params.targetAmount){
                _minRate = targetRate;
            }else if (totalAmountToBorrow > _params.targetAmount){
                maxRate = targetRate;
            }else{
                break;
            }
        }

        if (totalAmountToBorrow < _params.targetAmount){
            uint amountLeft = _params.targetAmount - totalAmountToBorrow;
            for (uint i = 0; i < amounts.length && amountLeft > 0; i++){
                if (amounts[i] < _maxToBorrow[i]){
                    uint amountDelta = Utils.minOf(amountLeft,  _maxToBorrow[i] - amounts[i]);
                    amounts[i] += amountDelta;
                    amountLeft -= amountDelta;
                }
            }
        }
    }

    function calculateAmountsToRepay(
        Types.StrategyParams memory _params,
        uint _maxRate, 
        uint[] memory _maxAmountToRepay
    ) internal pure returns (uint[] memory amounts){
        amounts = new uint[](_params.providers.length);
        uint minRate;
        uint totalAmountToRepay;

        // only 1 provider activated
        if (_params.targetRate0 == 0) {
            amounts[_params.targetIndex] = _params.targetAmount;
            return amounts;
        } else {
            uint amount = Utils.minOf(_maxAmountToRepay[_params.targetIndex], getAmountToRepay(_params.providers[_params.targetIndex], _params.targetRate0, _params.usageParams[_params.targetIndex]));
            if (amount >= _params.targetAmount){
                amounts[_params.targetIndex] = _params.targetAmount;
                return amounts;
            }else{
                _maxRate = _params.targetRate0;
            }
        }

        while(_maxRate - minRate > precision){
            totalAmountToRepay = 0;
            uint targetRate = (_maxRate + minRate) / 2;
            for (uint i = 0; i < _params.providers.length; i++){
                uint amount = Utils.minOf(_maxAmountToRepay[i], getAmountToRepay(_params.providers[i], targetRate, _params.usageParams[i]));
                amounts[i] = totalAmountToRepay < _params.targetAmount ? Utils.minOf(amount, _params.targetAmount - totalAmountToRepay) : 0;
                totalAmountToRepay += amount;
            }

            if (totalAmountToRepay < _params.targetAmount){
                _maxRate = targetRate;
            }else if (totalAmountToRepay > _params.targetAmount){
                minRate = targetRate;
            }else{
                break;
            }
        }

        if (totalAmountToRepay < _params.targetAmount){
            uint amountLeft = _params.targetAmount - totalAmountToRepay;
            for (uint i = 0; i < amounts.length && amountLeft > 0; i++){
                if (amounts[i] < _maxAmountToRepay[i]){
                    uint amountDelta = Utils.minOf(amountLeft,  _maxAmountToRepay[i] - amounts[i]);
                    amounts[i] += amountDelta;
                    amountLeft -= amountDelta;
                }
            }
        }
    }

    function getAmountToSupply(address _provider, uint _targetRate, bytes memory _usageParams) internal pure returns (uint){
        int amount = IProvider(_provider).supplyToTargetSupplyRate(_targetRate, _usageParams);
        return amount > 0 ? uint(amount) : 0;
    }
    
    function getAmountToWithdraw(address _provider, uint _targetRate, bytes memory _usageParams) internal pure returns (uint){
        int amount = IProvider(_provider).supplyToTargetSupplyRate(_targetRate, _usageParams);
        return amount < 0 ? uint(-amount) : 0;
    }

    function getAmountToBorrow(address _provider, uint _targetRate, bytes memory _usageParams) internal pure returns (uint){
        int amount = IProvider(_provider).borrowToTargetBorrowRate(_targetRate, _usageParams);
        return amount > 0 ? uint(amount) : 0;
    }

    function getAmountToRepay(address _provider, uint _targetRate, bytes memory _usageParams) internal pure returns (uint){
        int amount = IProvider(_provider).borrowToTargetBorrowRate(_targetRate, _usageParams);
        return amount < 0 ? uint(-amount) : 0;
    }
}