// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProvider.sol";
import "./interfaces/IStrategy.sol";

import "./libraries/StrategyCalculations.sol";

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

        for (uint i = 0; i < providerCount && _amount > minSupplyAmount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);
            
            amounts[i] = Utils.minOf(_amount - minSupplyAmount, minSupplyNeeded(_providers[i], _underlying));
            minSupplyAmount += amounts[i];
            usageParams[i].totalSupplied += amounts[i];

            if (usageParams[i].rate > maxRate){
                maxRate = usageParams[i].rate;
            }
        }

        if (_amount > minSupplyAmount){
            uint[] memory strategyAmounts = StrategyCalculations.calculateAmountsToSupply(_amount - minSupplyAmount, maxRate, usageParams);

            if (minSupplyAmount > 0){
                for (uint i = 0; i < providerCount; i++){
                    amounts[i] += strategyAmounts[i];
                }
            }else{
                return strategyAmounts;
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
            amounts[i] = maxWithdrawAllowed(_providers[i], _underlying);
            maxWithdrawAmount += amounts[i];

            if (usageParams[i].rate < minRate){
                minRate = usageParams[i].rate;
            }
        }

        require(maxWithdrawAmount >= _amount, "Strategy: insufficient balance");

        amounts = StrategyCalculations.calculateAmountsToWithdraw(_amount, minRate, usageParams, amounts);
    }

    function getBorrowStrategy(address[] memory _providers, address _underlying, uint _amount) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        Types.UsageParams[] memory usageParams = new Types.UsageParams[](providerCount);
        uint32 minRate = Utils.MAX_UINT32;
        uint maxBorrowAmount;

        for (uint i = 0; i < providerCount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);
            amounts[i] = maxBorrowAllowed(_providers[i], _underlying);
            maxBorrowAmount += amounts[i];

            if (usageParams[i].rate < minRate){
                minRate = usageParams[i].rate;
            }
        }

        require(maxBorrowAmount >= _amount, "Strategy: insufficient balance");

        amounts = StrategyCalculations.calculateAmountsToBorrow(_amount, minRate, usageParams, amounts);
    }

    function getRepayStrategy(address[] memory _providers, address _underlying, uint _amount) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        Types.UsageParams[] memory usageParams = new Types.UsageParams[](providerCount);
        uint32 maxRate;
        uint minRepayAmount;

        for (uint i = 0; i < providerCount && _amount > minRepayAmount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);

            amounts[i] = Utils.minOf(_amount - minRepayAmount, minRepayNeeded(_providers[i], _underlying));
            minRepayAmount += amounts[i];
            usageParams[i].totalBorrowed -= amounts[i];

            if (usageParams[i].rate > maxRate){
                maxRate = usageParams[i].rate;
            }
        }

        if (_amount > minRepayAmount){
            uint[] memory strategyAmounts = StrategyCalculations.calculateAmountsToRepay(_amount - minRepayAmount, maxRate, usageParams);

            if (minRepayAmount > 0){
                for (uint i = 0; i < providerCount; i++){
                    amounts[i] += strategyAmounts[i];
                }
            }else{
                return strategyAmounts;
            }
        }
    }

    function minSupplyNeeded(address _provider, address _underlying) public view override returns (uint amount){
        (uint collateral, uint borrowed) = IProvider(_provider).totalColletralAndBorrow(msg.sender, _underlying);
        uint minCollateralNeeded = borrowed * Utils.MILLION / maxLTV;
        return minCollateralNeeded > collateral ? minCollateralNeeded - collateral : 0;
    }

    function maxWithdrawAllowed(address _provider, address _underlying) public view override returns (uint amount){
        (uint collateral, uint borrowed) = IProvider(_provider).totalColletralAndBorrow(msg.sender, _underlying);
        uint minCollateralNeeded = borrowed * Utils.MILLION / maxLTV;
        return minCollateralNeeded < collateral ? Utils.minOf(collateral - minCollateralNeeded, IProvider(_provider).supplyOf(_underlying, msg.sender)) : 0;
    }

    function maxBorrowAllowed(address _provider, address _underlying) public view override returns (uint amount){
        (uint collateral, uint borrowed) = IProvider(_provider).totalColletralAndBorrow(msg.sender, _underlying);
        uint maxDebtAllowed = collateral * maxLTV / Utils.MILLION;
        return maxDebtAllowed > borrowed ? maxDebtAllowed - borrowed : 0;
    }

    function minRepayNeeded(address _provider, address _underlying) public view override returns (uint amount){
        (uint collateral, uint borrowed) = IProvider(_provider).totalColletralAndBorrow(msg.sender, _underlying);
        uint maxDebtAllowed = collateral * maxLTV / Utils.MILLION;
        return maxDebtAllowed < borrowed ? borrowed - maxDebtAllowed : 0;
    }
}