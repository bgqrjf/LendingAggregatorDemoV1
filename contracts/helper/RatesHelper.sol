// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.14;

import "../interfaces/IRouter.sol";
import "../libraries/internals/Utils.sol";

import "./MulticallHelper.sol";

contract RateGetter is MulticallHelper {
    IRouter public router;

    constructor(address _router) {
        router = IRouter(_router);
    }

    function getCurrentSupplyRate(address _underlying)
        public
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

        uint256 routerBorrowed = router.totalBorrowed(_underlying);
        uint256 lendingRate = totalSuppliedAmountWithFee > 0 &&
            protocolsBorrowRate > protocolsSupplyRate
            ? protocolsSupplyRate +
                ((protocolsBorrowRate - protocolsSupplyRate) * routerBorrowed) /
                totalSuppliedAmountWithFee
            : protocolsSupplyRate;

        return
            totalSuppliedAmountWithFee > 0
                ? (protocolsSupplyRate *
                    protocolsSupplies +
                    lendingRate *
                    totalLending) / (totalSuppliedAmountWithFee * Utils.MILLION)
                : routerBorrowed > 0
                ? lendingRate
                : protocolsSupplyRate;
    }

    function getCurrentBorrowRate(address _underlying)
        public
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

        uint256 routerSupplied = router.totalSupplied(_underlying);
        uint256 lendingRate = routerSupplied > 0 &&
            protocolsBorrowRate > protocolsSupplyRate
            ? protocolsSupplyRate +
                ((protocolsBorrowRate - protocolsSupplyRate) *
                    totalBorrowedAmount) /
                routerSupplied
            : protocolsSupplyRate;

        uint256 protocolsBorrows = Utils.sumOf(borrows);

        return
            totalBorrowedAmount > 0
                ? (protocolsBorrowRate *
                    protocolsBorrows +
                    lendingRate *
                    totalLending) / (totalBorrowedAmount * Utils.MILLION)
                : routerSupplied > 0
                ? lendingRate
                : protocolsBorrowRate;
    }

    function getLendingRate(address _underlying) public view returns (uint256) {
        (uint256 protocolsSupplyRate, uint256 protocolsBorrowRate) = router
            .protocols()
            .getRates(_underlying);

        uint256 routerSupplied = router.totalSupplied(_underlying);

        return
            routerSupplied > 0 && protocolsBorrowRate > protocolsSupplyRate
                ? protocolsSupplyRate +
                    ((protocolsBorrowRate - protocolsSupplyRate) *
                        router.totalBorrowed(_underlying)) /
                    routerSupplied
                : protocolsSupplyRate;
    }
}
