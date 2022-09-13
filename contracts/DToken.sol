// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IDToken.sol";
import "./Router.sol";

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
    
    Router public immutable router;
    address public override underlying;

    event Mint(address indexed account, uint amount);
    event Burn(address indexed account, uint amount);

    modifier onlyRouter{
        require(msg.sender == address(router), "DToken: OnlyRouter");
        _;
    }

    constructor(address _router, address _underlying, string memory _name, string memory _symbol){
        router = Router(payable(_router));
        underlying = _underlying;
        name = _name;
        symbol = _symbol;
    }


    function mint(address _account, uint _amountOfUnderlying, uint _totalUnderlying) external override onlyRouter returns (uint amount){
        amount = totalSupply > 0 ? _amountOfUnderlying * totalSupply / _totalUnderlying : _amountOfUnderlying;
        _mint(_account, amount);
    }

    function burn(address _account, uint _amountOfUnderlying, uint _totalUnderlying) external override onlyRouter returns (uint amount){
        amount = totalSupply > 0 ? _amountOfUnderlying * totalSupply / _totalUnderlying : _amountOfUnderlying;
        _burn(_account, amount);
    }
   
    function scaledDebtOf(address _account) public view override returns (uint){
        return scaledAmount(balanceOf[_account]);
    }

    function scaledAmount(uint _amount) public view override returns (uint){
        (, uint totalBorrowed) = router.protocols().totalBorrowed(underlying);
        return totalSupply > 0 ? (_amount * totalBorrowed).divCeil(totalSupply) : _amount;
    }

    function totalDebt() public view override returns(uint totalBorrowed){
        (, totalBorrowed) = router.protocols().totalBorrowed(underlying);
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