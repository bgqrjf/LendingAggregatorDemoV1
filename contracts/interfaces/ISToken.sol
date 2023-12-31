// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISToken is IERC20{
    function mint(address _account, uint amount) external;
    function burn(address _from, uint _amount) external;
    function scaledBalanceOf(address _account) external view returns (uint);
    function scaledAmount(uint _amount) external view returns (uint);

    // external state-getters
    function underlying() external view returns(address);
}