// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

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
    address public rewards;
    address public logic;

    mapping(address => address) public cTokens;

    mapping(address => SimulateData) public lastSimulatedSupply;
    mapping(address => SimulateData) public lastSimulatedBorrow;

    mapping(address => mapping(address => uint256)) public lastSupplyIndexes;
    mapping(address => mapping(address => uint256)) public lastBorrowIndexes;

    constructor(
        address _owner,
        address _comptroller,
        address _cETH,
        address _compTokenAddress,
        address _rewards
    ) {
        _transferOwnership(_owner);
        comptroller = ComptrollerInterface(_comptroller);
        (bool isListed, , ) = comptroller.markets(_cETH);
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[TransferHelper.ETH] = _cETH;

        rewardToken = _compTokenAddress;
        rewards = _rewards;
        logic = msg.sender;
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

    function setRewards(
        address _newRewards,
        address _newRewardsToken
    ) external onlyOwner {
        rewardToken = _newRewardsToken;
        rewards = _newRewards;
    }

    function setLogicAddress(address _newLogic) external onlyOwner {
        logic = _newLogic;
    }

    function updateCTokenList(address _cToken) external {
        (bool isListed, , ) = comptroller.markets(address(_cToken));
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[CTokenInterface(_cToken).underlying()] = _cToken;
    }

    function updateLastSupplyRewards(
        address _cToken,
        address _account,
        uint256 _index
    ) external {
        require(msg.sender == logic, "CompoundLogicStorage: unAuthorized");
        lastSupplyIndexes[_cToken][_account] = _index;
    }

    function updateLastBorrowRewards(
        address _cToken,
        address _account,
        uint256 _index
    ) external {
        require(msg.sender == logic, "CompoundLogicStorage: unAuthorized");
        lastBorrowIndexes[_cToken][_account] = _index;
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
