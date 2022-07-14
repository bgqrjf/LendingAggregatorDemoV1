// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IDToken.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/Math.sol";

// DebtTOken
contract DToken is IDToken{
    using Math for uint;

    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint public totalSupply;
    mapping(address => uint) public balanceOf;
    
    IRouter public immutable router;
    address public override underlying;

    event Mint(address indexed account, uint amount);
    event Burn(address indexed account, uint amount);

    modifier onlyRouter{
        require(msg.sender == address(router), "DToken: OnlyRouter");
        _;
    }

    constructor(address _router, address _underlying, string memory _name, string memory _symbol){
        router = IRouter(payable(_router));
        underlying = _underlying;
        name = _name;
        symbol = _symbol;
    }

    function mint(address _to, uint _amount) external override onlyRouter{
        _mint(_to, _amount);
    }

    function burn(address _account, uint _amount) external override onlyRouter {
        _burn(_account, _amount);
    }
   
    function scaledDebtOf(address _account) public view override returns (uint){
        return scaledAmount(balanceOf[_account]);
    }

    function scaledAmount(uint _amount) public view override returns (uint){
        return totalSupply > 0 ? (_amount * router.totalDebts(underlying)).divCeil(totalSupply) : _amount;
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        totalSupply += amount;
        balanceOf[account] += amount;
        emit Mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
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