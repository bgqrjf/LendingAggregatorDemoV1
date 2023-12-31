// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IFactory{
    function newConfig(address _owner, uint _vaultRatio) external returns (address);
    function newVault() external returns (address);
    function newAsset(Types.NewAssetParams memory _newAsset, uint8 _id) external returns (Types.Asset memory asset);
}