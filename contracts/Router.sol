// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IConfig.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IStrategy.sol";

import "./libraries/Types.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/UserAssetBitMap.sol";
import "./libraries/Utils.sol";

import "./ProtocolsHandler.sol";

contract Router {

    IConfig public config;
    IFactory public factory;
    IPriceOracle public priceOracle;
    ProtocolsHandler public protocols;
    IRewards public rewards;
    IStrategy public strategy;

    address[] public underlyings;

    mapping(address => Types.Asset) private _assets;

    mapping(address => uint) public totalLendings;
    mapping(address => uint) public userSupplied;

    event Supplied(address indexed supplier, address indexed asset, uint amount);
    event Redeemed(address indexed supplier, address indexed asset, uint amount);
    event Borrowed(address indexed borrower, address indexed asset, uint amount);
    event Repayed(address indexed borrower, address indexed asset, uint amount);

    event totalLendingsUpdated(address indexed asset, uint oldLending, uint newLending);

    constructor(address _priceOracle, address _strategy, address _factory, address _rewards){
        factory = IFactory(_factory);
        priceOracle = IPriceOracle(_priceOracle);
        strategy = IStrategy(_strategy);

        config = IConfig(IFactory(_factory).newConfig(msg.sender));
        rewards = IRewards(_rewards);
    }

    receive() external payable {}

    function supply(Types.UserAssetParams memory _params, bool _collateralable) public payable {
        ProtocolsHandler protocolsCache = protocols;
        Types.Asset memory asset = _assets[_params.asset];
        uint totalLending = protocols.simulateLendings(_params.asset, totalLendings[_params.asset]);

        TransferHelper.collectTo(_params.asset, msg.sender, address(protocolsCache), _params.amount);

        (uint[] memory supplies, uint totalSupplied) = protocolsCache.totalSupplied(_params.asset);

        uint sTokenAmount = asset.sToken.mint(_params.to, _params.amount, totalSupplied + totalLending);

        uint repayed = protocolsCache.repay(_params);
        if (_params.amount > repayed){
            protocolsCache.supply(_params.asset, _params.amount - repayed, supplies, totalSupplied);
        }

        // store on strategy aToken and cToken amount
        config.setUsingAsCollateral(_params.to, asset.index, _collateralable);
                
        updatetotalLendings(_params.asset, totalLending + repayed);
        rewards.startMiningSupplyReward(_params.asset, _params.to, sTokenAmount);

        protocolsCache.simulateSupply(_params.asset, totalLending + repayed);

        emit Supplied(_params.to, _params.asset, _params.amount);
    }

    function redeem(Types.UserAssetParams memory _params, bool _collateralable) public {
        ProtocolsHandler protocolsCache = protocols;
        Types.Asset memory asset = _assets[_params.asset];
        (uint[] memory supplies, uint totalSupplied) = protocolsCache.totalSupplied(_params.asset) ;
        uint totalLending = protocolsCache.simulateLendings(_params.asset, totalLendings[_params.asset]);

        uint sTokenAmount = asset.sToken.burn(msg.sender, _params.amount, totalSupplied + totalLendings[_params.asset]);

        // pay in protocol
        _redeem(_params, sTokenAmount, supplies, totalSupplied, totalLending);
        config.setUsingAsCollateral(msg.sender, asset.index, _collateralable);
    }

    function _redeem(Types.UserAssetParams memory _params, uint _sTokenAmount, uint[] memory _supplies, uint _totalSupplied, uint _totalLending) internal {
        ProtocolsHandler protocolsCache = protocols;
        uint redeemed = protocolsCache.redeem(_params.asset, _params.amount, _supplies, _totalSupplied, _params.to);

        if (_params.amount > redeemed){
            uint borrowed = protocolsCache.borrow(_params);
            _totalLending -= borrowed;
        }

        updatetotalLendings(_params.asset, _totalLending);
        rewards.stopMiningSupplyReward(_params.asset, msg.sender, _sTokenAmount);

        protocolsCache.simulateSupply(_params.asset, _totalLending);

        emit Redeemed(msg.sender, _params.asset, _params.amount);
    }

    function borrow(Types.UserAssetParams memory _params) public{
        require(borrowAllowed(_params), "Router: borrow not allowed");

        ProtocolsHandler protocolsCache = protocols;
        Types.Asset memory asset = _assets[_params.asset];

        (uint[] memory borrows, uint totalBorrowed) = protocolsCache.totalBorrowed(_params.asset);
        uint totalLending = protocolsCache.simulateLendings(_params.asset, totalLendings[_params.asset]);
        uint dTokenAmount = asset.dToken.mint(msg.sender, _params.amount, totalBorrowed + totalLendings[_params.asset]);

        config.setBorrowing(msg.sender, asset.index, true);

        (uint[] memory supplies, uint totalSupplied) = protocolsCache.totalSupplied(_params.asset);
        uint redeemed = protocolsCache.redeem(_params.asset, _params.amount, supplies, totalSupplied, _params.to);
        if (_params.amount > redeemed){
            _params.amount -= redeemed;
            protocolsCache.borrow(_params);
        }

        updatetotalLendings(_params.asset, totalLending + redeemed);
        rewards.startMiningBorrowReward(_params.asset, _params.to, dTokenAmount);

        protocolsCache.simulateBorrow(_params.asset, totalLending + redeemed);

        emit Borrowed(msg.sender, _params.asset, _params.amount);
    }

    function repay(Types.UserAssetParams memory _params) public payable {
        ProtocolsHandler protocolsCache = protocols;

        TransferHelper.collectTo(_params.asset, msg.sender, address(protocolsCache), _params.amount);
        
        Types.Asset memory asset = _assets[_params.asset];

        (uint[] memory borrows, uint totalBorrowed) = protocolsCache.totalBorrowed(_params.asset);
        uint totalLending = protocolsCache.simulateLendings(_params.asset, totalLendings[_params.asset]);
        uint dTokenAmount = asset.dToken.burn(_params.to, _params.amount, totalBorrowed + totalLendings[_params.asset]);

        uint repayed = protocolsCache.repay(_params);
        if (_params.amount > 0){
            (uint[] memory supplies, uint totalSupplied) = protocolsCache.totalSupplied(_params.asset);
            uint supplied = protocolsCache.supply(_params.asset, _params.amount - repayed, supplies, totalSupplied);
            totalLending += supplied;
        }

        updatetotalLendings(_params.asset, totalLending);
        rewards.stopMiningBorrowReward(_params.asset, _params.to, dTokenAmount);

        protocolsCache.simulateBorrow(_params.asset, totalLending);

        emit Repayed(_params.to, _params.asset, _params.amount);
    }

    function liquidate(Types.UserAssetParams memory _repayParams, Types.UserAssetParams memory _redeemParams) public payable{
        Types.BorrowConfig memory bc = config.borrowConfigs(_repayParams.asset);
        require(liquidateAllowed(_repayParams, bc), "Router: liquidate not allowed");

        repay(_repayParams);

        ISToken sToken = _assets[_redeemParams.asset].sToken;
        uint assetValue = priceOracle.valueOfAsset(_repayParams.asset, _redeemParams.asset, _repayParams.amount);
        uint redeemAmount = Utils.minOf(assetValue * bc.liquidateRewardRatio / Utils.MILLION, sToken.balanceOf(_repayParams.to));
        (uint[] memory supplies, uint totalSupplied) = protocols.totalSupplied(_redeemParams.asset);
        uint totalLending = protocols.simulateLendings(_redeemParams.asset, totalLendings[_redeemParams.asset]);
        uint sTokenAmount = sToken.burn(_repayParams.to, redeemAmount, totalSupplied + totalLending);
        _redeem(_redeemParams, sTokenAmount, supplies, totalSupplied, totalLending);
    }

    function borrowAllowed(Types.UserAssetParams memory _params) internal view returns (bool){
        Types.BorrowConfig memory bc = config.borrowConfigs(_params.asset);
        (uint collateralValue, uint debtsValue) = userStatus(_params.to, _params.asset);

        uint borrowLimit = collateralValue * bc.liquidateLTV / Utils.MILLION ;
        return _params.amount + debtsValue < borrowLimit;
    }

    function liquidateAllowed(Types.UserAssetParams memory _params, Types.BorrowConfig memory _bc) internal view returns (bool){
        (uint collateralValue, uint debtsValue) = userStatus(_params.to, _params.asset);
        uint maxLiquidation = debtsValue * _bc.maxLiquidateRatio / Utils.MILLION;

        return debtsValue * Utils.MILLION > _bc.liquidateLTV * collateralValue && _params.amount < maxLiquidation;
    }

    function updatetotalLendings(address _asset, uint _new) internal{
        uint old = totalLendings[_asset];
        totalLendings[_asset] = _new;
        emit totalLendingsUpdated(_asset, old, _new);
    }

    function userStatus(address _account, address _quote) public view returns (uint collateralValue, uint borrowingValue){
        uint userConfig = config.userDebtAndCollateral(_account);
        for (uint i = 0; i < underlyings.length; i++){
            if (UserAssetBitMap.isUsingAsCollateralOrBorrowing(userConfig, i)){
                Types.Asset memory asset = _assets[underlyings[i]];

                if (UserAssetBitMap.isUsingAsCollateral(userConfig, i)){
                    address underlying = asset.sToken.underlying();
                    uint balance = asset.sToken.scaledBalanceOf(_account);
                    
                    collateralValue += underlying == _quote ? balance : priceOracle.valueOfAsset(underlying, _quote, balance);
                }

                if (UserAssetBitMap.isBorrowing(userConfig, i)){
                    address underlying = asset.dToken.underlying();
                    uint balance = asset.dToken.scaledDebtOf(_account);

                    borrowingValue += underlying == _quote ? balance : priceOracle.valueOfAsset(underlying, _quote, balance);
                }
            }
        }
    }

    function updateLendings(address _asset) internal{
    }
}