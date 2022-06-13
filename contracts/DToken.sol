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

    constructor(address _underlying, string memory name, string memory symbol) ERC20 (name, symbol){
        router = IRouter(payable(msg.sender));
        underlying = _underlying;
    }

    function borrow(address _to, uint _amount) external override{
        require(_amount < router.borrowCap(underlying, msg.sender), "DToken: insufficient collateral");
        uint dTokenAmount = _amount * totalSupply().divCeil(router.totalDebts(underlying));

        _mint(msg.sender, dTokenAmount);
        router.borrow(underlying, _to);
    }

    function burn(address _account, uint _amount) external override onlyRouter {
        _burn(_account, _amount);
    }
   
    function scaledDebtOf(address _account) public view override returns (uint){
        return scaledAmount(balanceOf(_account));
    }

    function scaledAmount(uint _amount) public view override returns (uint){
        return _amount *  router.totalSupplied(underlying).divCeil(totalSupply());
    }
}