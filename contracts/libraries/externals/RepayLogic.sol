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

    event Repaid(
        address indexed borrower,
        address indexed asset,
        uint256 amount
    );

    function repay(
        Types.RepayParams memory _params,
        mapping(address => uint256) storage totalLendings
    ) external {
        repayInternal(_params, totalLendings);
    }

    function repayInternal(
        Types.RepayParams memory _params,
        mapping(address => uint256) storage totalLendings
    ) internal returns (uint256 amount) {
        require(_params.actionNotPaused, "RepayLogic: action paused");

        (
            ,
            uint256 totalBorrowedAmount,
            uint256 totalLending,
            uint256 newInterest
        ) = ExternalUtils.getBorrowStatus(
                _params.userParams.asset,
                _params.reservePool,
                _params.protocols,
                totalLendings
            );

        uint256 newFee;
        (amount, newFee) = recordRepay(
            Types.RecordRepayParams(
                _params.userParams,
                _params.rewards,
                _params.asset,
                newInterest,
                totalBorrowedAmount
            )
        );

        if (newFee > 0) {
            TransferHelper.collect(
                _params.userParams.asset,
                msg.sender,
                address(_params.feeCollector),
                newFee,
                0
            );
            totalLending -= newFee;
        }

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
                amount - newFee,
                0
            );

            ExternalUtils.updateTotalLendings(
                _params.protocols,
                _params.userParams.asset,
                totalLending,
                totalLendings
            );

            _params.reservePool.repay(
                Types.UserAssetParams(
                    _params.userParams.asset,
                    amount - newFee,
                    _params.userParams.to
                ),
                totalBorrowedAmount - newFee,
                _params.executeNow
            );
        } else {
            executeRepayInternal(
                _params.protocols,
                _params.userParams.asset,
                amount - newFee,
                totalLending,
                totalLendings
            );
        }

        if (_params.asset.dToken.balanceOf(msg.sender) == 0) {
            _params.config.setBorrowing(
                msg.sender,
                _params.userParams.asset,
                false
            );
        }
    }

    function recordRepay(
        Types.RecordRepayParams memory _params
    ) internal returns (uint256 repaidAmount, uint256 newFee) {
        (repaidAmount, newFee) = _params.asset.dToken.burn(
            _params.userParams.to,
            _params.userParams.amount,
            _params.totalBorrows,
            _params.newInterest
        );

        // _params.rewards.stopMiningBorrowReward(
        //     _params.userParams.asset,
        //     _params.userParams.to,
        //     dTokenAmount,
        //     dTokenTotalSupply
        // );

        emit Repaid(
            _params.userParams.to,
            _params.userParams.asset,
            repaidAmount
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
    ) internal {
        TransferHelper.collect(
            _asset,
            msg.sender,
            address(protocols),
            _amount,
            0
        );

        (uint256[] memory supplies, uint256 protocolsSupplies) = protocols
            .totalSupplied(_asset);

        (, uint256 supplied) = protocols.repayAndSupply(
            _asset,
            _amount,
            supplies,
            protocolsSupplies
        );

        ExternalUtils.updateTotalLendings(
            protocols,
            _asset,
            _totalLending - supplied,
            totalLendings
        );
    }

    function _refundETH(uint256 _amount) internal {
        if (address(this).balance >= _amount) {
            TransferHelper.transferETH(msg.sender, _amount, 0);
        }
    }
}
