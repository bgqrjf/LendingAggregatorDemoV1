// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IFactory.sol";
import "./libraries/Types.sol";

import "./Config.sol";
import "./SToken.sol";
import "./DToken.sol";
import "./Treasury.sol";

contract Factory is IFactory{
    function newConfig(uint _treasuryRatio) external override returns (address){
        return address(new Config(msg.sender, _treasuryRatio));
    }

    function newTreasury() external override returns (address){
        return address(new Treasury());
    }

    function newAsset(Types.NewAssetParams memory _newAsset, uint8 _id) external override returns (Types.Asset memory asset){
        asset = Types.Asset(
            _id,
            new SToken(_newAsset.underlying, _newAsset.sTokenName, _newAsset.sTokenSymbol),
            new DToken(_newAsset.underlying, _newAsset.dTokenName, _newAsset.dTokenSymbol),
            _newAsset.collateralable,
            0,
            0
        );
    }

}