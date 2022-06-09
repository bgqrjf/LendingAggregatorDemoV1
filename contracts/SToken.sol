// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/TransferHelper.sol";

import "./Router.sol";

// Supply Token
contract SToken is ERC20{
    address payable public router;
    address public underlying;

    modifier onlyRouter{
        require(msg.sender == router, "SToken: OnlyRouter");
        _;
    }

    constructor(address _underlying, string memory name, string memory symbol) ERC20 (name, symbol){
        router = payable(msg.sender);
        underlying = _underlying;
    }

    function mint(address _account, uint amount) external onlyRouter{
        _mint(_account, amount);
    }

    function withdraw(address _to, uint _amount, bool _colletralable) external{
        _withdraw(msg.sender, _to, _amount, _colletralable);
    }

    function liquidate(address _for, address _to, uint _amount) external onlyRouter{
        uint balance = balanceOf(_for);
        if (_amount > balance){
            _amount = balance;
        }

        _withdraw(_for, _to, _amount, true);
    }

    function _withdraw(address _from, address _to, uint _amount, bool _colletralable) internal {
        _burn(_from, _amount);
        Router(router).withdraw(underlying, _to, _colletralable);
    }

    function scaledBalanceOf(address _account) public view returns (uint){
        return scaledAmount(balanceOf(_account));
    }

    function scaledAmount(uint _amount) public view returns (uint){
        return _amount *  Router(router).totalSupplied(underlying) / totalSupply();
    }
}