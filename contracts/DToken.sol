// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IDToken.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/Math.sol";

// DebtTOken
contract DToken is IDToken, ERC20{
    using Math for uint;
    
    IRouter public immutable router;
    address public override underlying;

    modifier onlyRouter{
        require(msg.sender == address(router), "DToken: OnlyRouter");
        _;
    }

    constructor(address _router, address _underlying, string memory name, string memory symbol) ERC20 (name, symbol){
        router = IRouter(payable(_router));
        underlying = _underlying;
    }

    function mint(address _to, uint _amount) external override onlyRouter{
        _mint(_to, _amount);
    }

    function burn(address _account, uint _amount) external override onlyRouter {
        _burn(_account, _amount);
    }
   
    function scaledDebtOf(address _account) public view override returns (uint){
        return scaledAmount(balanceOf(_account));
    }

    function scaledAmount(uint _amount) public view override returns (uint){
        uint totalSupply = totalSupply();
        return totalSupply > 0 ? _amount * router.totalSupplied(underlying).divCeil(totalSupply) : _amount;
    }
}