// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDToken{
    function mint(address _account, uint _amountOfUnderlying, uint _totalUnderlying) external returns (uint);
    function burn(address _account, uint _amountOfUnderlying, uint _totalUnderlying) external returns (uint);

    function scaledDebtOf(address _account) external view returns (uint);
    function scaledAmount(uint _amount) external view returns (uint);

    // external state-getters
    function underlying() external view returns(address);
    
    function totalSupply() external view returns (uint);
    function totalDebt() external view returns(uint);

    function balanceOf(address account) external view returns (uint);
}