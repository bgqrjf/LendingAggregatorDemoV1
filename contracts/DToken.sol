// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/Math.sol";
import "./libraries/Utils.sol";

import "./Config.sol";
import "./Router.sol";
import "./SToken.sol";

// DebtTOken
contract DToken is ERC20{
    using Math for uint;

    address payable public router;
    address public underlying;

    modifier onlyRouter{
        require(msg.sender == router, "DToken: OnlyRouter");
        _;
    }

    constructor(address _underlying, string memory name, string memory symbol) ERC20 (name, symbol){
        router = payable(msg.sender);
        underlying = _underlying;
    }

    function borrow(address _to, uint _amount) external {
        require(_amount < Router(router).borrowCap(underlying, msg.sender), "DToken: insufficient collateral");
        uint dTokenAmount = _amount * totalSupply().divCeil(Router(router).totalDebts(underlying));

        _mint(msg.sender, dTokenAmount);
        Router(router).borrow(underlying, _to);
    }

    function burn(address _account, uint _amount) external onlyRouter {
        _burn(_account, _amount);
    }
   
    function scaledDebtOf(address _account) public view returns (uint){
        return scaledAmount(balanceOf(_account));
    }

    function scaledAmount(uint _amount) public view returns (uint){
        return _amount *  Router(router).totalSupplied(underlying).divCeil(totalSupply());
    }
}