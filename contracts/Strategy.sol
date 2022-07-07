// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProvider.sol";
import "./interfaces/IStrategy.sol";

import "./libraries/StrategyCalculations.sol";

contract Strategy is IStrategy{
    using StrategyCalculations for Types.StrategyParams;

    uint public maxLTV;

    constructor (uint _maxLTV){
        maxLTV = _maxLTV;
    }

    function getSupplyStrategy(address[] memory _providers, address _underlying, uint _amount, address _for) external view override returns (uint[] memory amounts){
        Types.StrategyParams memory params;
        params.providers = _providers;
        params.usageParams = new bytes[](params.providers.length);

        amounts = new uint[](params.providers.length);
        uint maxRate;
        uint minSupplyAmount;

        for (uint i = 0; i < params.providers.length && _amount > minSupplyAmount; i++){
            params.usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);

            amounts[i] = Utils.minOf(_amount - minSupplyAmount, minSupplyNeeded(_providers[i], _underlying, _for));
            minSupplyAmount += amounts[i];

            uint rate = IProvider(_providers[i]).getCurrentSupplyRate(_underlying);
            if (rate > maxRate){
                params.targetRate0 = maxRate;
                maxRate = rate;
                params.targetIndex = i;
            }else if (rate > params.targetRate0){
                params.targetRate0 = rate;
            }
        }

        if (_amount > minSupplyAmount){
            params.targetAmount = _amount - minSupplyAmount;

            uint[] memory strategyAmounts = params.calculateAmountsToSupply(maxRate);
            if (minSupplyAmount > 0){
                for (uint i = 0; i < params.providers.length; i++){
                    amounts[i] += strategyAmounts[i];
                }
            }else{
                return strategyAmounts;
            }
        }
    }

    function getWithdrawStrategy(address[] memory _providers, address _underlying, uint _amount, address _for) external view override returns (uint[] memory amounts){
        Types.StrategyParams memory params;
        params.providers = _providers;
        params.targetAmount = _amount;
        params.usageParams = new bytes[](params.providers.length);
        
        amounts = new uint[](params.providers.length);
        uint minRate = Utils.MAX_UINT32;
        uint maxWithdrawAmount;

        for (uint i = 0; i < params.providers.length; i++){
            params.usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);

            amounts[i] = maxWithdrawAllowed(_providers[i], _underlying, _for);
            maxWithdrawAmount += amounts[i];

            uint rate = IProvider(_providers[i]).getCurrentSupplyRate(_underlying);
            if (rate < minRate){
                params.targetRate0 = minRate;
                minRate = rate;
                params.targetIndex = i;
            }else if (rate < params.targetRate0){
                params.targetRate0 = rate;
            }
        }

        require(maxWithdrawAmount >= _amount, "Strategy: insufficient balance");

        amounts = params.calculateAmountsToWithdraw(minRate, amounts);
    }

    function getBorrowStrategy(address[] memory _providers, address _underlying, uint _amount, address _for) external view override returns (uint[] memory amounts){
        Types.StrategyParams memory params;
        params.providers = _providers;
        params.targetAmount = _amount;
        params.usageParams = new bytes[](params.providers.length);
        
        amounts = new uint[](params.providers.length);
        uint minRate = Utils.MAX_UINT32;
        uint maxBorrowAmount;

        for (uint i = 0; i < params.providers.length; i++){
            params.usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);

            amounts[i] = maxBorrowAllowed(_providers[i], _underlying, _for);
            maxBorrowAmount += amounts[i];

            uint rate = IProvider(_providers[i]).getCurrentBorrowRate(_underlying);
            if (rate < minRate){
                params.targetRate0 = minRate;
                minRate = rate;
                params.targetIndex = i;
            }else if (rate < params.targetRate0){
                params.targetRate0 = rate;
            }
        }

        require(maxBorrowAmount >= _amount, "Strategy: insufficient balance");

        amounts = params.calculateAmountsToBorrow(minRate, amounts);
    }

    function getRepayStrategy(address[] memory _providers, address _underlying, uint _amount, address _for) external view override returns (uint[] memory amounts){
        Types.StrategyParams memory params;
        params.providers = _providers;
        params.targetAmount = _amount;
        params.usageParams = new bytes[](params.providers.length);
        
        amounts = new uint[](params.providers.length);
        uint[] memory maxAmountsToRepay = new uint[](params.providers.length);
        uint maxRate;
        
        uint minRepayAmount;
        for (uint i = 0; i < params.providers.length && _amount > params.providers.length; i++){
            params.usageParams[i] = IProvider(_providers[i]).getUsageParams(_underlying);

            amounts[i] = Utils.minOf(_amount - params.providers.length, minRepayNeeded(_providers[i], _underlying, _for));
            minRepayAmount += amounts[i];

            maxAmountsToRepay[i] = IProvider(_providers[i]).debtOf(_underlying, msg.sender);

            uint rate = IProvider(_providers[i]).getCurrentBorrowRate(_underlying);
            if (rate > maxRate){
                params.targetRate0 = maxRate;
                maxRate = rate;
                params.targetIndex = i;
            }else if (rate > params.targetRate0){
                params.targetRate0 = rate;
            }
        }

        if (_amount > params.providers.length){
            uint[] memory strategyAmounts = params.calculateAmountsToRepay(maxRate, maxAmountsToRepay);


            if (params.providers.length > 0){
                for (uint i = 0; i < params.providers.length; i++){
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