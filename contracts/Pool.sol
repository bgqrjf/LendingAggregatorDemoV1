// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/Utils.sol";
import "./libraries/Types.sol";

import "./Router.sol";

contract Pool{
    /// @param amount is amount of underlying tokens to liquidate
    struct LiquidateArgs{
        address debtAsset;
        address collateralAsset;
        address borrower;
        address to;
        uint amount;
    }

    address immutable public ETH;

    address payable immutable public router;

    constructor(
        address payable _router
    ){
        router = _router;
        ETH = Router(router).ETH();
    }

    receive() external payable{
        // depositETH(msg.sender);
    }

    function deposit(address _token, address _to, uint _amount, bool _colletralable) external returns (uint sTokenAmount) {
        TransferHelper.transferFrom(_token, msg.sender, router, _amount);
        sTokenAmount = Router(router).supply(_token, _to, _colletralable);
    }

    function repay(address _token, address _for, uint _amount) public returns (uint actualAmount){
       Types.Asset memory asset = Router(router).assets(_token);
        uint amount = _amount * asset.dToken.totalSupply() / Router(router).totalDebts(_token);
        TransferHelper.transferFrom(_token, msg.sender, router, amount);
        actualAmount = Router(router).repay(_token, _for);
    }

    function liquidate(LiquidateArgs memory _param) external returns (uint actualAmount, uint burnedAmount){
        Types.Asset memory asset = Router(router).assets(_param.debtAsset);
        uint amount = _param.amount *asset.dToken.totalSupply() / Router(router).totalDebts(_param.debtAsset);
        TransferHelper.transferFrom(_param.debtAsset, msg.sender, router, amount);
        (actualAmount, burnedAmount) = Router(router).liquidate(_param.debtAsset, _param.collateralAsset, _param.to, msg.sender);
    }
}