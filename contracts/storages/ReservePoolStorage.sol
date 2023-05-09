// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import "../interfaces/IReservePool.sol";

abstract contract ReservePoolStorage is IReservePool {
    struct PendingRequest {
        address nextAccount;
        uint256 amount;
        bool collateralable;
    }

    uint256 public maxPendingRatio;
    mapping(address => uint256) public maxReserves;
    mapping(address => uint256) public executeSupplyThresholds;

    mapping(address => mapping(address => PendingRequest))
        public pendingSupplies;
    mapping(address => address) public nextAccountsToSupply;
    mapping(address => address) public lastAccountsToSupply;

    mapping(address => uint256) public reserves;
    mapping(address => uint256) public pendingSupplyAmounts;
    mapping(address => uint256) public override redeemedAmounts;
    mapping(address => uint256) public override lentAmounts;
    mapping(address => uint256) public override pendingRepayAmounts;
}
