// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.14;

import "./CTokenInterface.sol";
import "./IOracle.sol";

interface ComptrollerInterface {
    function enterMarkets(address[] memory cTokens)
        external
        returns (uint256[] memory);

    function markets(address cToken)
        external
        view
        returns (
            bool,
            uint256,
            bool
        );

    function getAssetsIn(address account)
        external
        view
        returns (CTokenInterface[] memory);

    function oracle() external view returns (IOracle);

    function claimComp(address holder) external;

    function compSupplyState(address cToekn)
        external
        view
        returns (uint224 index, uint32 block);

    function compBorrowState(address cToken)
        external
        view
        returns (uint224 index, uint32 block);

    function compSupplySpeeds(address cToken)
        external
        view
        returns (uint256 speed);

    function compSupplierIndex(address cToken, address account)
        external
        view
        returns (uint256);

    function compBorrowerIndex(address cToken, address account)
        external
        view
        returns (uint256);

    function compBorrowSpeeds(address cToken) external view returns (uint256);
}
