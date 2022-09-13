// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IProtocol.sol";
import "./IPriceOracle.sol";
import "./IFactory.sol";
import "./IConfig.sol";
import "./IWETH.sol";

import "../libraries/Types.sol";

interface IRouter{
    function addAsset(Types.NewAssetParams memory _newAsset) external returns (Types.Asset memory asset);
    function updateConfig(address _config) external;
    function updateFactory(address _factory) external;
    function addProtocol(IProtocol _protocol) external;
    function removeProtocol(uint _protocolIndex, address _protocol) external;
    function updatePriceOracle(address _priceOracle) external;
    function updateStrategy(address _strategy) external;

    // function supply(Types.SupplyParams memory params) external payable;
    // function redeem(Types.SupplyParams memory _params) external;
    function borrow(address _underlying, address _to, uint _borrowAmount) external returns (uint amount);
    function repay(address _underlying, address _for) external returns (uint amount);
    function liquidate(
        address _debtToken, 
        address _colletrallToken, 
        address _for, 
        address _to
    ) external returns (uint liquidateAmount, uint burnAmount);
    function getAssetByID(uint id) external view returns (ISToken, IDToken, bool);
    function totalSupplied(address _underlying) external view returns (uint[] memory amounts, uint amount);
    function totalDebts(address _underlying) external view returns (uint amount);
    function borrowCap(address _underlying, address _account) external view returns (uint);
    function withdrawCap(address _account, address _quote) external view returns (uint amount);
    function valueOf(address _account, address _quote) external view returns (uint collateralValue, uint borrowingValue);
    function getProtocols() external view returns (IProtocol[] memory);

    // external state-getters
    function assets(address) external view returns(Types.Asset memory);
}
