// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.0;

import "./Types.sol";
import "./Utils.sol";
import "./Math.sol";

import "../interfaces/IProvider.sol";

library StrategyCalculations{
    uint constant precision = 1;

    function calculateAmountsToSupply(
        uint _targetAmount, 
        uint _maxRate, 
        address[] memory _providers,
        bytes[] memory _usageParams
    ) internal pure returns (uint[] memory amounts){
        amounts = new uint[](_providers.length);
        uint minRate;
        uint totalAmountToSupply;
        
        while(_maxRate - minRate > precision){
            totalAmountToSupply = 0;
            uint targetRate = (_maxRate + minRate) / 2;
            for (uint i = 0; i < _providers.length; i++){
                uint amount = getAmountToSupply(_providers[i], targetRate, _usageParams[i]);
                amounts[i] = totalAmountToSupply < _targetAmount ? Utils.minOf(amount, _targetAmount - totalAmountToSupply) : 0;
                totalAmountToSupply += amount;
            }

            if (totalAmountToSupply < _targetAmount){
                _maxRate = targetRate;
            }else if (totalAmountToSupply > _targetAmount){
                minRate = targetRate;
            }else{
                break;
            }
        }

        if (totalAmountToSupply < _targetAmount){
            amounts[0] += _targetAmount - totalAmountToSupply;
        }
    }

    function calculateAmountsToWithdraw(
        uint _targetAmount, 
        uint _minRate, 
        address[] memory _providers, 
        bytes[] memory _usageParams,
        uint[] memory _maxToWithdraw
    ) internal pure returns (uint[] memory amounts){
        amounts = new uint[](_providers.length);
        uint maxRate;
        uint totalAmountToWithdraw;

        while(maxRate > _minRate + precision || maxRate == 0){
            totalAmountToWithdraw = 0;
            uint targetRate = maxRate == 0 ? _minRate + _minRate + 1 : (maxRate + _minRate) / 2;

            for (uint i = 0; i < _providers.length; i++){
                uint amount = Utils.minOf(getAmountToWithdraw(_providers[i], targetRate, _usageParams[i]), _maxToWithdraw[i]);
                amounts[i] = totalAmountToWithdraw < _targetAmount ? Utils.minOf(amount, _targetAmount - totalAmountToWithdraw) : 0;
                totalAmountToWithdraw += amount;
            }

            if (totalAmountToWithdraw < _targetAmount){
                _minRate = targetRate;
            }else if (totalAmountToWithdraw > _targetAmount){
                maxRate = targetRate;
            }else{
                break;
            }
        }

        if (totalAmountToWithdraw < _targetAmount){
            uint amountLeft = _targetAmount - totalAmountToWithdraw;
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
        uint _targetAmount, 
        uint _minRate, 
        address[] memory _providers, 
        bytes[] memory _usageParams,
        uint[] memory _maxToBorrow
    ) internal pure returns (uint[] memory amounts){
        amounts = new uint[](_providers.length);
        uint maxRate;
        uint totalAmountToBorrow;

        while(maxRate > _minRate + precision || maxRate == 0){
            totalAmountToBorrow = 0;
            uint targetRate = maxRate == 0 ? _minRate + _minRate + 1: (maxRate + _minRate) / 2;

            for (uint i = 0; i < _providers.length; i++){
                uint amount = Utils.minOf(getAmountToBorrow(_providers[i], targetRate, _usageParams[i]), _maxToBorrow[i]);
                amounts[i] = totalAmountToBorrow < _targetAmount ? Utils.minOf(amount, _targetAmount - totalAmountToBorrow) : 0;
                totalAmountToBorrow += amount;
            }

            if (totalAmountToBorrow < _targetAmount){
                _minRate = targetRate;
            }else if (totalAmountToBorrow > _targetAmount){
                maxRate = targetRate;
            }else{
                break;
            }
        }

        if (totalAmountToBorrow < _targetAmount){
            amounts[0] += _targetAmount - totalAmountToBorrow;
        }
    }

    function calculateAmountsToRepay(
        uint _targetAmount, 
        uint _maxRate, 
        address[] memory _providers,
        bytes[] memory _usageParams,
        uint[] memory _maxAmountToRepay
    ) internal pure returns (uint[] memory amounts){
        amounts = new uint[](_providers.length);
        uint minRate;
        uint totalAmountToRepay;
        while(_maxRate - minRate > precision){
            totalAmountToRepay = 0;
            uint targetRate = (_maxRate + minRate) / 2;
            for (uint i = 0; i < _providers.length; i++){
                uint amount = Utils.minOf(_maxAmountToRepay[i], getAmountToRepay(_providers[i], targetRate, _usageParams[i]));
                amounts[i] = totalAmountToRepay < _targetAmount ? Utils.minOf(amount, _targetAmount - totalAmountToRepay) : 0;
                totalAmountToRepay += amount;
            }

            if (totalAmountToRepay < _targetAmount){
                _maxRate = targetRate;
            }else if (totalAmountToRepay > _targetAmount){
                minRate = targetRate;
            }else{
                break;
            }
        }

        if (totalAmountToRepay < _targetAmount){
            uint amountLeft = _targetAmount - totalAmountToRepay;
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