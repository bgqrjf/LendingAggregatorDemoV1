// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IMultiImplementationBeacon {
    function implementations(bytes32) external view returns (address);
}
