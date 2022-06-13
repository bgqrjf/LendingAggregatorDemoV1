// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProvider.sol";
import "./interfaces/IStrategy.sol";

import "./libraries/LoanCalculation.sol";

contract Strategy is IStrategy{
    uint public maxLTV;

    constructor (uint _maxLTV){
        maxLTV = _maxLTV;
    }

    function getSupplyStrategy(address[] memory _providers, address _underlying, uint _amount) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        Types.UsageParams[] memory usageParams = new Types.UsageParams[](providerCount);
        uint32 maxRate;
        uint minSupplyAmount;

        for (uint i = 0; i < providerCount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);
            if (amounts[i] > 0){
                amounts[i] = minSupplyNeeded(usageParams[i]);
                minSupplyAmount += amounts[i];
            }

            if (usageParams[i].rate > maxRate){
                maxRate = usageParams[i].rate;
            }
        }

         if (_amount > minSupplyAmount){
            uint[] memory strategyAmounts = LoanCalculation.calculateAmountsToSupply(_amount - minSupplyAmount, maxRate, usageParams);

            if (minSupplyAmount > 0){
                for (uint i = 0; i < providerCount; i++){
                    amounts[i] += strategyAmounts[i];
                }
            }
        }
    }

    function getWithdrawStrategy(address[] memory _providers, address _underlying, uint _amount) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        Types.UsageParams[] memory usageParams = new Types.UsageParams[](providerCount);
        uint32 minRate = Utils.MAX_UINT32;
        uint maxWithdrawAmount;

        for (uint i = 0; i < providerCount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);
            if (amounts[i] > 0){
                amounts[i] = maxWithdrawAllowed(usageParams[i]);
                maxWithdrawAmount += amounts[i];
            }

            if (usageParams[i].rate < minRate){
                minRate = usageParams[i].rate;
            }
        }

        require(maxWithdrawAmount >= _amount, "Strategy: insufficient balance");

        amounts = LoanCalculation.calculateAmountsToWithdraw(_amount, minRate, usageParams, amounts);
    }

    function getBorrowStrategy(address[] memory _providers, address _underlying, uint _amount) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        Types.UsageParams[] memory usageParams = new Types.UsageParams[](providerCount);
        uint32 minRate = Utils.MAX_UINT32;
        uint maxBorrowAmount;

        for (uint i = 0; i < providerCount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);
            if (amounts[i] > 0){
                amounts[i] = maxBorrowAllowed(usageParams[i]);
                maxBorrowAmount += amounts[i];
            }

            if (usageParams[i].rate < minRate){
                minRate = usageParams[i].rate;
            }
        }

        require(maxBorrowAmount >= _amount, "Strategy: insufficient balance");

        amounts = LoanCalculation.calculateAmountsToBorrow(_amount, minRate, usageParams, amounts);
    }

    function getRepayStrategy(address[] memory _providers, address _underlying, uint _amount) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        Types.UsageParams[] memory usageParams = new Types.UsageParams[](providerCount);
        uint32 maxRate;
        uint minRepayAmount;

        for (uint i = 0; i < providerCount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);
            if (amounts[i] > 0){
                amounts[i] = minRepayNeeded(usageParams[i]);
                minRepayAmount += amounts[i];
            }

            if (usageParams[i].rate > maxRate){
                maxRate = usageParams[i].rate;
            }
        }

         if (_amount > minRepayAmount){
            uint[] memory strategyAmounts = LoanCalculation.calculateAmountsToRepay(_amount - minRepayAmount, maxRate, usageParams);

            if (minRepayAmount > 0){
                for (uint i = 0; i < providerCount; i++){
                    amounts[i] += strategyAmounts[i];
                }
            }
        }
    }

    function minSupplyNeeded(Types.UsageParams memory _params) public view override returns (uint amount){
        if (_params.totalBorrowed * Utils.MILLION > maxLTV * _params.totalSupplied){
            amount = LoanCalculation.calculateSupplyAmountToReachLTV(_params, maxLTV);
        }
    }

    function minRepayNeeded(Types.UsageParams memory _params) public view override returns (uint amount){
        if (_params.totalBorrowed * Utils.MILLION > maxLTV * _params.totalSupplied){
            amount = LoanCalculation.calculateRepayAmountToReachLTV(_params, maxLTV);
        }
    }

    function maxWithdrawAllowed(Types.UsageParams memory _params) public view override returns (uint amount){
        if (_params.totalBorrowed * Utils.MILLION > maxLTV * _params.totalSupplied){
            amount = LoanCalculation.calculateWithdrawToReachLTV(_params, maxLTV);
        }
    }

    function maxBorrowAllowed(Types.UsageParams memory _params) public view override returns (uint amount){
        if (_params.totalBorrowed * Utils.MILLION > maxLTV * _params.totalSupplied){
            amount = LoanCalculation.calculateBorrowToReachLTV(_params, maxLTV);
        }
    }
}