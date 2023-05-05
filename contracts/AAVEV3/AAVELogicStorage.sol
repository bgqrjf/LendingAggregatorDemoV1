// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./IAAVEPool.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract AAVELogicStorage is Ownable {
    struct SimulateData {
        uint256 amount;
        uint256 index;
    }

    address payable public wrappedNative;
    address public rewardToken;
    IAAVEPool public pool;

    // mapping underlying , msg.sender to simulateData
    mapping(address => SimulateData) internal lastSimulatedSupply;
    mapping(address => SimulateData) internal lastSimulatedBorrow;

    constructor(
        address _owner,
        address _pool,
        address payable _wrappedNative
    ) {
        _transferOwnership(_owner);
        pool = IAAVEPool(_pool);
        wrappedNative = _wrappedNative;
    }

    function setLastSimulatedSupply(address _asset, SimulateData memory data)
        external
        onlyOwner
    {
        lastSimulatedSupply[_asset] = data;
    }

    function setLastSimulatedBorrow(address _asset, SimulateData memory data)
        external
        onlyOwner
    {
        lastSimulatedBorrow[_asset] = data;
    }

    function getLastSimulatedSupply(address _asset)
        public
        view
        returns (SimulateData memory data)
    {
        return lastSimulatedSupply[_asset];
    }

    function getLastSimulatedBorrow(address _asset)
        public
        view
        returns (SimulateData memory data)
    {
        return lastSimulatedBorrow[_asset];
    }
}
