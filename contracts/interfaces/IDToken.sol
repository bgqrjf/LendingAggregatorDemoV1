// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IDToken {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event AccFeeUpdated(uint256 newAccFee, uint256 newIndex);
    event UserFeeIndexUpdated(address account, uint256 newIndex);
    event CollectedFeeUpdated(uint256 collectedFee);

    function initialize(
        address _underlying,
        address _rewards,
        string memory _name,
        string memory _symbol,
        uint256 feeRate
    ) external;

    function mint(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying,
        uint256 _newInterest
    ) external returns (uint256 amount);

    function burn(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying,
        uint256 _newInterest
    ) external returns (uint256 amountOfUnderlying, uint256 newCollectedFee);

    function claimRewards(address _account) external returns (uint256);

    function updateNewFee(
        uint256 _newInterest
    ) external returns (uint256 uncollectedFee);

    function scaledDebtOf(address _account) external view returns (uint256);

    function calculateFee(
        uint256 _newInterest
    ) external view returns (uint256 newAccFee, uint256 newFeeIndex);

    function scaledAmount(
        uint256 _amount,
        uint256 scaledAmount
    ) external view returns (uint256);

    // external state-getters
    function underlying() external view returns (address);

    function feeRate() external view returns (uint256);

    function accFee() external view returns (uint256);

    function collectedFee() external view returns (uint256);

    function feeIndex() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function feeIndexOf(address account) external view returns (uint256);
}
