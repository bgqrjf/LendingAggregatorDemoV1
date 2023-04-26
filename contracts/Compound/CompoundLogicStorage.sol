// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./ComptrollerInterface.sol";

import "../libraries/internals/TransferHelper.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract CompoundLogicStorage is Ownable {
    struct SimulateData {
        uint256 amount;
        uint256 index;
    }

    ComptrollerInterface public comptroller;
    address public rewardToken;

    mapping(address => address) public cTokens;

    mapping(address => SimulateData) public lastSimulatedSupply;
    mapping(address => SimulateData) public lastSimulatedBorrow;

    constructor(
        address _owner,
        address _comptroller,
        address _cETH,
        address _compTokenAddress
    ) {
        _transferOwnership(_owner);
        comptroller = ComptrollerInterface(_comptroller);
        (bool isListed, , ) = comptroller.markets(_cETH);
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[TransferHelper.ETH] = _cETH;

        rewardToken = _compTokenAddress;
    }

    function setLastSimulatedSupply(
        address _asset,
        SimulateData memory data
    ) external onlyOwner {
        lastSimulatedSupply[_asset] = data;
    }

    function setLastSimulatedBorrow(
        address _asset,
        SimulateData memory data
    ) external onlyOwner {
        lastSimulatedBorrow[_asset] = data;
    }

    function updateCTokenList(address _cToken) external {
        (bool isListed, , ) = comptroller.markets(address(_cToken));
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[CTokenInterface(_cToken).underlying()] = _cToken;
    }

    function getLastSimulatedSupply(
        address _asset
    ) public view returns (SimulateData memory data) {
        return lastSimulatedSupply[_asset];
    }

    function getLastSimulatedBorrow(
        address _asset
    ) public view returns (SimulateData memory data) {
        return lastSimulatedBorrow[_asset];
    }
}
