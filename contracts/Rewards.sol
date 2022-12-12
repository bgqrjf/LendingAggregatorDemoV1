// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRewards.sol";
import "./libraries/TransferHelper.sol";

contract Rewards is IRewards, Ownable {
    IProtocol[] public protocols;
    address public protocolsHandler;

    // mapping user => asset => isSupply => userData
    mapping(address => mapping(address => mapping(bool => UserData)))
        public userData;

    // mapping asset => protocols => isSupply => amount
    mapping(address => mapping(IProtocol => mapping(bool => uint256)))
        public totalClaimed;
    mapping(address => mapping(IProtocol => mapping(bool => uint256)))
        public totalRewardslast;

    constructor(address _protocolsHandler) Ownable() {
        protocolsHandler = _protocolsHandler;
    }

    function startMiningSupplyReward(
        address _asset,
        address _account,
        uint256 _share,
        uint256 _totalShare
    ) external override onlyOwner {
        IProtocol[] memory protocolsCache = protocols;
        UserData memory data = userData[_account][_asset][true];
        while (data.rewards.length <= protocolsCache.length) {
            userData[_account][_asset][true].rewards.push();
            data = userData[_account][_asset][true];
        }

        for (uint256 i = 0; i < protocolsCache.length; ++i) {
            uint256 currentRewardPerShare = getRewardPerShare(
                _asset,
                protocolsCache[i],
                _totalShare,
                true
            );

            userData[_account][_asset][true].rewards[i].claimed =
                data.rewards[i].claimed +
                currentRewardPerShare *
                _share;
        }

        userData[_account][_asset][true].shares = data.shares + _share;
    }

    function stopMiningSupplyReward(
        address _asset,
        address _account,
        uint256 _share,
        uint256 _totalShare
    ) public override onlyOwner {
        IProtocol[] memory protocolsCache = protocols;
        UserData memory data = userData[_account][_asset][true];
        while (data.rewards.length < protocolsCache.length) {
            userData[_account][_asset][true].rewards.push();
            data = userData[_account][_asset][true];
        }

        for (uint256 i = 0; i < protocolsCache.length; ++i) {
            uint256 currentRewardPerShare = getRewardPerShare(
                _asset,
                protocolsCache[i],
                _totalShare,
                true
            );

            userData[_account][_asset][true].rewards[i].lastReward = data
                .rewards[i]
                .lastReward +
                _totalShare >
                0
                ? ((currentRewardPerShare -
                    data.rewards[i].lastRewardPerShare) * data.shares) /
                    _totalShare
                : 0;

            userData[_account][_asset][true]
                .rewards[i]
                .lastRewardPerShare = currentRewardPerShare;
        }

        userData[_account][_asset][true].shares = data.shares - _share;
    }

    function startMiningBorrowReward(
        address _asset,
        address _account,
        uint256 _share,
        uint256 _totalShare
    ) external override onlyOwner {
        IProtocol[] memory protocolsCache = protocols;
        UserData memory data = userData[_account][_asset][false];
        while (data.rewards.length < protocolsCache.length) {
            userData[_account][_asset][false].rewards.push();
            data = userData[_account][_asset][false];
        }

        for (uint256 i = 0; i < protocolsCache.length; ++i) {
            uint256 currentRewardPerShare = getRewardPerShare(
                _asset,
                protocolsCache[i],
                _totalShare,
                false
            );

            userData[_account][_asset][false].rewards[i].claimed =
                data.rewards[i].claimed +
                currentRewardPerShare *
                _share;
        }

        userData[_account][_asset][false].shares += data.shares + _share;
    }

    function stopMiningBorrowReward(
        address _asset,
        address _account,
        uint256 _share,
        uint256 _totalShare
    ) public override onlyOwner {
        IProtocol[] memory protocolsCache = protocols;
        UserData memory data = userData[_account][_asset][false];
        while (data.rewards.length < protocolsCache.length) {
            userData[_account][_asset][false].rewards.push();
            data = userData[_account][_asset][false];
        }

        for (uint256 i = 0; i < protocolsCache.length; ++i) {
            uint256 currentRewardPerShare = getRewardPerShare(
                _asset,
                protocolsCache[i],
                _totalShare,
                false
            );

            userData[_account][_asset][false].rewards[i].lastReward = data
                .rewards[i]
                .lastReward +
                _totalShare >
                0
                ? ((currentRewardPerShare -
                    data.rewards[i].lastRewardPerShare) * data.shares) /
                    _totalShare
                : 0;
            userData[_account][_asset][false]
                .rewards[i]
                .lastRewardPerShare = currentRewardPerShare;
        }

        userData[_account][_asset][false].shares = data.shares - _share;
    }

    function claim(
        address _asset,
        address _account,
        uint256 _totalShare
    ) external override onlyOwner returns (uint256[] memory rewardsToCollect) {
        stopMiningSupplyReward(_asset, _account, 0, _totalShare);
        stopMiningBorrowReward(_asset, _account, 0, _totalShare);

        UserData memory supplyData = userData[_account][_asset][false];
        UserData memory borrowData = userData[_account][_asset][true];

        rewardsToCollect = new uint256[](supplyData.rewards.length);
        for (uint256 i = 0; i < supplyData.rewards.length; ++i) {
            supplyData.rewards[i].claimed += supplyData.rewards[i].lastReward;
            borrowData.rewards[i].claimed += borrowData.rewards[i].lastReward;

            rewardsToCollect[i] +=
                supplyData.rewards[i].lastReward +
                borrowData.rewards[i].lastReward;

            supplyData.rewards[i].lastReward = 0;
            borrowData.rewards[i].lastReward = 0;

            uint256 protocolRewardBalance = TransferHelper.balanceOf(
                protocols[i].rewardToken(),
                protocolsHandler
            );

            if (rewardsToCollect[i] > protocolRewardBalance) {
                protocols[i].claimRewards(protocolsHandler);
            }
        }
    }

    function addProtocol(IProtocol _protocol) external onlyOwner {
        protocols.push(_protocol);
    }

    function getRewardPerShare(
        address _asset,
        IProtocol _protocol,
        uint256 _totalShare,
        bool _isSupply
    ) internal view returns (uint256 rewardPerShare) {
        uint256 totalRewards = IProtocol(_protocol).totalRewards(
            _asset,
            protocolsHandler,
            _isSupply
        );

        rewardPerShare = _totalShare > 0
            ? (totalRewards - totalRewardslast[_asset][_protocol][_isSupply]) /
                _totalShare
            : 0;
    }

    function setProtocolsHandler(address _protocolsHandler) external onlyOwner {
        protocolsHandler = _protocolsHandler;
    }
}
