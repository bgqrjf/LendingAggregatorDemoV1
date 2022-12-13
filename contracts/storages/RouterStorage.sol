// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.14;

import "../interfaces/IRouter.sol";

abstract contract RouterStorage is IRouter {
    enum Action {
        supply,
        redeem,
        borrow,
        repay,
        liquidate,
        claimRewards
    }

    IConfig public config;
    IPriceOracle public priceOracle;
    IProtocolsHandler public protocols;
    IRewards public rewards;
    address payable public feeCollector;

    address public sTokenImplement;
    address public dTokenImplement;
    address[] public underlyings;
    mapping(address => Types.Asset) public assets;
    mapping(address => uint256) public totalLendings;

    mapping(address => uint256) public accFees;
    mapping(address => uint256) public collectedFees;
    mapping(address => uint256) public accFeeOffsets;
    mapping(address => uint256) public feeIndexes;
    mapping(address => mapping(address => uint256)) public userFeeIndexes;

    mapping(address => bool) public tokenPaused;

    // address0 => block all
    // tokenAddress => block token
    mapping(address => uint256) public blockedActions;
}
