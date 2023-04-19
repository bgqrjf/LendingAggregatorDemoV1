// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IMultiImplementationBeacon {
    function implementations(bytes32) external view returns (address);
}
