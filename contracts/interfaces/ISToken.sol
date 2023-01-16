// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../libraries/internals/Types.sol";

interface ISToken is IERC20Upgradeable {
    function initialize(
        address _underlying,
        string memory name,
        string memory symbol
    ) external;

    function mint(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external returns (uint256);

    function burn(
        address _account,
        uint256 _amount,
        uint256 _totalUnderlying,
        uint256 _totalUncollectedFee
    ) external returns (uint256 amount, uint256 fee);

    function scaledBalanceOf(address _account) external view returns (uint256);

    function scaledAmount(uint256 _amount, uint256 scaledAmount)
        external
        view
        returns (uint256);

    function scaledTotalSupply() external view returns (uint256);

    function unscaledAmount(uint256 _amount, uint256 _totalSupplied)
        external
        view
        returns (uint256);

    // external state-getters
    function underlying() external view returns (address);
}
