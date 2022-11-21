// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IDToken.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./libraries/Math.sol";

// DebtToken
contract DToken is IDToken, OwnableUpgradeable {
    using Math for uint256;

    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    address public override underlying;
    mapping(address => uint256) public balanceOf;

    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __Ownable_init();

        underlying = _underlying;
        name = _name;
        symbol = _symbol;
    }

    function mint(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyOwner returns (uint256 amount) {
        uint256 totalSupplyCache = totalSupply;
        amount = totalSupplyCache > 0
            ? (_amountOfUnderlying * totalSupplyCache).divCeil(_totalUnderlying)
            : _amountOfUnderlying;
        _mint(_account, amount);
    }

    function burn(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyOwner returns (uint256 amount) {
        amount = _totalUnderlying > 0
            ? (_amountOfUnderlying * totalSupply).divCeil(_totalUnderlying)
            : _amountOfUnderlying;
        _burn(_account, amount);
    }

    function scaledDebtOf(address _account)
        public
        view
        override
        returns (uint256)
    {
        return
            scaledAmount(
                balanceOf[_account],
                IRouter(owner()).totalBorrowed(underlying)
            );
    }

    function scaledAmount(uint256 _amount, uint256 totalBorrowed)
        public
        view
        override
        returns (uint256)
    {
        return
            totalSupply > 0
                ? (_amount * totalBorrowed) / (totalSupply)
                : _amount;
    }

    function totalDebt() public view override returns (uint256 totalBorrowed) {
        return IRouter(owner()).totalBorrowed(underlying);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        totalSupply += amount;
        balanceOf[account] += amount;
        emit Mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = balanceOf[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            balanceOf[account] = accountBalance - amount;
        }
        totalSupply -= amount;

        emit Burn(account, amount);
    }
}
