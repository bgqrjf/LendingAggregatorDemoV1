// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProvider.sol";

import "./libraries/Utils.sol";
import "./libraries/Math.sol";

import "./Types.sol";

contract Strategy{
    uint public maxLTV;

    constructor (uint _maxLTV){
        maxLTV = _maxLTV;
    }

    function getSupplyStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        Types.UsageParams[] memory usageParams = new Types.UsageParams[](providerCount);
        uint maxApy = 0;
        uint minSupplyAmount;

        for (uint i = 0; i < providerCount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);
            if (amounts[i] > 0){
                amounts[i] = Utils.minOf(_amount, minSupplyNeeded(usageParams[i]));
                minSupplyAmount += amounts[i];
            }

            if (usageParams[i].rate > maxApy){
                maxApy = usageParams[i].rate;
            }
        }

         if (_amount > minSupplyAmount){
            uint[] memory strategyAmounts = calculateAmountsToSupply(_amount - minSupplyAmount, maxApy, usageParams);

            if (minSupplyAmount > 0){
                for (uint i = 0; i < providerCount; i++){
                    amounts[i] += strategyAmounts[i];
                }
            }
        }
    }

    function getWithdrawStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        Types.UsageParams[] memory usageParams = new Types.UsageParams[](providerCount);
        uint minApy = Utils.MAX_UINT;
        uint maxWithdrawAmount;

        for (uint i = 0; i < providerCount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);
            if (amounts[i] > 0){
                amounts[i] = maxWithdrawAllowed(usageParams[i]);
                maxWithdrawAmount += amounts[i];
            }

            if (usageParams[i].rate < minApy){
                minApy = usageParams[i].rate;
            }
        }

        require(maxWithdrawAmount >= _amount, "Strategy: insufficient balance");

        amounts = calculateAmountsToWithdraw(_amount, minApy, usageParams, amounts);

    }

    function minSupplyNeeded(Types.UsageParams memory _params) public view returns (uint amount){
        if (_params.totalBorrowed * Utils.MILLION / _params.totalSupplied > maxLTV){
            amount = calculateSupplyAmountToReachLTV(_params, maxLTV);
        }
    }

    function maxWithdrawAllowed(Types.UsageParams memory _params) public view returns (uint amount){
        if (_params.totalBorrowed * Utils.MILLION / _params.totalSupplied > maxLTV){
            amount = calculateWithdrawToReachLTV(_params, maxLTV);
        }
    }


    function getBorrowStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts){
        // should not exceed provider alarm LTV
        // select best interest after borrow
    }

    function getRepayStrategy(address[] memory _providers, address _underlying, uint _amount) external view returns (uint[] memory amounts){
        // if excced alarm LTV repay to the pool
        // select best interest after repay
    }

    function calculateAmountsToSupply(uint _targetAmount, uint _maxApy, Types.UsageParams[] memory _params) public pure returns (uint[] memory amounts){
        amounts = new uint[](_params.length);
        uint minApy;
        while(_maxApy - minApy > 1){
            uint targetRate = (_maxApy + minApy) / 2;
            uint totalAmountToSupply;
            for (uint i = 0; i < _params.length; i++){
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

    function calculateAmountsToWithdraw(
        uint _targetAmount, 
        uint _minApy, 
        Types.UsageParams[] memory _params, 
        uint[] memory _maxToWithdraw
    ) public pure returns (uint[] memory amounts){
        amounts = new uint[](_params.length);
        uint maxApy = Utils.MAX_UINT;
        uint totalAmouintToWithdraw;

        while(maxApy - _minApy > 1){
            uint targetRate = maxApy >  2 * _minApy ? 2 * _minApy : (maxApy + _minApy) / 2;

            for (uint i = 0; i < _params.length; i++){
                amounts[i]= Utils.minOf(calculateAmountToWithdraw(targetRate, _params[i]), _maxToWithdraw[i]);
                totalAmouintToWithdraw += amounts[i];
            }

            if (totalAmouintToWithdraw < _targetAmount){
                _minApy = targetRate;
            }else if (totalAmouintToWithdraw > _targetAmount){
                maxApy = targetRate;
            }else{
                break;
            }
        }
        
    }

    function calculateAmountToSupply(uint _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){
        if (_targetRate < _params.rate){
            uint supplyOfTarget = supplyOfTargetRate(_targetRate, _params);
            amount = supplyOfTarget - _params.totalSupplied;
        }
    }

    function calculateAmountToWithdraw(uint _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){
        if (_targetRate > _params.rate){
            uint supplyOfTarget = supplyOfTargetRate(_targetRate, _params);
            amount = _params.totalSupplied - supplyOfTarget;
        }
    }

    function calculateSupplyAmountToReachLTV(Types.UsageParams memory _params, uint _ltv) public pure returns (uint amount){
        uint supplyOfLTV = _params.totalBorrowed / _ltv;
        amount =  supplyOfLTV > _params.totalSupplied ? supplyOfLTV - _params.totalSupplied : 0;
    }

    function calculateWithdrawToReachLTV(Types.UsageParams memory _params, uint _ltv) public pure returns (uint amount){
        uint supplyOfLTV = _params.totalBorrowed / _ltv;
        amount =  supplyOfLTV < _params.totalSupplied ? _params.totalSupplied  - supplyOfLTV : 0;
    }

    function supplyOfTargetRate(uint _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){
        uint a = _params.totalBorrowed * _params.base;
        uint b = _params.totalBorrowed * Math.sqrt(_params.base ** 2 + 4 * _params.slope1 * _targetRate);
        amount = (a + b) / (2 * _targetRate);

        uint targetLTV = _params.totalBorrowed * Utils.MILLION / amount;
        if (targetLTV > _params.optimalLTV){
            uint base = _params.slope1 * _params.optimalLTV / Utils.MILLION + _params.base; 
            uint kbp =  _params.slope2 * _params.totalBorrowed * _params.optimalLTV / Utils.MILLION; 
            a = _params.totalBorrowed * base; 
            b = Math.sqrt((kbp - _params.totalBorrowed * base) ** 2 + 4 * _params.slope2 * (_params.totalBorrowed ** 2) * _targetRate);
            amount = (a + b - kbp) / (2 * _targetRate);
        }
    }

}