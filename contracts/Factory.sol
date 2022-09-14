// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IFactory.sol";
import "./libraries/Types.sol";

import "./Config.sol";
import "./SToken.sol";
import "./DToken.sol";
import "./ProtocolsHandler.sol";

contract Factory is IFactory {
    function newConfig(address _owner) external override returns (address) {
        return address(new Config(_owner, msg.sender));
    }

    function newAsset(Types.NewAssetParams memory _newAsset, uint8 _id)
        external
        override
        returns (Types.Asset memory asset)
    {
        asset = Types.Asset(
            _id,
            new SToken(
                msg.sender,
                _newAsset.underlying,
                _newAsset.sTokenName,
                _newAsset.sTokenSymbol
            ),
            new DToken(
                msg.sender,
                _newAsset.underlying,
                _newAsset.dTokenName,
                _newAsset.dTokenSymbol
            ),
            _newAsset.collateralable
        );
    }

    function newProtocolsHandler(address[] memory _protocols, address _strategy)
        external
        override
        returns (address)
    {
        return address(new ProtocolsHandler(_protocols, _strategy, msg.sender));
    }
}
