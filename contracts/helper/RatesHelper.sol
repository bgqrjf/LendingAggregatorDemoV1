// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.14;

import "../interfaces/IRouter.sol";

import "../libraries/internals/Utils.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./MulticallHelper.sol";

contract RatesHelper is MulticallHelper {
    IRouter public router;

    constructor(address _router) {
        router = IRouter(_router);
    }

    function getCurrentSupplyRate(
        address _underlying
    ) public view returns (uint256) {
        (
            ,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 totalSuppliedAmountWithFee,

        ) = router.getSupplyStatus(_underlying);

        (uint256 protocolsSupplyRate, ) = router.protocols().getRates(
            _underlying
        );

        uint256 lendingRate = getLendingRate(_underlying);

        lendingRate =
            (lendingRate *
                (Utils.MILLION -
                    router.getAsset(_underlying).dToken.feeRate())) /
            Utils.MILLION;

        return
            totalSuppliedAmountWithFee > 0
                ? (protocolsSupplyRate *
                    protocolsSupplies +
                    lendingRate *
                    totalLending) / (totalSuppliedAmountWithFee)
                : protocolsSupplyRate;
    }

    function getLendingRate(address _underlying) public view returns (uint256) {
        (, , , uint256 totalSuppliedAmountWithFee, ) = router.getSupplyStatus(
            _underlying
        );

        (uint256 protocolsSupplyRate, uint256 protocolsBorrowRate) = router
            .protocols()
            .getRates(_underlying);

        return
            totalSuppliedAmountWithFee > 0 &&
                protocolsBorrowRate > protocolsSupplyRate
                ? protocolsSupplyRate +
                    ((protocolsBorrowRate - protocolsSupplyRate) *
                        Math.min(
                            router.totalBorrowed(_underlying),
                            totalSuppliedAmountWithFee
                        )) /
                    totalSuppliedAmountWithFee
                : protocolsSupplyRate;
    }

    function getCurrentSupplyRates(
        address _underlying
    ) public view returns (uint256 rate, uint256[] memory protocolsRates) {
        rate = getCurrentSupplyRate(_underlying);
        protocolsRates = getProtocolsSupplyRates(_underlying);
    }

    function getProtocolsSupplyRates(
        address _underlying
    ) public view returns (uint256[] memory protocolsRates) {
        IProtocol[] memory protocols = router.protocols().getProtocols();
        protocolsRates = new uint256[](protocols.length);
        for (uint i = 0; i < protocols.length; ++i) {
            protocolsRates[i] = protocols[i].getCurrentSupplyRate(_underlying);
        }
    }

    function getCurrentBorrowRate(
        address _underlying
    ) public view returns (uint256) {
        (
            uint256[] memory borrows,
            uint256 totalBorrowedAmount,
            uint256 totalLending,

        ) = router.getBorrowStatus(_underlying);

        (, uint256 protocolsBorrowRate) = router.protocols().getRates(
            _underlying
        );

        uint256 lendingRate = getLendingRate(_underlying);
        uint256 protocolsBorrows = Utils.sumOf(borrows);

        return
            totalBorrowedAmount > 0
                ? (protocolsBorrowRate *
                    protocolsBorrows +
                    lendingRate *
                    totalLending) / (totalBorrowedAmount)
                : protocolsBorrowRate;
    }

    function getCurrentBorrowRates(
        address _underlying
    ) public view returns (uint256 rate, uint256[] memory protocolsRates) {
        rate = getCurrentBorrowRate(_underlying);
        protocolsRates = getProtocolsBorrowRates(_underlying);
    }

    function getProtocolsBorrowRates(
        address _underlying
    ) public view returns (uint256[] memory protocolsRates) {
        IProtocol[] memory protocols = router.protocols().getProtocols();
        protocolsRates = new uint256[](protocols.length);
        for (uint i = 0; i < protocols.length; ++i) {
            protocolsRates[i] = protocols[i].getCurrentBorrowRate(_underlying);
        }
    }
}
