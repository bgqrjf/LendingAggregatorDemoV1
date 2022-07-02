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

    function getSupplyStrategy(address[] memory _providers, address _underlying, uint _amount, address _for) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        uint maxRate;
        uint minSupplyAmount;
        bytes[] memory usageParams = new bytes[](providerCount);

        for (uint i = 0; i < providerCount && _amount > minSupplyAmount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);

            amounts[i] = Utils.minOf(_amount - minSupplyAmount, minSupplyNeeded(_providers[i], _underlying, _for));
            minSupplyAmount += amounts[i];

            uint rate = IProvider(_providers[i]).getCurrentSupplyRate(_underlying);
            if (rate > maxRate){
                maxRate = rate;
            }
        }

        if (_amount > minSupplyAmount){
            uint[] memory strategyAmounts = StrategyCalculations.calculateAmountsToSupply(_amount - minSupplyAmount, maxRate, _providers, usageParams);

            if (minSupplyAmount > 0){
                for (uint i = 0; i < providerCount; i++){
                    amounts[i] += strategyAmounts[i];
                }
            }else{
                return strategyAmounts;
            }
        }
    }

    function getWithdrawStrategy(address[] memory _providers, address _underlying, uint _amount, address _for) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        uint minRate = Utils.MAX_UINT32;
        uint maxWithdrawAmount;
        bytes[] memory usageParams = new bytes[](providerCount);

        for (uint i = 0; i < providerCount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);

            amounts[i] = maxWithdrawAllowed(_providers[i], _underlying, _for);
            maxWithdrawAmount += amounts[i];

            uint rate = IProvider(_providers[i]).getCurrentSupplyRate(_underlying);
            if (rate < minRate){
                minRate = rate;
            }
        }

        require(maxWithdrawAmount >= _amount, "Strategy: insufficient balance");

        amounts = StrategyCalculations.calculateAmountsToWithdraw(_amount, minRate, _providers, usageParams, amounts);
    }

    function getBorrowStrategy(address[] memory _providers, address _underlying, uint _amount, address _for) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        uint minRate = Utils.MAX_UINT32;
        uint maxBorrowAmount;
        bytes[] memory usageParams = new bytes[](providerCount);

        for (uint i = 0; i < providerCount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);

            amounts[i] = maxBorrowAllowed(_providers[i], _underlying, _for);
            maxBorrowAmount += amounts[i];

            uint rate = IProvider(_providers[i]).getCurrentBorrowRate(_underlying);
            if (rate < minRate){
                minRate = rate;
            }
        }

        require(maxBorrowAmount >= _amount, "Strategy: insufficient balance");

        amounts = StrategyCalculations.calculateAmountsToBorrow(_amount, minRate, _providers, usageParams, amounts);
    }

    function getRepayStrategy(address[] memory _providers, address _underlying, uint _amount, address _for) external view override returns (uint[] memory amounts){
        uint providerCount = _providers.length;
        amounts = new uint[](providerCount);
        uint maxRate;
        uint minRepayAmount;
        bytes[] memory usageParams = new bytes[](providerCount);
        uint[] memory maxAmountsToRepay = new uint[](providerCount);

        for (uint i = 0; i < providerCount && _amount > minRepayAmount; i++){
            usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);

            amounts[i] = Utils.minOf(_amount - minRepayAmount, minRepayNeeded(_providers[i], _underlying, _for));
            minRepayAmount += amounts[i];

            maxAmountsToRepay[i] = IProvider(_providers[i]).debtOf(_underlying, msg.sender);

            uint rate = IProvider(_providers[i]).getCurrentBorrowRate(_underlying);
            if (rate > maxRate){
                maxRate = rate;
            }
        }

        if (_amount > minRepayAmount){
            uint[] memory strategyAmounts = StrategyCalculations.calculateAmountsToRepay(_amount - minRepayAmount, maxRate, _providers, usageParams, maxAmountsToRepay);

            if (minRepayAmount > 0){
                for (uint i = 0; i < providerCount; i++){
                    amounts[i] += strategyAmounts[i];
                }
            }else{
                return strategyAmounts;
            }
        }
    }

    function minSupplyNeeded(address _provider, address _underlying, address _account) public view override returns (uint amount){
        (uint collateral, uint borrowed) = IProvider(_provider).totalColletralAndBorrow(_account, _underlying);
        uint minCollateralNeeded = borrowed * Utils.MILLION / maxLTV;
        return minCollateralNeeded > collateral ? minCollateralNeeded - collateral : 0;
    }

    function maxWithdrawAllowed(address _provider, address _underlying, address _account) public view override returns (uint amount){
        (uint collateral, uint borrowed) = IProvider(_provider).totalColletralAndBorrow(_account, _underlying);
        uint minCollateralNeeded = borrowed * Utils.MILLION / maxLTV;
        return minCollateralNeeded < collateral ? Utils.minOf(collateral - minCollateralNeeded, IProvider(_provider).supplyOf(_underlying, _account)) : 0;
    }

    function maxBorrowAllowed(address _provider, address _underlying, address _account) public view override returns (uint amount){
        (uint collateral, uint borrowed) = IProvider(_provider).totalColletralAndBorrow(_account, _underlying);
        uint maxDebtAllowed = collateral * maxLTV / Utils.MILLION;
        return maxDebtAllowed > borrowed ? maxDebtAllowed - borrowed : 0;
    }

    function minRepayNeeded(address _provider, address _underlying, address _account) public view override returns (uint amount){
        (uint collateral, uint borrowed) = IProvider(_provider).totalColletralAndBorrow(_account, _underlying);
        uint maxDebtAllowed = collateral * maxLTV / Utils.MILLION;
        return maxDebtAllowed < borrowed ? borrowed - maxDebtAllowed : 0;
    }
}