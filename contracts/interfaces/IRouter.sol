// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IProtocol.sol";
import "./IPriceOracle.sol";
import "./IFactory.sol";
import "./IConfig.sol";
import "./IWETH.sol";

import "../libraries/Types.sol";

interface IRouter {
    function addAsset(Types.NewAssetParams memory _newAsset)
        external
        returns (Types.Asset memory asset);

    function updateConfig(address _config) external;

    function updateFactory(address _factory) external;

    function addProtocol(IProtocol _protocol) external;

    function removeProtocol(uint256 _protocolIndex, address _protocol) external;

    function updatePriceOracle(address _priceOracle) external;

    function updateStrategy(address _strategy) external;

    // function supply(Types.SupplyParams memory params) external payable;
    // function redeem(Types.SupplyParams memory _params) external;
    function borrow(
        address _underlying,
        address _to,
        uint256 _borrowAmount
    ) external returns (uint256 amount);

    function repay(address _underlying, address _for)
        external
        returns (uint256 amount);

    function liquidate(
        address _debtToken,
        address _colletrallToken,
        address _for,
        address _to
    ) external returns (uint256 liquidateAmount, uint256 burnAmount);

    function getAssetByID(uint256 id)
        external
        view
        returns (
            ISToken,
            IDToken,
            bool
        );

    function totalSupplied(address _underlying)
        external
        view
        returns (uint256[] memory amounts, uint256 amount);

    function totalDebts(address _underlying)
        external
        view
        returns (uint256 amount);

    function borrowCap(address _underlying, address _account)
        external
        view
        returns (uint256);

    function withdrawCap(address _account, address _quote)
        external
        view
        returns (uint256 amount);

    function valueOf(address _account, address _quote)
        external
        view
        returns (uint256 collateralValue, uint256 borrowingValue);

    function getProtocols() external view returns (IProtocol[] memory);

    // external state-getters
    function assets(address) external view returns (Types.Asset memory);
}
