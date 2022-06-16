// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IPool.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/Utils.sol";
import "./libraries/Types.sol";

import "./Router.sol";

contract Pool is IPool{
    address payable immutable public override router;

    constructor(address payable _router){
        router = _router;
    }

    receive() external payable{
        supplyETH(msg.sender, true);
    }

    function supply(address _token, address _to, uint _amount, bool _colletralable) external override returns (uint sTokenAmount) {
        TransferHelper.transferFrom(_token, msg.sender, router, _amount);
        sTokenAmount = Router(router).supply(_token, _to, _colletralable);
    }

    function supplyETH(address _to, bool _colletralable) public payable override returns (uint sTokenAmount) {
        TransferHelper.transferETH(router, msg.value);
        sTokenAmount = Router(router).supply(TransferHelper.ETH, _to, _colletralable);
    }

    function repay(address _token, address _for, uint _amount) external returns (uint actualAmount){
       Types.Asset memory asset = Router(router).assets(_token);
        uint amount = _amount * asset.dToken.totalSupply() / Router(router).totalDebts(_token);
        TransferHelper.transferFrom(_token, msg.sender, router, amount);
        actualAmount = Router(router).repay(_token, _for);
    }

    function repayETH(address _for, uint _amount) external payable returns (uint actualAmount){
        Types.Asset memory asset = Router(router).assets(TransferHelper.ETH);
        uint amount = _amount * asset.dToken.totalSupply() / Router(router).totalDebts(TransferHelper.ETH);
        TransferHelper.transferETH(router, amount);
        if (msg.value > amount){
            TransferHelper.transferETH(msg.sender, msg.value - amount);
        }
        actualAmount = Router(router).repay(TransferHelper.ETH, _for);
    }

    function liquidate(LiquidateArgs memory _param) external returns (uint actualAmount, uint burnedAmount){
        Types.Asset memory asset = Router(router).assets(_param.debtAsset);
        uint amount = _param.amount *asset.dToken.totalSupply() / Router(router).totalDebts(_param.debtAsset);
        TransferHelper.transferFrom(_param.debtAsset, msg.sender, router, amount);
        (actualAmount, burnedAmount) = Router(router).liquidate(_param.debtAsset, _param.collateralAsset, _param.to, msg.sender);
    }
}