// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.14;

import "../interfaces/IRouter.sol";

abstract contract RouterStorage is IRouter {
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
    mapping(address => uint256) public userSupplied;

    mapping(address => uint256) public accFees;
    mapping(address => uint256) public collectedFees;
    mapping(address => uint256) public accFeeOffsets;
    mapping(address => uint256) public feeIndexes;
    mapping(address => mapping(address => uint256)) public userFeeIndexes;
}
