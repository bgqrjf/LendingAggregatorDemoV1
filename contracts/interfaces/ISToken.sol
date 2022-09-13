// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/Types.sol";

interface ISToken is IERC20{
    function mint(address _account, uint _amountOfUnderlying, uint _totalUnderlying) external returns (uint);
    function burn(address _account, uint _amountOfUnderlying, uint _totalUnderlying) external returns (uint);

    function scaledBalanceOf(address _account) external view returns (uint);
    function scaledAmount(uint _amount) external view returns (uint);
    function scaledTotalSupply() external view returns (uint);

    // external state-getters
    function underlying() external view returns(address);
    function userShare(address _account) external view returns (Types.UserShare memory share);
}