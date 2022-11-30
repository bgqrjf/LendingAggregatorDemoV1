// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IDToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol
    ) external;

    function mint(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external returns (uint256);

    function burn(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external returns (uint256);

    function scaledDebtOf(address _account) external view returns (uint256);

    function scaledAmount(uint256 _amount, uint256 scaledAmount)
        external
        view
        returns (uint256);

    // external state-getters
    function underlying() external view returns (address);

    function totalSupply() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}
