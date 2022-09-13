// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProtocol.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IRewards.sol";

import "./Utils.sol";
import "./TransferHelper.sol";

library Protocols {
    // using Protocols for IProtocol;
    // using Protocols for IProtocol[];
    // function supply(IProtocol _protocol, address _underlying, uint _amount) internal {
    //     Types.ProtocolData memory data = _protocol.getSupplyData(_underlying, _amount);
    //     _depositCall(data, _underlying, _amount);
    //     if (!data.initialized){
    //         _initializeProtocol(_protocol, _underlying);
    //     }
    // }
    // function redeem(IProtocol[] memory _protocols, IRewards rewards, address _underlying, uint _amount) internal returns (uint redeemedAmount){
    //     uint[] memory amounts = _protocols.supplies(_underlying);
    //     for (uint i = 0; i < _protocols.length && _amount > redeemedAmount ; i++){
    //         rewards.updateSupplyRewardData(_protocols, _underlying, share, msg.sender);
    //         uint amount = Utils.minOf(amounts[i], _amount - redeemedAmount);
    //         _protocols[i].redeem(_underlying,  amount);
    //         redeemedAmount += amount;
    //     }
    // }
    // function redeem(IProtocol _protocol, address _underlying, uint _amount) internal {
    //     Types.ProtocolData memory data = _protocol.getRedeemData(_underlying, _amount);
    //     _withdrawCall(data, _amount);
    // }
    // function protocolToSupply(IProtocol[] memory _protocols, address _underlying) internal view returns(IProtocol protocol){
    //     uint maxRate;
    //     for (uint i = 0; i < _protocols.length; i++){
    //         uint currentRate = _protocols[i].getCurrentSupplyRate(_underlying);
    //         if(currentRate > maxRate){
    //             protocol = _protocols[i];
    //             maxRate = currentRate;
    //         }
    //     }
    // }
    // function _initializeProtocol(IProtocol _protocol, address _underlying) private{
    //     Types.ProtocolData memory initData = _protocol.getAddAssetData(_underlying);
    //     if (initData.target != address(0)){
    //         Utils.lowLevelCall(initData.target, initData.encodedData, 0);
    //     }
    //     _protocol.setInitialized(_underlying);
    // }
    // function _depositCall(Types.ProtocolData memory _data, address underlying, uint amount) private{
    //     if (_data.approveTo == address(0)){
    //         Utils.lowLevelCall(_data.target, _data.encodedData, amount);
    //     }else{
    //         if (_data.weth != address(0)){
    //             IWETH(_data.weth).deposit{value: amount}();
    //             TransferHelper.approve(_data.weth, _data.approveTo, amount);
    //         }else{
    //             TransferHelper.approve(underlying, _data.approveTo, amount);
    //         }
    //         Utils.lowLevelCall(_data.target, _data.encodedData, 0);
    //     }
    // }
    // function _withdrawCall(Types.ProtocolData memory _data, uint _amount) internal {
    //     Utils.lowLevelCall(_data.target, _data.encodedData, 0);
    //     if (_data.weth != address(0)){
    //         IWETH(_data.weth).withdraw(_amount);
    //     }
    // }
    // function repay(IProtocol[] memory _protocols, address _underlying, uint _amount) internal returns (uint repayedAmount){
    //     uint[] memory amounts = _protocols.debts(_underlying);
    //     for (uint i = 0; i < _protocols.length && _amount > repayedAmount ; i++){
    //         uint amount = Utils.minOf(amounts[i], _amount - repayedAmount);
    //         _protocols[i].repay(_underlying,  amount);
    //         repayedAmount += amount;
    //     }
    // }
    // function repay(IProtocol _protocol, address _underlying, uint _amount) internal {
    //     Types.ProtocolData memory data = _protocol.getRepayData(_underlying, _amount);
    //     _depositCall(data, _underlying, _amount);
    // }
    // function borrow(IProtocol[] memory _protocols, address _underlying, uint _amount) internal returns (uint repayedAmount){
    // }
    // function supplies(IProtocol[] memory _protocols, address _underlying) internal view returns (uint[] memory amounts){
    //     amounts = new uint[](_protocols.length);
    //     for (uint i = 0; i < _protocols.length; i++){
    //         amounts[i] = _protocols[i].supplyOf(_underlying, address(this));
    //     }
    // }
    // function debts(IProtocol[] memory _protocols, address _underlying) internal view returns (uint[] memory amounts){
    //     amounts = new uint[](_protocols.length);
    //     for (uint i = 0; i < _protocols.length; i++){
    //         amounts[i] = _protocols[i].debtOf(_underlying, address(this));
    //     }
    // }
    // function rebalance(IProtocol[] memory _protocols, IStrategy strategy, IRewards rewards, address _underlying, uint _totalShare) internal {
    //     // calculate supply strategy
    //     (uint[] memory currentSupplies, uint[] memory newSupplies) = strategy.rebalanceSupplies(_protocols, _underlying);
    //     for (uint i = 0 ; i < _protocols.length; i++){
    //         if (currentSupplies[i] > newSupplies[i]){
    //             uint redeemAmount = currentSupplies[i] - newSupplies[i];
    //             Types.ProtocolData memory data = _protocols[i].getRedeemData(_underlying, redeemAmount);
    //             _withdrawCall(data, redeemAmount);
    //             rewards.updateRouterSupplyRewardData(_protocols[i], _underlying, _totalShare);
    //         }
    //     }
    //     for (uint i = 0; i < _protocols.length; i++){
    //         if (currentSupplies[i] < newSupplies[i]){
    //             uint supplyAmount = newSupplies[i] - currentSupplies[i];
    //             Types.ProtocolData memory data = _protocols[i].getSupplyData(_underlying, supplyAmount);
    //             _depositCall(data, _underlying, supplyAmount);
    //             rewards.updateRouterSupplyRewardData(_protocols[i], _underlying, _totalShare);
    //         }
    //     }
    // }
}
