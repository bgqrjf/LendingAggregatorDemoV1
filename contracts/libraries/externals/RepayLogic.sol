// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../internals/ExternalUtils.sol";
import "../internals/TransferHelper.sol";
import "../internals/Types.sol";

import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";
import "../../interfaces/IConfig.sol";

library RepayLogic {
    event FeeCollected(
        address indexed asset,
        address indexed collector,
        uint256 amount
    );

    event Repayed(
        address indexed borrower,
        address indexed asset,
        uint256 amount
    );

    function repay(
        Types.RepayParams memory _params,
        mapping(address => uint256) storage totalLendings,
        mapping(address => uint256) storage accFees,
        mapping(address => uint256) storage collectedFees,
        mapping(address => uint256) storage feeIndexes
    ) external {
        repayInternal(
            _params,
            totalLendings,
            accFees,
            collectedFees,
            feeIndexes
        );
    }

    function repayInternal(
        Types.RepayParams memory _params,
        mapping(address => uint256) storage totalLendings,
        mapping(address => uint256) storage accFees,
        mapping(address => uint256) storage collectedFees,
        mapping(address => uint256) storage feeIndexes
    ) internal returns (uint256 amount) {
        require(_params.actionNotPaused, "RepayLogic: action paused");

        (
            ,
            uint256 protocolsBorrows,
            uint256 totalLending,
            uint256 reservePoolLentAmount,
            uint256 newInterest
        ) = ExternalUtils.getBorrowStatus(
                _params.userParams.asset,
                _params.reservePool,
                _params.protocols,
                totalLendings
            );

        uint256 totalBorrowedAmount = protocolsBorrows +
            totalLending +
            reservePoolLentAmount;

        uint256 fee;
        (amount, fee) = recordRepay(
            Types.RecordRepayParams(
                _params.userParams,
                _params.config,
                _params.rewards,
                _params.accFeeOffset,
                _params.userFeeIndexes,
                _params.asset
            ),
            newInterest,
            totalBorrowedAmount,
            accFees,
            collectedFees,
            feeIndexes
        );

        TransferHelper.collect(
            _params.userParams.asset,
            msg.sender,
            _params.feeCollector,
            fee,
            0
        );
        emit FeeCollected(_params.userParams.asset, _params.feeCollector, fee);

        if (
            _params.userParams.asset == TransferHelper.ETH &&
            _params.userParams.amount > amount
        ) {
            _refundETH(_params.userParams.amount - amount);
        }

        if (address(_params.reservePool) != address(0)) {
            TransferHelper.collect(
                _params.userParams.asset,
                msg.sender,
                address(_params.reservePool),
                amount - fee,
                0
            );

            _params.reservePool.repay(
                _params.userParams,
                totalBorrowedAmount,
                _params.executeNow
            );
        } else {
            TransferHelper.collect(
                _params.userParams.asset,
                msg.sender,
                address(_params.protocols),
                amount - fee,
                0
            );

            totalLending = executeRepayInternal(
                _params.protocols,
                _params.userParams.asset,
                amount - fee,
                totalLending,
                totalLendings
            );
        }

        ExternalUtils.updateTotalLendings(
            _params.protocols,
            _params.userParams.asset,
            totalLending > fee ? totalLending - fee : 0,
            totalLendings
        );
    }

    function recordRepay(
        Types.RecordRepayParams memory _params,
        uint256 newInterest,
        uint256 totalBorrows,
        mapping(address => uint256) storage accFees,
        mapping(address => uint256) storage collectedFees,
        mapping(address => uint256) storage feeIndexes
    ) internal returns (uint256 repayAmount, uint256 fee) {
        uint256 dTokenTotalSupply = _params.asset.dToken.totalSupply();
        uint256 userDebts = _params.asset.dToken.scaledAmount(
            _params.asset.dToken.balanceOf(_params.userParams.to),
            totalBorrows
        );

        repayAmount = _params.userParams.amount;
        if (repayAmount >= userDebts) {
            repayAmount = userDebts;
            _params.config.setBorrowing(
                _params.userParams.to,
                _params.asset.index,
                false
            );
        }

        uint256 dTokenAmount = _params.asset.dToken.burn(
            _params.userParams.to,
            repayAmount,
            totalBorrows
        );

        uint256 accFee = ExternalUtils.updateAccFee(
            _params.userParams.asset,
            newInterest,
            _params.config,
            accFees
        );
        uint256 feeIndex = ExternalUtils.updateFeeIndex(
            _params.userParams.asset,
            dTokenTotalSupply,
            // accFee + accFeeOffsets[_params.asset]
            accFee + _params.accFeeOffset,
            feeIndexes
        );

        fee =
            ((feeIndex - _params.userFeeIndexes) * dTokenAmount) /
            Utils.QUINTILLION;

        collectedFees[_params.userParams.asset] += fee;

        _params.rewards.stopMiningBorrowReward(
            _params.userParams.asset,
            _params.userParams.to,
            dTokenAmount,
            dTokenTotalSupply
        );

        emit Repayed(
            _params.userParams.to,
            _params.userParams.asset,
            repayAmount
        );
    }

    function executeRepay(
        IProtocolsHandler protocols,
        address _asset,
        uint256 _amount,
        uint256 _totalLending,
        mapping(address => uint256) storage totalLendings
    ) external {
        executeRepayInternal(
            protocols,
            _asset,
            _amount,
            _totalLending,
            totalLendings
        );
    }

    function executeRepayInternal(
        IProtocolsHandler protocols,
        address _asset,
        uint256 _amount,
        uint256 _totalLending,
        mapping(address => uint256) storage totalLendings
    ) internal returns (uint256 totalLending) {
        (uint256[] memory supplies, uint256 protocolsSupplies) = protocols
            .totalSupplied(_asset);

        (, uint256 supplied) = protocols.repayAndSupply(
            _asset,
            _amount,
            supplies,
            protocolsSupplies
        );

        totalLending = _totalLending > supplied ? _totalLending - supplied : 0;

        ExternalUtils.updateTotalLendings(
            protocols,
            _asset,
            totalLending,
            totalLendings
        );
    }

    function _refundETH(uint256 _amount) internal {
        if (address(this).balance >= _amount) {
            TransferHelper.transferETH(msg.sender, _amount, 0);
        }
    }
}
