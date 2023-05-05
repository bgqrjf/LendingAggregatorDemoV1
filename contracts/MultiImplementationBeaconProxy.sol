// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import "./interfaces/IMultiImplementationBeacon.sol";

contract MultiImplementationBeaconProxy is Proxy, ERC1967Upgrade {
    bytes32 public immutable implementationID;

    constructor(bytes32 _implementationID, bytes memory _initdata) {
        implementationID = _implementationID;
        _setBeacon(msg.sender, _initdata);
    }

    function _beacon() internal view virtual returns (address) {
        return _getBeacon();
    }

    function _implementation()
        internal
        view
        virtual
        override
        returns (address)
    {
        return
            IMultiImplementationBeacon(_getBeacon()).implementations(
                implementationID
            );
    }

    function _setBeacon(address beacon, bytes memory data) internal virtual {
        StorageSlot.getAddressSlot(_BEACON_SLOT).value = beacon;
        emit BeaconUpgraded(beacon);

        if (data.length > 0) {
            Address.functionDelegateCall(_implementation(), data);
        }
    }
}
