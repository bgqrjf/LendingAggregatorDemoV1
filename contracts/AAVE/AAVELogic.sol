// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProvider.sol";
import "./IAAVEPool.sol";
import "./IAAVEInterestRateStrategy.sol";

import "./AAVEDataTypes.sol";
import "./AAVEReserveConfigurationGetter.sol";
import "../libraries/Utils.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/Types.sol";

contract AAVELogic is IProvider{
    IAAVEPool public pool;

    constructor(address _pool){
        pool = IAAVEPool(_pool);
    }

    function supply(address _underlying, uint _amount) external override{
        pool.supply(_underlying, _amount, address(this), 0);
    }

    function withdraw(address _underlying, uint _amount) external override{
        pool.withdraw(_underlying, _amount, address(this));
    }

    function withdrawAll(address _underlying) external override{
        pool.withdraw(_underlying, Utils.MAX_UINT, address(this));
    }

    function borrow (address _underlying, uint _amount) external override{
        pool.borrow(_underlying, _amount, uint(AAVEDataTypes.InterestRateMode.VARIABLE), 0, address(this));
    }
 
    function repay(address _underlying, uint _amount) external override{
        pool.repay(_underlying, _amount, uint(AAVEDataTypes.InterestRateMode.VARIABLE), address(this));
    } 

    // return underlying Token
    // return data for caller
    function supplyOf(address _underlying) external view override returns (uint) {
        AAVEDataTypes.ReserveData memory reserve = pool.getReserveData(_underlying);
        return TransferHelper.balanceOf(reserve.aTokenAddress, msg.sender);
    }

    function debtOf(address _underlying) external view override returns (uint) {
        AAVEDataTypes.ReserveData memory reserve = pool.getReserveData(_underlying);
        return TransferHelper.balanceOf(reserve.variableDebtTokenAddress, msg.sender);
    }

    // ray to Million
    function getUsageParams(address _underlying) external view override returns (Types.UsageParams memory _params){
        AAVEDataTypes.ReserveData memory reserve = pool.getReserveData(_underlying);
        _params.totalSupplied = TransferHelper.balanceOf(reserve.aTokenAddress, msg.sender);
        _params.totalBorrowed = TransferHelper.balanceOf(reserve.variableDebtTokenAddress, msg.sender);
        _params.slope1 = truncateRay(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).getVariableRateSlope1(), 6);
        _params.slope2 =  truncateRay(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).getVariableRateSlope2(), 6);
        _params.base =  truncateRay(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).getBaseVariableBorrowRate(), 6);
        _params.optimalLTV =  truncateRay(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).OPTIMAL_USAGE_RATIO(), 6);
        _params.rate =  truncateRay(IAAVEInterestRateStrategy(reserve.interestRateStrategyAddress).getBaseVariableBorrowRate(), 6);
        _params.reserveFactor = uint32(AAVEReserveConfigurationGetter.getReserveFactor(reserve.configuration) * 100);
    }

    function truncateRay(uint x, uint l) internal pure returns (uint32 y){
        return uint32(x / 10 ** (27- l));
    }
}