// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProvider.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IWETH.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/Utils.sol";
import "./libraries/UserAssetBitMap.sol";
import "./libraries/Math.sol";

contract Router is IRouter, Ownable{
    using Math for uint;

    IConfig public config;
    IPriceOracle public priceOracle;
    IStrategy public strategy;
    IFactory public factory;

    address[] public underlyings;
    address[] public providers;

    mapping(address => Types.Asset) private _assets;
    mapping(address => uint) public assetIndex;
    mapping(address => mapping(address => mapping(address => bytes))) public rewardData;

    event AmountsSupplied(address indexed supplier, address indexed underlying, uint amount, address[] suppliedTo, uint[] amounts);
    event AmountsWithdrawed(address indexed supplier, address indexed underlying, uint amount, address[] withdrawedFrom, uint[] amounts);
    event AmountsBorrowed(address indexed borrower, address indexed underlying, uint amount, address[] borrowedFrom, uint[] amounts);
    event AmountsRepayed(address indexed borrower, address indexed underlying, uint amount, address[] repayedTo, uint[] amounts);

    constructor(address[] memory _providers, address _priceOracle, address _strategy, address _factory){
        factory = IFactory(_factory);
        priceOracle = IPriceOracle(_priceOracle);
        strategy = IStrategy(_strategy);

        config = IConfig(IFactory(_factory).newConfig(msg.sender));

        providers = _providers;
    }

    receive() external payable {}

    function addAsset(Types.NewAssetParams memory _newAsset) external override onlyOwner returns (Types.Asset memory asset){
        uint8 underlyingCount = uint8(underlyings.length);
        require(underlyingCount < UserAssetBitMap.MAX_RESERVES_COUNT, "Router: asset list full");
        underlyings.push(_newAsset.underlying);

        asset =  factory.newAsset(_newAsset, underlyingCount);
        _assets[_newAsset.underlying] = asset;
        config.setBorrowConfig(_newAsset.underlying, _newAsset.borrowConfig);
    }

    function updateConfig(address _config) external override onlyOwner{
        config = IConfig(_config);
    }
    
    function updateFactory(address _factory) external override onlyOwner{
        factory = IFactory(_factory);
    }

    function addProvider(address _provider) external override onlyOwner{
        providers.push(_provider);
    }

    function removeProvider(uint _providerIndex, address _provider) external override onlyOwner{
        address[] memory providersCached = providers;
        require(providersCached[_providerIndex] == _provider, "Router: wrong index");
        require(providersCached.length > 1, "Router: at least 1 provider is required");
        providers[_providerIndex] = providersCached[providersCached.length - 1];
        providersCached[_providerIndex] = providersCached[providersCached.length - 1];
        providers.pop();

        address[] memory underlyingCached = underlyings;
        for (uint i = 0; i < underlyingCached.length; i++){
            // borrow from other pools
            uint amount = IProvider(_provider).debtOf(underlyingCached[i], address(this));
            if (amount > 0) {
                uint[] memory amounts = strategy.getBorrowStrategy(providers, underlyingCached[i], amount, address(this));
                for (uint j = 0; j < amounts.length; i++){
                    Types.ProviderData memory data = IProvider(providersCached[i]).getBorrowData(underlyingCached[i], amounts[i]);
                    Utils.lowLevelCall(data.target, data.encodedData, 0);
                    if (data.weth != address(0)){
                        IWETH(data.weth).withdraw(amounts[i]);
                    }
                }

                // repay Debts
                {
                    Types.ProviderData memory data = IProvider(_provider).getRepayData(underlyingCached[i], amount);
                    if (data.approveTo == address(0)){
                        Utils.lowLevelCall(data.target, data.encodedData, amounts[i]);
                    }else{
                        if (underlyingCached[i] == TransferHelper.ETH){
                            IWETH(data.weth).deposit{value: amounts[i]}();
                            TransferHelper.approve(data.weth, data.approveTo, amounts[i]);
                        }else{
                            TransferHelper.approve(underlyingCached[i], data.approveTo, amounts[i]);
                        }

                        Utils.lowLevelCall(data.target, data.encodedData, 0);
                    }
                }
            }
        }
        
        for (uint i = 0; i < underlyingCached.length; i++){
            Types.ProviderData memory data = IProvider(_provider).getWithdrawAllData(underlyingCached[i]);
            Utils.lowLevelCall(data.target, data.encodedData, 0);
            if (underlyingCached[i] == TransferHelper.ETH){
                IWETH(data.weth).withdraw(TransferHelper.balanceOf(data.weth, address(this)));
            }

            supply(underlyingCached[i], address(0), false);
        }
    } 

    function updatePriceOracle(address _priceOracle) external override onlyOwner{
        priceOracle = IPriceOracle(_priceOracle); 
    }

    function updateStrategy(address _strategy) external override onlyOwner{
        strategy = IStrategy(_strategy);
    }

    // rebalance with strategy
    function supply(address _underlying, address _to, bool _colletralable) public override returns (uint sTokenAmount){
        Types.Asset memory asset = _assets[_underlying];
        address[] memory supplyTo = providers;
        uint amount = TransferHelper.balanceOf(_underlying, address(this));
        require(amount > 0, "Router: no token received");
        Types.UserShare memory share = userShare(_to, asset);

        {
            uint sTokenSupply = asset.sToken.totalSupply();
            uint uTokenSupplied = totalSupplied(_underlying);

            if (_to != address(0)){
                sTokenAmount = uTokenSupplied > 0 ? amount * sTokenSupply / uTokenSupplied : amount;
                asset.sToken.mint(_to, sTokenAmount);
                config.setUsingAsCollateral(_to, asset.index, _colletralable);
            }
        }

        uint[] memory amounts = strategy.getSupplyStrategy(supplyTo, _underlying, amount, address(this));
        for (uint i = 0; i < supplyTo.length; i++){
            if (amounts[i] > 0){
                Types.ProviderData memory data = IProvider(supplyTo[i]).getSupplyData(_underlying, amounts[i]);

                if (_to != address(0)){
                    bytes memory rewardDataCache = rewardData[_to][supplyTo[i]][_underlying];
                    rewardDataCache = IProvider(supplyTo[i]).getRewardSupplyData(_underlying, share, rewardDataCache); 
                    rewardData[_to][supplyTo[i]][_underlying] = rewardDataCache;
                }
                
                if (data.approveTo == address(0)){
                    Utils.lowLevelCall(data.target, data.encodedData, amounts[i]);
                }else{
                    if (data.weth != address(0)){
                        IWETH(data.weth).deposit{value: amounts[i]}();
                        TransferHelper.approve(data.weth, data.approveTo, amounts[i]);
                    }else{
                        TransferHelper.approve(_underlying, data.approveTo, amounts[i]);
                    }

                    Utils.lowLevelCall(data.target, data.encodedData, 0);
                }

                if (!data.initialized){
                    Types.ProviderData memory initData = IProvider(supplyTo[i]).getAddAssetData(_underlying);
                    if (initData.target != address(0)){
                        Utils.lowLevelCall(initData.target, initData.encodedData, 0);
                    }
                    IProvider(supplyTo[i]).setInitialized(_underlying);
                }
            }
        }
        
        emit AmountsSupplied(_to, _underlying, amount, supplyTo, amounts);
    }

    function withdraw(address _underlying, address _to, uint _sTokenAmount, bool _colletralable) public override returns (uint amount){
        Types.Asset memory asset = _assets[_underlying];
        address[] memory withdrawFrom = providers;       

        Types.UserShare memory share = userShare(msg.sender, asset);
 
        {
            uint sTokenSupply = asset.sToken.totalSupply();
            uint uTokenSupplied = totalSupplied(_underlying);

            amount = _sTokenAmount * uTokenSupplied / sTokenSupply;
            require(amount > 0, "Router: withdraw 0");
            require(withdrawCap(msg.sender, _underlying) >= amount, "SToken: not enough collateral");

            asset.sToken.burn(msg.sender, _sTokenAmount);
            config.setUsingAsCollateral(msg.sender, asset.index, _colletralable);
        }


        uint[] memory amounts = strategy.getWithdrawStrategy(withdrawFrom, _underlying, amount, address(this));
        for (uint i = 0; i < withdrawFrom.length; i++){
            if (amounts[i] > 0){
                Types.ProviderData memory data = IProvider(withdrawFrom[i]).getWithdrawData(_underlying, amounts[i]);

                bytes memory rewardDataCache = rewardData[msg.sender][withdrawFrom[i]][_underlying];
                rewardDataCache = IProvider(withdrawFrom[i]).getRewardSupplyData(_underlying, share, rewardDataCache); 
                rewardData[msg.sender][withdrawFrom[i]][_underlying] = rewardDataCache;

                Utils.lowLevelCall(data.target, data.encodedData, 0);
                if (data.weth != address(0)){
                    IWETH(data.weth).withdraw(amounts[i]);
                }
            }
        }
        
        uint balance = TransferHelper.balanceOf(_underlying, address(this));
        TransferHelper.transfer(_underlying, _to, balance);
        emit AmountsWithdrawed(msg.sender, _underlying, balance, withdrawFrom, amounts);
    }

    function borrow(address _underlying, address _to, uint _borrowAmount) public override returns (uint amount){
        require(_borrowAmount < borrowCap(_underlying, msg.sender), "DToken: insufficient collateral");

        Types.Asset memory asset = _assets[_underlying];
        address[] memory borrowFrom = providers;

        Types.UserShare memory share = userShare(msg.sender, asset);
        {
            // uint dTokenSupply = asset.dToken.totalSupply();
            uint debts = totalDebts(_underlying);
            uint dTokenAmount = share.dTokenTotalSupply > 0 ? (_borrowAmount * share.dTokenTotalSupply).divCeil(debts) : _borrowAmount;
            require(dTokenAmount > 0, "Router: no borrow amount");
            
            asset.dToken.mint(msg.sender, dTokenAmount);
            config.setBorrowing(msg.sender, asset.index, true);
        }

        uint[] memory amounts = strategy.getBorrowStrategy(borrowFrom, _underlying, _borrowAmount, address(this));
        for (uint i = 0; i < borrowFrom.length; i++){
            if (amounts[i] > 0){
                Types.ProviderData memory data = IProvider(borrowFrom[i]).getBorrowData(_underlying, amounts[i]);

                rewardData[msg.sender][borrowFrom[i]][_underlying] = IProvider(borrowFrom[i]).getRewardBorrowData(_underlying, share, rewardData[msg.sender][borrowFrom[i]][_underlying]);

                Utils.lowLevelCall(data.target, data.encodedData, 0);
                if (data.weth != address(0)){
                    IWETH(data.weth).withdraw(amounts[i]);
                }

            }
          
        }

        amount = TransferHelper.balanceOf(_underlying, address(this));
        TransferHelper.transfer(_underlying, _to, amount);

        emit AmountsBorrowed(msg.sender, _underlying, amount, borrowFrom, amounts);
    }

    function repay(address _underlying, address _for) public override returns (uint amount){
        Types.Asset memory asset = _assets[_underlying];
        address[] memory repayTo = providers;

        Types.UserShare memory share = userShare(msg.sender, asset);

        {
            uint debts = totalDebts(_underlying);
            
            amount = TransferHelper.balanceOf(_underlying, address(this));
            uint dTokenAmount =  amount * share.dTokenTotalSupply / debts;
            require(dTokenAmount <= asset.dToken.balanceOf(_for), "Router: excceed repay Limit");
            asset.dToken.burn(_for, dTokenAmount);

            if (asset.dToken.balanceOf(_for) == 0){
                config.setBorrowing(_for, asset.index, false);
            }
        }

        uint[] memory amounts = strategy.getRepayStrategy(repayTo, _underlying, amount, address(this));
        for (uint i = 0; i < repayTo.length; i++){
            if(amounts[i] > 0){
                Types.ProviderData memory data = IProvider(repayTo[i]).getRepayData(_underlying, amounts[i]);
                rewardData[_for][repayTo[i]][_underlying] = IProvider(repayTo[i]).getRewardBorrowData(_underlying, share, rewardData[_for][repayTo[i]][_underlying]);

                if (data.approveTo == address(0)){
                    Utils.lowLevelCall(data.target, data.encodedData, amounts[i]);
                }else{
                    if (data.weth != address(0)){
                        IWETH(data.weth).deposit{value: amounts[i]}();
                        TransferHelper.approve(data.weth, data.approveTo, amounts[i]);
                    }else{
                        TransferHelper.approve(_underlying, data.approveTo, amounts[i]);
                    }

                    Utils.lowLevelCall(data.target, data.encodedData, 0);
                }


            }
        }

        emit AmountsRepayed(_for, _underlying, amount, repayTo, amounts);
    }

    function liquidate(
        address _debtToken, 
        address _colletrallToken, 
        address _for, 
        address _to
    ) external override returns (uint liquidateAmount, uint burnAmount){
        Types.BorrowConfig memory bc = config.borrowConfigs(_debtToken);
        (uint collateralValue, uint debtsValue) = valueOf(_for, _debtToken);

        require(debtsValue * Utils.MILLION > bc.liquidateLTV * collateralValue, "Router: sufficient collateral");

        liquidateAmount = repay(_debtToken, _for);

        require(liquidateAmount <=  debtsValue * bc.maxLiquidateRatio / Utils.MILLION, "Router: Exceed Liquidate Cap");

        burnAmount = priceOracle.valueOfAsset(_debtToken, _colletrallToken, liquidateAmount) * bc.liquidateRewardRatio / Utils.MILLION;        
        burnAmount = Utils.minOf(burnAmount, _assets[_colletrallToken].sToken.balanceOf(_for));
        
         _assets[_colletrallToken].sToken.burn(_for, burnAmount);
         withdraw(_colletrallToken, _to, burnAmount, true);
    }

    function getAssetByID(uint id) public view override returns (ISToken, IDToken, bool){
        Types.Asset memory asset = _assets[underlyings[id]];
        return(
            asset.sToken,
            asset.dToken,
            asset.collateralable
        );
    }

    function totalSupplied(address _underlying) public view override returns (uint amount){
        address[] memory providersCopy = providers;
        for (uint i = 0; i < providersCopy.length; i++){
            amount += IProvider(providersCopy[i]).supplyOf(_underlying, address(this));
        }
    }

    function totalDebts(address _underlying) public view override returns (uint amount){
        address[] memory providersCopy = providers;
        for (uint i = 0; i < providersCopy.length; i++){
            amount += IProvider(providersCopy[i]).debtOf(_underlying, address(this));
        }
    }

    function borrowCap(address _underlying, address _account) public view override returns (uint){
        Types.BorrowConfig memory bc = config.borrowConfigs(_underlying);
        (uint collateralValue, uint debtsValue) = valueOf(_account, _underlying);
        return collateralValue * bc.maxLTV / Utils.MILLION - debtsValue;
    }

    function valueOf(address _account, address _quote) public view override returns (uint collateralValue, uint borrowingValue){
        uint userConfig = config.userDebtAndCollateral(_account);
        for (uint i = 0; i < underlyings.length; i++){
            if (UserAssetBitMap.isUsingAsCollateralOrBorrowing(userConfig, i)){
                if (UserAssetBitMap.isUsingAsCollateral(userConfig, i)){
                    (ISToken sToken,,) = getAssetByID(i);
                    collateralValue += priceOracle.valueOfAsset(
                        sToken.underlying(),
                        _quote, 
                        sToken.scaledBalanceOf(_account)
                    );
                }

                if (UserAssetBitMap.isBorrowing(userConfig, i)){
                    (, IDToken dToken,) = getAssetByID(i);
                    borrowingValue += priceOracle.valueOfAsset(
                        dToken.underlying(),
                        _quote, 
                        dToken.scaledDebtOf(_account)
                    );
                }
            }
        }
    }

    function withdrawCap(address _account, address _quote) public view override returns (uint amount){
        uint userConfig = config.userDebtAndCollateral(_account);
        if (UserAssetBitMap.isUsingAsCollateral(userConfig, _assets[_quote].index)){
            uint collateralInUse;
            uint totalCollateral;
            address[] memory underlyingsCache = underlyings;
            for (uint i = 0; i < underlyingsCache.length; i++){
                Types.Asset memory asset = _assets[underlyingsCache[i]];
                if (UserAssetBitMap.isBorrowing(userConfig, asset.index)){
                    uint borrowingValue = priceOracle.valueOfAsset(
                        underlyingsCache[i],
                        _quote,
                        asset.dToken.scaledDebtOf(_account)
                    );

                    Types.BorrowConfig memory bc = config.borrowConfigs(underlyingsCache[i]);
                    collateralInUse += borrowingValue * Utils.MILLION / bc.maxLTV;
                }

                if (UserAssetBitMap.isUsingAsCollateral(userConfig, asset.index)){
                    totalCollateral += priceOracle.valueOfAsset(
                        underlyingsCache[i],
                        _quote, 
                        asset.sToken.scaledBalanceOf(_account)
                    );
                }
            }

            return totalCollateral > collateralInUse ? totalCollateral - collateralInUse : 0;
        }else{
            return Utils.MAX_UINT;
        }
    }

    function assets(address _underlying) external view override returns (Types.Asset memory){
        return _assets[_underlying];
    }

    function getProviders() external view override returns (address[] memory){
        return providers;
    }

    function claimRewardToken(address _provider, address _to, address _underlying) external returns (uint amount){
        Types.ProviderData memory data = IProvider(_provider).getClaimRewardData(_underlying);
        Utils.lowLevelCall(data.target, data.encodedData, 0);

        address rewardToken;
        bytes memory params;
        (params, rewardToken, amount) = IProvider(_provider).getAmountToClaim(_underlying, userShare(msg.sender, _assets[_underlying]), rewardData[_to][_provider][_underlying]);

        rewardData[_to][_provider][_underlying] = params;
        TransferHelper.transfer(rewardToken, _to, Utils.minOf(amount, TransferHelper.balanceOf(rewardToken, address(this))));
    }

    function userShare(address _account, Types.Asset memory _asset) internal view returns (Types.UserShare memory){
        return Types.UserShare(
            _asset.sToken.balanceOf(_account),
            _asset.sToken.totalSupply(),
            _asset.dToken.balanceOf(_account),
            _asset.dToken.totalSupply()
        );
    }
}