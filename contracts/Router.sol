// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProvider.sol";
import "./interfaces/IPriceOracleGetter.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/Utils.sol";
import "./libraries/UserAssetBitMap.sol";

contract Router is IRouter, Ownable{
    address immutable public override ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IFactory public factory;
    IConfig public config;
    IPriceOracleGetter public priceOracle;
    IStrategy public strategy;
    ITreasury public treasury;

    address[] public underlyings;
    address[] public providers;

    mapping(address => Types.Asset) private _assets;

    // mapping(token address => asset Index)
    mapping(address => uint) public assetIndex;

    constructor(address[] memory _providers, address _priceOracle, address _strategy, address _factory, uint _treasuryRatio){
        factory = IFactory(_factory);
        priceOracle = IPriceOracleGetter(_priceOracle);
        strategy = IStrategy(_strategy);

        config = IConfig(factory.newConfig(_treasuryRatio));
        treasury = ITreasury(factory.newTreasury());
        providers = _providers;
    }

    receive() external payable {}

    function addAsset(Types.NewAssetParams memory _newAsset) external override onlyOwner returns (Types.Asset memory asset){
        uint8 underlyingCount = uint8(underlyings.length);
        require(underlyingCount < UserAssetBitMap.MAX_RESERVES_COUNT, "Router: asset list full");
        underlyings.push(_newAsset.underlying);

        asset = factory.newAsset(_newAsset, underlyingCount);
        _assets[_newAsset.underlying] = asset;
        config.setBorrowConfig(_newAsset.underlying, _newAsset.borrowConfig);
    }

    function updateConfig(address _config) external override onlyOwner{
        config = IConfig(_config);
    }
    
    function updateFactory(address _factory) external override onlyOwner{
        factory = IFactory(_factory);
    }

    function updateTreasury(address _treasury) external override onlyOwner{
        treasury = ITreasury(_treasury);
    }

    function addProvider(address _provider) external override onlyOwner{
        providers.push(_provider);
    }

    function removeProvider(uint _providerIndex, address _provider) external override onlyOwner{
        address[] memory providersCached = providers;
        require(providersCached[_providerIndex] == _provider, "Router: wrong index");
        require(providersCached.length > 1, "Router: at least 1 provider is required");
        providers[_providerIndex] = providersCached[providersCached.length - 1];
        providers.pop();

        address[] memory underlyingCached = underlyings;
        for (uint i = 0; i < underlyingCached.length; i++){
            IProvider(_provider).withdrawAll(underlyingCached[i]);
            supply(underlyingCached[i], address(0), false);
        }
    } 

    function updatePriceOracle(address _priceOracle) external override onlyOwner{
        priceOracle = IPriceOracleGetter(_priceOracle); 
    }

    function updateStrategy(address _strategy) external override onlyOwner{
        strategy = IStrategy(_strategy);
    }

    // use reentry guard
    function supply(address _underlying, address _to, bool _colletralable) public override returns (uint sTokenAmount){
        Types.Asset memory asset = _assets[_underlying];
        address[] memory supplyTo = providers;
        uint amount = TransferHelper.balanceOf(_underlying, address(this));
        uint sTokenSupply = asset.sToken.totalSupply();
        uint uTokenSupplied = totalSupplied(_underlying);

        // not mint sToken if _to == address(0)
        if (_to != address(0)){
            // update states
            sTokenAmount = amount * sTokenSupply / uTokenSupplied;
            asset.sToken.mint(_to, sTokenAmount);
            _assets[_underlying].sReserve = asset.sToken.totalSupply();
            config.setUsingAsCollateral(_to, asset.index, _colletralable);
        }

        // supply to provider
        amount = supplyToTreasury(_underlying, amount, uTokenSupplied);
        uint[] memory amounts = strategy.getSupplyStrategy(providers, _underlying, amount);
        for (uint i = 0; i < supplyTo.length - 1; i++){
            uint amountToSupply = Utils.minOf(amounts[i], amount);
            if (amountToSupply > 0){
                Utils.delegateCall(supplyTo[i], abi.encodeWithSelector(IProvider.supply.selector, _underlying, amountToSupply));
                amount -= amountToSupply;
            }
        }

        Utils.delegateCall(
            supplyTo[supplyTo.length - 1], 
            abi.encodeWithSelector(
                IProvider.supply.selector, 
                _underlying,
                TransferHelper.balanceOf(_underlying, address(this))
            )
        );
    }

    // only validated underlying tokens
    function withdraw(address _underlying, address _to, bool _colletralable) public override {
        Types.Asset memory asset = _assets[_underlying];
        address[] memory withdrawFrom = providers;
        uint sTokenSupply = asset.sToken.totalSupply();
        uint uTokenSupplied = totalSupplied(_underlying);

        // update states
        _assets[_underlying].sReserve = sTokenSupply;

        uint amount = withdrawFromTreasury(_underlying, (asset.sReserve - sTokenSupply) * uTokenSupplied / asset.sReserve);
        uint[] memory amounts = strategy.getWithdrawStrategy(withdrawFrom, _underlying, amount);
        for (uint i = 0; i < withdrawFrom.length - 1; i++){
            Utils.delegateCall(withdrawFrom[i], abi.encodeWithSelector(IProvider.withdraw.selector, _underlying, amounts[i]));
        }

        Utils.delegateCall(
            withdrawFrom[withdrawFrom.length - 1], 
            abi.encodeWithSelector(
                IProvider.withdraw.selector, 
                _underlying,
                amount - TransferHelper.balanceOf(_underlying, address(this))
            )
        );

        config.setUsingAsCollateral(_to, asset.index, _colletralable);

        TransferHelper.transferERC20(_underlying, _to, amount);
    }

    function borrow(address _underlying, address _to) public override returns (uint amount){
        Types.Asset memory asset = _assets[_underlying];
        address[] memory borrowFrom = providers;
        uint dTokenSupply = asset.dToken.totalSupply();
        uint debts = totalDebts(_underlying);
        _assets[_underlying].dReserve = asset.dToken.totalSupply();

        amount = (dTokenSupply - asset.dReserve) * debts / asset.dReserve;

        require(amount > 0, "Router: no borrow amount");
        config.setBorrowing(_to, asset.index, true);

        uint[] memory amounts = strategy.getBorrowStrategy(borrowFrom, _underlying, amount);

        for (uint i = 0; i < borrowFrom.length - 1; i++){
            Utils.delegateCall(borrowFrom[i], abi.encodeWithSelector(IProvider.borrow.selector, _underlying, amounts[i]));
        }

        Utils.delegateCall(
            borrowFrom[borrowFrom.length - 1],
            abi.encodeWithSelector(
                IProvider.borrow.selector, 
                _underlying,
                amount - TransferHelper.balanceOf(_underlying, address(this))
            )
        );

        TransferHelper.transferERC20(_underlying, _to, amount);
    }

    function repay(address _underlying, address _for) public override returns (uint amount){
        Types.Asset memory asset = _assets[_underlying];
        address[] memory repayTo = providers;
        uint dTokenSupply = asset.dToken.totalSupply();
        uint debts = totalDebts(_underlying);

        amount = Utils.minOf(
            TransferHelper.balanceOf(_underlying, address(this)) * dTokenSupply / debts, 
            asset.dToken.balanceOf(_for)
        );

        uint[] memory amounts = strategy.getRepayStrategy(repayTo, _underlying, amount * debts/ dTokenSupply);
        for (uint i = 0; i < repayTo.length - 1; i++){
            uint amountToRepay = Utils.minOf(amounts[i], amount);
            if (amountToRepay > 0){
                Utils.delegateCall(repayTo[i], abi.encodeWithSelector(IProvider.repay.selector, _underlying, amountToRepay));
                amount -= amountToRepay;
            }
        }

        Utils.delegateCall(
            repayTo[repayTo.length - 1], 
            abi.encodeWithSelector(
                IProvider.repay.selector, 
                _underlying,
                TransferHelper.balanceOf(_underlying, address(this))
            )
        );

        // update states
        asset.dToken.burn(_for, amount);
        _assets[_underlying].sReserve = asset.sToken.totalSupply();

        if (asset.dToken.balanceOf(_for) == 0){
            config.setBorrowing(_for, asset.index, false);
        }
    }

    function liquidate(
        address _debtToken, 
        address _colletrallToken, 
        address _for, 
        address _to
    ) external override returns (uint liquidateAmount, uint burnAmount){
        Types.BorrowConfig memory bc = config.borrowConfigs(_debtToken);
        (uint collateralValue, uint debtsValue) = valueOf(_for, _debtToken);

        require(debtsValue * Utils.MILLION / collateralValue > bc.liquidateLTV, "Router: sufficient collateral");

        liquidateAmount = repay(_debtToken, _for);

        require(liquidateAmount <=  debtsValue * bc.maxLiquidateRatio / Utils.MILLION, "Router: Exceed Liquidate Cap");

        burnAmount = priceOracle.valueOfAsset(_debtToken, _colletrallToken, liquidateAmount) * bc.liquidateRewardRatio / Utils.MILLION;
        _assets[_colletrallToken].sToken.liquidate(_for, _to, burnAmount);
    }

    function getAssetByID(uint id) public view override returns (ISToken, IDToken, bool, uint, uint){
        Types.Asset memory asset = _assets[underlyings[id]];
        return(
            asset.sToken,
            asset.dToken,
            asset.collateralable,
            asset.sReserve,
            asset.dReserve
        );
    }

    function totalSupplied(address _underlying) public view override returns (uint amount){
        address[] memory providersCopy = providers;
        for (uint i = 0; i < providersCopy.length; i++){
            amount += IProvider(providersCopy[i]).supplyOf(_underlying);
        }
        amount += TransferHelper.balanceOf(_underlying, address(treasury));
    }

    function totalDebts(address _underlying) public view override returns (uint amount){
        address[] memory providersCopy = providers;
        for (uint i = 0; i < providersCopy.length; i++){
            amount += IProvider(providersCopy[i]).debtOf(_underlying);
        }
    }

    function borrowCap(address _underlying, address _account) external view override returns (uint){
        Types.BorrowConfig memory bc = config.borrowConfigs(_underlying);
        (uint collateralValue, uint debtsValue) = valueOf(_account, _underlying);
        return collateralValue * bc.maxLTV / Utils.MILLION - debtsValue;
    }

    function valueOf(address _account, address _quote) public view override returns (uint collateralValue, uint borrowingValue){
        uint userConfig = config.userDebtAndCollateral(_account);
        for (uint i = 0; i < underlyings.length; i++){
            if (UserAssetBitMap.isUsingAsCollateralOrBorrowing(userConfig, i)){
                if (UserAssetBitMap.isUsingAsCollateral(userConfig, i)){
                    (ISToken sToken,,,,) = getAssetByID(i);
                    collateralValue += priceOracle.valueOfAsset(
                        sToken.underlying(),
                        _quote, 
                        sToken.scaledBalanceOf(_account)
                    );
                }

                if (UserAssetBitMap.isBorrowing(userConfig, i)){
                    (, IDToken dToken,,,) = getAssetByID(i);
                    borrowingValue += priceOracle.valueOfAsset(
                        dToken.underlying(),
                        _quote, 
                        dToken.scaledDebtOf(_account)
                    );
                }
            }
        }
    }

    function assets(address _underlying) external view override returns (Types.Asset memory){
        return _assets[_underlying];
    }

    // transfer to treasury
    function supplyToTreasury(address _underlying, uint _amount, uint _totalSupplied) internal returns (uint amountLeft){
        uint amountDesired = _totalSupplied * config.treasuryRatio() / Utils.MILLION;
        uint balance = TransferHelper.balanceOf(_underlying, address(treasury));
        if (balance < amountDesired){
            uint amountToTreasury = Utils.minOf(_amount,  amountDesired - balance);
            TransferHelper.transferERC20(_underlying, address(treasury), amountToTreasury);
            amountLeft = _amount - amountToTreasury;
        }
    }

    function withdrawFromTreasury(address _underlying, uint _amount) internal returns (uint amountLeft){
        uint amountFromTreasury = Utils.minOf(TransferHelper.balanceOf(_underlying, address(treasury)), _amount);
        treasury.withdraw(_underlying, amountFromTreasury);
        amountLeft = _amount - amountFromTreasury;
    }

}
