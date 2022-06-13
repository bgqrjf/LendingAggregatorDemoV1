// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDToken is IERC20{
    function borrow(address _to, uint _amount) external;
    function burn(address _account, uint _amount) external;

    function scaledDebtOf(address _account) external view returns (uint);
    function scaledAmount(uint _amount) external view returns (uint);

    // external state-getters
    function underlying() external view returns(address);
}