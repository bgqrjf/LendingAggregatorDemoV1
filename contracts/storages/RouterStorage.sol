// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.14;

import "../interfaces/IRouter.sol";

abstract contract RouterStorage is IRouter {
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

    mapping(address => uint256) public accFees;
    mapping(address => uint256) public collectedFees;
    mapping(address => uint256) public feeIndexes;
    mapping(address => mapping(address => uint256)) public userFeeIndexes;
    mapping(address => mapping(address => uint256)) public userFee;

    // address0 => block all
    // tokenAddress => block token
    mapping(address => uint256) public blockedActions;
}
