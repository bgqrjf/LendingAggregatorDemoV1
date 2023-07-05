import "./IProtocol.sol";
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ICompProtocol is IProtocol {
    function getSupplyCompSpeed(
        address _underlying
    ) external view returns (uint256);

    function getBorrowCompSpeed(
        address _underlying
    ) external view returns (uint256);

    function BLOCK_PER_YEAR() external view returns (uint256);
}
