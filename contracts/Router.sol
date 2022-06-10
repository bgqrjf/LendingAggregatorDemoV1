// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProvider.sol";
import "./interfaces/IPriceOracleGetter.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/Utils.sol";
import "./libraries/UserAssetBitMap.sol";

import "./Types.sol";
import "./Config.sol";
import "./SToken.sol";
import "./DToken.sol";
import "./Treasury.sol";
import "./Strategy.sol";

contract Router is Ownable{
    // constant
    address immutable public ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint immutable public MAX_APY = 100000;
    
    IPriceOracleGetter public priceOracle;
    Config public config;
    address[] public underlyings;
    address[] private providers;
    Treasury private treasury;
    Strategy public strategy;

    mapping(address => Types.Asset) public assets;

    // mapping(token address => asset Index)
    mapping(address => uint) public assetIndex;

    constructor(address[] memory _providers, address _priceOracle, address _strategy, uint _treasuryRatio){
        config = new Config(msg.sender, _treasuryRatio);
        providers = _providers;
        priceOracle = IPriceOracleGetter(_priceOracle);
        treasury = new Treasury();
        strategy = Strategy(_strategy);
    }

    receive() external payable {}

    function addAsset(Types.NewAssetParams memory _newAsset) external onlyOwner returns (Types.Asset memory asset){
        require(underlyings.length < UserAssetBitMap.MAX_RESERVES_COUNT, "Router: asset list full");
        underlyings.push(_newAsset.underlying);

        asset = Types.Asset(
            uint8(underlyings.length),
            new SToken(_newAsset.underlying, _newAsset.sTokenName, _newAsset.sTokenSymbol),
            new DToken(_newAsset.underlying, _newAsset.dTokenName, _newAsset.dTokenSymbol),
            _newAsset.collateralable,
            0,
            0
        );

        assets[_newAsset.underlying] = asset;
        config.setBorrowConfig(_newAsset.underlying, _newAsset.borrowConfig);
    }

    // use reentry guard
    function supply(address _underlying, address _to, bool _colletralable) public returns (uint sTokenAmount){
        Types.Asset memory asset = assets[_underlying];
        address[] memory supplyTo = providers;
        uint amount = TransferHelper.balanceOf(_underlying, address(this));
        uint sTokenSupply = asset.sToken.totalSupply();
        uint uTokenSupplied = totalSupplied(_underlying);

        // update states
        sTokenAmount = amount * sTokenSupply / uTokenSupplied;
        asset.sToken.mint(_to, sTokenAmount);
        assets[_underlying].sReserve += asset.sToken.totalSupply();

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

        config.setUsingAsCollateral(_to, asset.index, _colletralable);
    }

    // only validated underlying tokens
    function withdraw(address _underlying, address _to, bool _colletralable) public{
        Types.Asset memory asset = assets[_underlying];
        address[] memory withdrawFrom = providers;
        uint sTokenSupply = asset.sToken.totalSupply();
        uint uTokenSupplied = totalSupplied(_underlying);

        // update states
        assets[_underlying].sReserve = sTokenSupply;

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

    function borrow(address _underlying, address _to) public returns (uint amount){
        Types.Asset memory asset = assets[_underlying];
        address[] memory borrowFrom = providers;
        uint dTokenSupply = asset.dToken.totalSupply();
        uint debts = totalDebts(_underlying);
        assets[_underlying].dReserve = asset.dToken.totalSupply();

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

    function repay(address _underlying, address _for) public returns (uint amount){
        Types.Asset memory asset = assets[_underlying];
        address[] memory repayTo = providers;
        uint dTokenSupply = asset.dToken.totalSupply();
        uint debts = totalDebts(_underlying);

        amount = Utils.minOf(
            TransferHelper.balanceOf(_underlying, address(this)) * dTokenSupply / debts, 
            asset.dToken.balanceOf(_for)
        );

        // supply to provider
        uint[] memory amounts = strategy.getRepayStrategy(repayTo, _underlying, amount * debts/ dTokenSupply);
        for (uint i = 0; i < repayTo.length - 1; i++){
            Utils.delegateCall(repayTo[i], abi.encodeWithSelector(IProvider.repay.selector, _underlying, amounts[i]));
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
        assets[_underlying].sReserve = asset.sToken.totalSupply();

        if (asset.dToken.balanceOf(_for) == 0){
            config.setBorrowing(_for, asset.index, false);
        }
    }

    function liquidate(
        address _debtToken, 
        address _colletrallToken, 
        address _for, 
        address _to
    ) external returns (uint liquidateAmount, uint burnAmount){
        (,uint liquidateLTV, uint maxLiquidateRatio, uint liquidateReward) = config.borrowConfigs(_debtToken);
        (uint collateralValue, uint debtsValue) = valueOf(_for, _debtToken);

        require(debtsValue * Utils.MILLION / collateralValue > liquidateLTV, "Router: sufficient collateral");

        liquidateAmount = repay(_debtToken, _for);

        require(liquidateAmount <=  debtsValue * maxLiquidateRatio / Utils.MILLION, "Router: Exceed Liquidate Cap");

        burnAmount = priceOracle.valueOfAsset(_debtToken, _colletrallToken, liquidateAmount) * liquidateReward / Utils.MILLION;
        assets[_colletrallToken].sToken.liquidate(_for, _to, burnAmount);
    }

    function getAssetByID(uint id) public view returns (SToken, DToken, bool, uint, uint){
        Types.Asset memory asset = assets[underlyings[id]];
        return(
            asset.sToken,
            asset.dToken,
            asset.collateralable,
            asset.sReserve,
            asset.dReserve
        );
    }

    function totalSupplied(address _underlying) public view returns (uint amount){
        address[] memory providersCopy = providers;
        for (uint i = 0; i < providersCopy.length; i++){
            amount += IProvider(providersCopy[i]).supplyOf(_underlying);
        }
        amount += TransferHelper.balanceOf(_underlying, address(treasury));
    }

    function totalDebts(address _underlying) public view returns (uint amount){
        address[] memory providersCopy = providers;
        for (uint i = 0; i < providersCopy.length; i++){
            amount += IProvider(providersCopy[i]).debtOf(_underlying);
        }
    }

    function borrowCap(address _underlying, address _account) public view returns (uint){
        (uint maxLTV,,,) = config.borrowConfigs(_underlying);
        (uint collateralValue, uint debtsValue) = valueOf(_account, _underlying);
        return collateralValue * maxLTV / Utils.MILLION - debtsValue;
    }

    function valueOf(address _account, address _quote) public view returns (uint collateralValue, uint borrowingValue){
        uint userConfig = config.userDebtAndCollateral(_account);
        for (uint i = 0; i < underlyings.length; i++){
            if (UserAssetBitMap.isUsingAsCollateralOrBorrowing(userConfig, i)){
                if (UserAssetBitMap.isUsingAsCollateral(userConfig, i)){
                    (SToken sToken,,,,) = getAssetByID(i);
                    collateralValue += priceOracle.valueOfAsset(
                        sToken.underlying(),
                        _quote, 
                        sToken.scaledBalanceOf(_account)
                    );
                }

                if (UserAssetBitMap.isBorrowing(userConfig, i)){
                    (, DToken dToken,,,) = getAssetByID(i);
                    borrowingValue += priceOracle.valueOfAsset(
                        dToken.underlying(),
                        _quote, 
                        dToken.scaledDebtOf(_account)
                    );
                }
            }
        }
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
