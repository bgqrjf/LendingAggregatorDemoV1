// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.14;

interface ComptrollerLensInterface {
    function markets(address) external view returns(bool, uint, bool);
}