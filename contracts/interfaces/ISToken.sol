// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/Types.sol";

interface ISToken is IERC20 {
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

    function scaledBalanceOf(address _account) external view returns (uint256);

    function scaledAmount(uint256 _amount) external view returns (uint256);

    function scaledTotalSupply() external view returns (uint256);

    // external state-getters
    function underlying() external view returns (address);

    function userShare(address _account)
        external
        view
        returns (Types.UserShare memory share);
}
