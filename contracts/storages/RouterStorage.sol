// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.14;

import "../interfaces/IRewards.sol";
import "../interfaces/IRouter.sol";

abstract contract RouterStorage is IRouter {
    // keccak256(abi.encode(sToken))
    bytes32 constant keySToken =
        0xf4607c285e5e5052b68cc102b0f0aefa028c725cf822cbeb4df3b38eae13f4c6;
    // keccak256(abi.encode(dToken))
    bytes32 constant keyDToken =
        0x397d006442448cc7c6efb9f002a4f07af385617253d574a44d3027430057e1fe;

    IConfig public override config;
    IPriceOracle public override priceOracle;
    IProtocolsHandler public protocols;
    IRewards public rewards;
    IReservePool public reservePool;
    address payable public feeCollector;

    address public sTokenImplement;
    address public dTokenImplement;
    address[] public underlyings;
    mapping(address => Types.Asset) public assets;
    mapping(address => uint256) public totalLendings;

    // address0 => block all
    // tokenAddress => block token
    mapping(address => uint256) public blockedActions;
}
