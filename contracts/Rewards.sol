// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IRewards.sol";

contract Rewards is IRewards {
    function startMiningSupplyReward(
        address asset,
        address account,
        uint256 amount
    ) external override {}

    function stopMiningSupplyReward(
        address asset,
        address account,
        uint256 amount
    ) external override {}

    function startMiningBorrowReward(
        address asset,
        address account,
        uint256 amount
    ) external override {}

    function stopMiningBorrowReward(
        address asset,
        address account,
        uint256 amount
    ) external override {}

    // address public router;
    // mapping(address => mapping(IProtocol => mapping(address => bytes))) public userRewardsData;
    // modifier onlyRouter{
    //     require(msg.sender == router, "Rewards: Only Router");
    //     _;
    // }
    // constructor(address _router){
    //     router = _router;
    // }
    // function updateSupplyRewardData(IProtocol _protocol, address _underlying, Types.UserShare memory _share, address _account) external override onlyRouter{
    //     (userRewardsData[_account][_protocol][_underlying], userRewardsData[address(0)][_protocol][_underlying])
    //         = _protocol.getRewardSupplyData(
    //             _underlying,
    //             _share,
    //             userRewardsData[_account][_protocol][_underlying],
    //             userRewardsData[address(0)][_protocol][_underlying]
    //         );
    // }
    // function updateRouterSupplyRewardData(IProtocol _protocol, address _underlying, uint _totalShare) external override onlyRouter{
    //     userRewardsData[address(0)][_protocol][_underlying] = _protocol.getRouterRewardSupplyData(
    //         _underlying,
    //         _totalShare,
    //         userRewardsData[address(0)][_protocol][_underlying]
    //     );
    // }
}
