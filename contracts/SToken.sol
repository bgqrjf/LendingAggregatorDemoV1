// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/ISToken.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

// Supply Token
// owner is router
contract SToken is ISToken, OwnableUpgradeable, ERC20Upgradeable {
    using Math for uint256;
    address public override underlying;

    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __Ownable_init();
        __ERC20_init(_name, _symbol);

        underlying = _underlying;
    }

    function mint(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyOwner returns (uint256 amount) {
        uint256 totalSupply = totalSupply();
        amount = totalSupply > 0
            ? (_amountOfUnderlying * totalSupply) / _totalUnderlying
            : _amountOfUnderlying;
        _mint(_account, amount);
    }

    function burn(
        address _from,
        bool _notLiquidate,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyOwner returns (uint256 amountOfUnderlying) {
        amountOfUnderlying = Math.min(
            _amountOfUnderlying,
            scaledAmount(balanceOf(_from), _totalUnderlying)
        );
        uint256 amount = unscaledAmount(amountOfUnderlying, _totalUnderlying);

        _burn(_from, amount);

        if (_notLiquidate) {
            _validatePosition(_from);
        }

        return scaledAmount(amount, _totalUnderlying);
    }

    function scaledAmount(
        uint256 _amount,
        uint256 _totalSupplied
    ) public view override returns (uint256) {
        uint totalSupply = totalSupply();
        return totalSupply > 0 ? (_amount * _totalSupplied) / totalSupply : 0;
    }

    function unscaledAmount(
        uint256 _amount,
        uint256 _totalSupplied
    ) public view override returns (uint256) {
        uint256 totalSupply = totalSupply();
        return
            _totalSupplied > 0
                ? (_amount * totalSupply).ceilDiv(_totalSupplied)
                : 0;
    }

    function scaledBalanceOf(
        address _account
    ) external view override returns (uint256) {
        return
            scaledAmount(
                balanceOf(_account),
                IRouter(owner()).totalSupplied(underlying)
            );
    }

    function scaledTotalSupply() public view override returns (uint256 amount) {
        return IRouter(owner()).totalSupplied(underlying);
    }

    function _afterTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal view override {
        _amount;
        _to;
        if (msg.sender != owner()) {
            _validatePosition(_from);
        }
    }

    function _validatePosition(address _from) internal view {
        if (IRouter(owner()).isUsingAsCollateral(underlying, _from)) {
            (bool isHealthy, , ) = IRouter(owner()).isPoisitionHealthy(
                underlying,
                _from
            );
            require(isHealthy, "SToken: insufficient collateral");
        }
    }
}
