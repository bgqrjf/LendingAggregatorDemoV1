// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20{
    uint8 private d;

    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol){
        d = _decimals;
    }

    function mint(address account, uint amount) external {
        _mint(account, amount * 10 ** decimals());
    }

    function burn(address account, uint amount) external {
        _burn(account, amount);
    }

    function decimals() public view override returns (uint8){
        return d;
    }
}
