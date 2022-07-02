// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/ISToken.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/TransferHelper.sol";

// Supply Token
contract SToken is ISToken, ERC20{
    IRouter public immutable router;
    address public override underlying;

    modifier onlyRouter{
        require(msg.sender == address(router), "SToken: OnlyRouter");
        _;
    }

    constructor(address _router, address _underlying, string memory name, string memory symbol) ERC20 (name, symbol){
        router = IRouter(payable(_router));
        underlying = _underlying;
    }

    function mint(address _account, uint amount) external override onlyRouter{
        _mint(_account, amount);
    }

    function withdraw(address _to, uint _amount, bool _colletralable) external override{
        require(router.withdrawCap(msg.sender, underlying) >= _amount, "SToken: not enough collateral");
        _withdraw(msg.sender, _to, _amount, _colletralable);
    }

    function liquidate(address _for, address _to, uint _amount) external override onlyRouter{
        uint balance = balanceOf(_for);
        if (_amount > balance){
            _amount = balance;
        }

        _withdraw(_for, _to, _amount, true);
    }

    function scaledBalanceOf(address _account) public view override returns (uint){
        return scaledAmount(balanceOf(_account));
    }

    function scaledAmount(uint _amount) public view override returns (uint){
        return _amount * router.totalSupplied(underlying) / totalSupply();
    }

    function _withdraw(address _from, address _to, uint _amount, bool _colletralable) internal {
        _burn(_from, _amount);
        router.withdraw(underlying, _from, _to, _colletralable);
    }
}