// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.0;

import "./Types.sol";
import "./Utils.sol";
import "./Math.sol";

library LoanCalculation{
    function calculateSupplyAmountToReachLTV(Types.UsageParams memory _params, uint _ltv) public pure returns (uint amount){
        uint supplyOfLTV = _params.totalBorrowed / _ltv;
        amount = supplyOfLTV - _params.totalSupplied;
    }

    function calculateWithdrawToReachLTV(Types.UsageParams memory _params, uint _ltv) public pure returns (uint amount){
        uint supplyOfLTV = _params.totalBorrowed / _ltv;
        amount = _params.totalSupplied  - supplyOfLTV;
    }

    function calculateBorrowToReachLTV(Types.UsageParams memory _params, uint _ltv) public pure returns (uint amount){
        uint loanOfLTV = _params.totalSupplied * _ltv;
        amount = loanOfLTV - _params.totalBorrowed;
    }

    function calculateRepayAmountToReachLTV(Types.UsageParams memory _params, uint _ltv) public pure returns (uint amount){
        uint loanOfLTV = _params.totalSupplied * _ltv;
        amount = _params.totalBorrowed - loanOfLTV;
    }

    function calculateAmountsToSupply(uint _targetAmount, uint32 _maxRate, Types.UsageParams[] memory _params) public pure returns (uint[] memory amounts){
        amounts = new uint[](_params.length);
        uint32 minRate;
        while(_maxRate - minRate > 1){
            uint32 targetRate = (_maxRate + minRate) / 2;
            uint totalAmountToSupply;
            for (uint i = 0; i < _params.length; i++){
                amounts[i]= calculateAmountToSupply(targetRate, _params[i]);
                totalAmountToSupply += amounts[i];
            }

            if (totalAmountToSupply < _targetAmount){
                _maxRate = targetRate;
            }else if (totalAmountToSupply > _targetAmount){
                minRate = targetRate;
            }else{
                break;
            }
        }
    }

    function calculateAmountsToWithdraw(
        uint _targetAmount, 
        uint32 _minRate, 
        Types.UsageParams[] memory _params, 
        uint[] memory _maxToWithdraw
    ) public pure returns (uint[] memory amounts){
        amounts = new uint[](_params.length);
        uint32 maxRate;
        uint totalAmountToWithdraw;

        while(maxRate - _minRate > 1){
            uint32 targetRate = maxRate == 0 ? _minRate + _minRate : (maxRate + _minRate) / 2;

            for (uint i = 0; i < _params.length; i++){
                amounts[i]= Utils.minOf(calculateAmountToWithdraw(targetRate, _params[i]), _maxToWithdraw[i]);
                totalAmountToWithdraw += amounts[i];
            }

            if (totalAmountToWithdraw < _targetAmount){
                _minRate = targetRate;
            }else if (totalAmountToWithdraw > _targetAmount){
                maxRate = targetRate;
            }else{
                break;
            }
        }
        
    }

    function calculateAmountsToBorrow(
        uint _targetAmount, 
        uint32 _minRate, 
        Types.UsageParams[] memory _params, 
        uint[] memory _maxToBorrow
    ) public pure returns (uint[] memory amounts){
        amounts = new uint[](_params.length);
        uint32 maxRate;
        uint totalAmountToBorrow;

        while(maxRate - _minRate > 1){
            uint32 targetRate = maxRate == 0 ? _minRate + _minRate : (maxRate + _minRate) / 2;

            for (uint i = 0; i < _params.length; i++){
                amounts[i]= Utils.minOf(calculateAmountToBorrow(targetRate, _params[i]), _maxToBorrow[i]);
                totalAmountToBorrow += amounts[i];
            }

            if (totalAmountToBorrow < _targetAmount){
                _minRate = targetRate;
            }else if (totalAmountToBorrow > _targetAmount){
                maxRate = targetRate;
            }else{
                break;
            }
        }
        
    }

    function calculateAmountsToRepay(uint _targetAmount, uint32 _maxRate, Types.UsageParams[] memory _params) public pure returns (uint[] memory amounts){
        amounts = new uint[](_params.length);
        uint32 minRate;
        while(_maxRate - minRate > 1){
            uint32 targetRate = (_maxRate + minRate) / 2;
            uint totalAmountToRepay;
            for (uint i = 0; i < _params.length; i++){
                amounts[i]= calculateAmountToRepay(targetRate, _params[i]);
                totalAmountToRepay += amounts[i];
            }

            if (totalAmountToRepay < _targetAmount){
                _maxRate = targetRate;
            }else if (totalAmountToRepay > _targetAmount){
                minRate = targetRate;
            }else{
                break;
            }
        }
    }

    function calculateAmountToSupply(uint32 _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){
        if (_targetRate < _params.rate){
            uint supplyOfTarget = supplyOfTargetRate(_targetRate, _params);
            amount = supplyOfTarget - _params.totalSupplied;
        }
    }

    function calculateAmountToWithdraw(uint32 _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){
        if (_targetRate > _params.rate){
            uint supplyOfTarget = supplyOfTargetRate(_targetRate, _params);
            amount = _params.totalSupplied - supplyOfTarget;
        }
    }

    function calculateAmountToBorrow(uint32 _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){
        if (_targetRate > _params.rate){
            uint loanOfTarget = loanOfTargetRate(_targetRate, _params);
            amount = loanOfTarget - _params.totalBorrowed;
        }
    }

    function calculateAmountToRepay(uint32 _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){
        if (_targetRate < _params.rate){
            uint loanOfTarget = loanOfTargetRate(_targetRate, _params);
            amount = _params.totalBorrowed - loanOfTarget;
        }
    }

    function supplyOfTargetRate(uint32 _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){
        supplyToBorrowRate(_targetRate, _params.reserveFactor);
        uint a = _params.totalBorrowed * _params.base;
        uint b = _params.totalBorrowed * Math.sqrt(_params.base * _params.base + 4 * _params.slope1 * _targetRate);
        amount = (a + b) / (2 * _targetRate);

        uint targetLTV = _params.totalBorrowed * Utils.MILLION / amount;
        if (targetLTV > _params.optimalLTV){
            uint base = _params.slope1 * _params.optimalLTV / Utils.MILLION + _params.base; 
            uint kbp =  _params.slope2 * _params.totalBorrowed * _params.optimalLTV / Utils.MILLION; 
            a = _params.totalBorrowed * base; 
            b = Math.sqrt((kbp - _params.totalBorrowed * base) ** 2 + 4 * _params.slope2 * _params.totalBorrowed * _params.totalBorrowed * _targetRate);
            amount = (a + b - kbp) / (2 * _targetRate);
        }
    }

    function loanOfTargetRate(uint32 _targetRate, Types.UsageParams memory _params) public pure returns (uint amount){
        uint a = _params.totalSupplied * Math.sqrt(_params.base * _params.base + 4 * _params.slope1 * _targetRate);
        uint b = _params.totalSupplied * _params.base;
        amount = (a-b) / (2 * _params.slope1);
        
        uint targetLTV = amount * Utils.MILLION / _params.totalSupplied;
        if (targetLTV > _params.optimalLTV){
            uint base = _params.slope1 * _params.optimalLTV / Utils.MILLION + _params.base; 
            uint ksp =  _params.slope2 * _params.totalSupplied * _params.optimalLTV / Utils.MILLION; 
            a = ksp + _params.totalSupplied * base;
            b = Math.sqrt(a * a + 4 * _params.slope2 * _params.totalSupplied * _params.totalSupplied * _targetRate);
            amount = (a + b ) / (2 * _params.slope1);
        }
    }

    function supplyToBorrowRate(uint32 _supplyRate, uint32 _reserveFactor) public pure returns (uint32 _borrowRate){
        return _supplyRate * uint32(Utils.MILLION) /  _reserveFactor;
    }

    function borrowToSupplyRate(uint32 _borrowRate, uint32 _reserveFactor) public pure returns (uint32 _supplyRate){
        return _borrowRate * _reserveFactor / uint32(Utils.MILLION);
    }
}