// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.14;

import "../interfaces/IRouter.sol";
import "../libraries/internals/Utils.sol";

import "./MulticallHelper.sol";

contract RateGetter is MulticallHelper {
    IRouter router;

    constructor(address _router) {
        router = IRouter(_router);
    }

    function getSupplyRate(address _underlying)
        external
        view
        returns (uint256)
    {
        (
            ,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 totalSuppliedAmountWithFee,

        ) = router.getSupplyStatus(_underlying);

        (uint256 protocolsSupplyRate, uint256 protocolsBorrowRate) = router
            .protocols()
            .getRates(_underlying);

        uint256 lendingRate = ((protocolsBorrowRate - protocolsSupplyRate) *
            (router.totalBorrowed(_underlying))) / (totalSuppliedAmountWithFee);

        return
            (protocolsSupplyRate *
                protocolsSupplies +
                lendingRate *
                totalLending) / (totalSuppliedAmountWithFee * Utils.MILLION);
    }

    function getBorrowRate(address _underlying)
        external
        view
        returns (uint256)
    {
        (
            uint256[] memory borrows,
            uint256 totalBorrowedAmount,
            uint256 totalLending,

        ) = router.getBorrowStatus(_underlying);

        (uint256 protocolsSupplyRate, uint256 protocolsBorrowRate) = router
            .protocols()
            .getRates(_underlying);

        uint256 lendingRate = ((protocolsBorrowRate - protocolsSupplyRate) *
            (totalBorrowedAmount)) / (router.totalSupplied(_underlying));

        uint256 protocolsBorrows = Utils.sumOf(borrows);

        return
            (protocolsBorrowRate *
                protocolsBorrows +
                lendingRate *
                totalLending) / (totalBorrowedAmount * Utils.MILLION);
    }

    function getLendingRate(address _underlying)
        external
        view
        returns (uint256 lendingRate)
    {
        (uint256 protocolsSupplyRate, uint256 protocolsBorrowRate) = router
            .protocols()
            .getRates(_underlying);

        lendingRate =
            ((protocolsBorrowRate - protocolsSupplyRate) *
                (router.totalBorrowed(_underlying))) /
            (router.totalSupplied(_underlying));
    }
}
