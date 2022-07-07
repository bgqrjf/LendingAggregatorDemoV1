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

    function burn(address _from, uint _amount) external override onlyRouter{
        _burn(_from, _amount);
    }

    function scaledBalanceOf(address _account) public view override returns (uint){
        return scaledAmount(balanceOf(_account));
    }

    function scaledAmount(uint _amount) public view override returns (uint){
        return _amount * router.totalSupplied(underlying) / totalSupply();
    }
}