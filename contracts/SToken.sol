// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/ISToken.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./libraries/TransferHelper.sol";

// Supply Token
// owner is router
contract SToken is ISToken, OwnableUpgradeable, ERC20Upgradeable {
    address public override underlying;

    function initialize(
        address _underlying,
        string memory name,
        string memory symbol
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name, symbol);

        underlying = _underlying;
    }

    function mint(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyOwner returns (uint256 amount) {
        amount = totalSupply() > 0
            ? (_amountOfUnderlying * totalSupply()) / _totalUnderlying
            : _amountOfUnderlying;
        _mint(_account, amount);
    }

    function burn(
        address _from,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyOwner returns (uint256 amount) {
        amount = totalSupply() > 0
            ? (_amountOfUnderlying * totalSupply()) / _totalUnderlying
            : _amountOfUnderlying;
        _burn(_from, amount);
    }

    function scaledBalanceOf(address _account)
        public
        view
        override
        returns (uint256)
    {
        return scaledAmount(balanceOf(_account));
    }

    function scaledAmount(uint256 _amount)
        public
        view
        override
        returns (uint256)
    {
        uint256 totalSupply = totalSupply();
        uint256 totalSupplied = IRouter(owner()).totalSupplied(underlying);
        return totalSupply > 0 ? (_amount * totalSupplied) / totalSupply : 0;
    }

    function scaledTotalSupply() public view override returns (uint256 amount) {
        return IRouter(owner()).totalSupplied(underlying);
    }
}
