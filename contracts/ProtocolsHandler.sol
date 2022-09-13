// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProtocol.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IStrategy.sol";

import "./libraries/TransferHelper.sol";
import "./libraries/Types.sol";
import "./libraries/Utils.sol";

contract ProtocolsHandler{
    IRouter public immutable router;
    IStrategy public strategy;

    IProtocol[] public protocols;

    modifier onlyRouter{
        require(msg.sender == address(router), "SToken: OnlyRouter");
        _;
    }

    constructor(IProtocol[] memory _protocols, IStrategy _strategy, IRouter _router){
        protocols = _protocols;
        strategy = _strategy;
        router = _router;
    }

    function redeemAndSupply(address _asset, uint[] memory supplies, uint _totalSupplied) internal {       
        IProtocol[] memory protocolsCache = protocols; 
        (uint[] memory supplyAmounts, uint[] memory redeemAmounts) = strategy.getSupplyStrategy(protocolsCache, _asset, supplies, _totalSupplied);
        for (uint i = 0; i < protocolsCache.length; i++){
            if (redeemAmounts[i] > 0){
                _redeem(protocolsCache[i], _asset, redeemAmounts[i]);
            }

            if (supplyAmounts[i] > 0){
                _supply(protocolsCache[i], _asset, supplyAmounts[i]);
            }
        }
    }

    function supply(address _asset, uint _amount, uint[] memory supplies, uint _totalSupplied) public onlyRouter returns(uint amount){
        redeemAndSupply(_asset, supplies,  _totalSupplied + _amount);
        return _amount;
    }  

    function redeem(address _asset, uint _amount, uint[] memory supplies, uint _totalSupplied, address _to) public onlyRouter returns(uint amount){        
        // expect revert if _amount > _totalSupplied
        redeemAndSupply(_asset, supplies, _totalSupplied - _amount);
        TransferHelper.transfer(_asset, _to, _amount);

        return _amount;
    }
    
    function borrow(Types.UserAssetParams memory _params) public onlyRouter returns(uint amount){
        IProtocol[] memory protocolsCache = protocols;
        uint[] memory amounts = strategy.getBorrowStrategy(protocolsCache, _params);

        for (uint i = 0; i < protocolsCache.length; i++){
            if (amounts[i] > 0){
                Types.ProtocolData memory data = protocolsCache[i].getBorrowData(_params.asset, _params.amount);
                Utils.lowLevelCall(data.target, data.encodedData, 0);
                if (data.weth != address(0)){
                    IWETH(data.weth).withdraw(amounts[i]);
                }
            }
        }

        TransferHelper.transfer(_params.asset, _params.to, _params.amount);

        return _params.amount;
    }

    function repay(Types.UserAssetParams memory _params) public onlyRouter returns(uint amount){
        (, uint total) = totalBorrowed(_params.asset);
        _params.amount = Utils.minOf(_params.amount, total);
        
        IProtocol[] memory protocolsCache = protocols;
        uint[] memory amounts = strategy.getRepayStrategy(protocolsCache, _params);
        for (uint i = 0; i < protocolsCache.length; i++){
            if (amounts[i] > 0){
                Types.ProtocolData memory data = protocolsCache[i].getRepayData(_params.asset, _params.amount);

                if (data.approveTo == address(0)){
                    Utils.lowLevelCall(data.target, data.encodedData, amounts[i]);
                }else{
                    if (data.weth != address(0)){
                        IWETH(data.weth).deposit{value: amounts[i]}();
                        TransferHelper.approve(data.weth, data.approveTo, amounts[i]);
                    }else{
                        TransferHelper.approve(_params.asset, data.approveTo, amounts[i]);
                    }

                    Utils.lowLevelCall(data.target, data.encodedData, 0);
                }
            }        
        }
        return _params.amount;
    }


    function totalSupplied(address asset) public view returns (uint[] memory amounts, uint totalAmount){
        IProtocol[] memory protocolsCache = protocols;
        amounts = new uint[](protocolsCache.length);
        for (uint i = 0; i < protocolsCache.length; i++){
            amounts[i] = protocolsCache[i].supplyOf(asset, address(this));
            totalAmount += amounts[i];
        }
    }

    function totalBorrowed(address asset) public view returns (uint[] memory amounts, uint totalAmount){
        IProtocol[] memory protocolsCache = protocols;
        amounts = new uint[](protocolsCache.length);
        for (uint i = 0; i < protocolsCache.length; i++){
            amounts[i] = protocolsCache[i].debtOf(asset, address(this));
            totalAmount += amounts[i];
        }
    }

    function simulateLendings(address _asset, uint _totalLending) public view returns (uint totalLending){
        IProtocol[] memory protocolsCache = protocols;
        uint supplyInterest;
        uint borrowInterest;
        for (uint i = 0; i < protocolsCache.length; i++){
            supplyInterest = protocolsCache[i].lastSupplyInterest(_asset);
            borrowInterest = protocolsCache[i].lastBorrowInterest(_asset);
        }

        uint interestDelta = borrowInterest > supplyInterest ? borrowInterest - supplyInterest : 0;
        (,uint borrowed) = totalBorrowed(_asset);
        (,uint supplied) = totalSupplied(_asset);
        totalLending = _totalLending + interestDelta * borrowed / supplied;
    }

    function simulateSupply(address _asset, uint _totalLending) external onlyRouter{
        IProtocol[] memory protocolsCache = protocols;
        uint[] memory supplyAmounts = strategy.getSimulateSupplyStrategy(protocolsCache, _asset, _totalLending);
        for (uint i = 0; i < protocolsCache.length; i++){
            protocolsCache[i].updateSupplyShare(_asset, supplyAmounts[i]);
        }
    }

    function simulateBorrow(address _asset, uint _totalLending) external onlyRouter{
        IProtocol[] memory protocolsCache = protocols;
        uint[] memory borrowAmounts = strategy.getSimulateBorrowStrategy(protocolsCache, _asset, _totalLending);
        for (uint i = 0; i < protocolsCache.length; i++){
            protocolsCache[i].updateBorrowShare(_asset, borrowAmounts[i]);
        }
    }

    function _supply(IProtocol _protocol, address _asset, uint _amount) internal{
        Types.ProtocolData memory data = _protocol.getSupplyData(_asset, _amount);

        // if supply with ETH
        if (data.approveTo == address(0)){
            Utils.lowLevelCall(data.target, data.encodedData, _amount);
        }else{
            if (data.weth != address(0)){
                IWETH(data.weth).deposit{value: _amount}();
                TransferHelper.approve(data.weth, data.approveTo, _amount);
            }else{
                TransferHelper.approve(_asset, data.approveTo, _amount);
            }

            Utils.lowLevelCall(data.target, data.encodedData, 0);
        }

        if (!data.initialized){
            Types.ProtocolData memory initData = _protocol.getAddAssetData(_asset);
            if (initData.target != address(0)){
                Utils.lowLevelCall(initData.target, initData.encodedData, 0);
            }
            _protocol.setInitialized(_asset);
        }
    }

    function _redeem(IProtocol _protocol, address _asset, uint _amount) internal{
        Types.ProtocolData memory data = _protocol.getRedeemData(_asset, _amount);
        Utils.lowLevelCall(data.target, data.encodedData, 0);
        if (data.weth != address(0)){
            IWETH(data.weth).withdraw(_amount);
        }
    }
}