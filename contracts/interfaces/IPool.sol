// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IPool{
    /// @param amount is amount of underlying tokens to liquidate
    struct LiquidateArgs{
        address debtAsset;
        address collateralAsset;
        address borrower;
        address to;
        uint amount;
    }

    receive() external payable;

    function router() external view returns (address payable);

    function supply(address _token, address _to, uint _amount, bool _colletralable) external returns (uint sTokenAmount);
    function supplyETH(address _to, bool _colletralable) external payable returns (uint sTokenAmount);
    function repay(address _token, address _for, uint _amount) external returns (uint actualAmount);
    function liquidate(LiquidateArgs memory _param) external returns (uint actualAmount, uint burnedAmount);
}