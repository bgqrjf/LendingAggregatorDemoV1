// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../internals/ExternalUtils.sol";
import "../internals/TransferHelper.sol";
import "../internals/Types.sol";

import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";
import "../../interfaces/IConfig.sol";

library RedeemLogic {
    event Redeemed(
        address indexed supplier,
        address indexed asset,
        uint256 amount
    );

    function redeem(
        Types.RedeemParams memory _params,
        mapping(address => uint256) storage totalLendings,
        mapping(address => uint256) storage accFees
    ) external {
        require(_params.actionNotPaused, "RedeemLogic: action paused");

        if (address(_params.reservePool) != address(0)) {
            _params.reservePool.redeem(
                _params.userParams,
                msg.sender,
                _params.executeNow,
                _params.collateralable
            );
        } else {
            (
                uint256[] memory supplies,
                uint256 protocolsSupplies,
                uint256 totalLending,
                uint256 newInterest
            ) = ExternalUtils.getSupplyStatus(
                    _params.userParams.asset,
                    _params.protocols,
                    totalLendings
                );

            uint256 uncollectedFee;
            (_params.userParams.amount, uncollectedFee) = recordRedeemInternal(
                _params,
                protocolsSupplies + totalLending,
                newInterest,
                msg.sender,
                accFees
            );

            executeRedeemInternal(
                _params,
                supplies,
                protocolsSupplies,
                totalLending,
                uncollectedFee,
                totalLendings
            );
        }
    }

    function recordRedeem(
        Types.RedeemParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        address _redeemFrom,
        mapping(address => uint256) storage accFees
    ) external returns (uint256 underlyingAmount, uint256 fee) {
        return
            recordRedeemInternal(
                _params,
                _totalSupplies,
                _newInterest,
                _redeemFrom,
                accFees
            );
    }

    function executeRedeem(
        Types.RedeemParams memory _params,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending,
        uint256 _uncollectedFee,
        mapping(address => uint256) storage totalLendings
    ) external {
        executeRedeemInternal(
            _params,
            _supplies,
            _protocolsSupplies,
            _totalLending,
            _uncollectedFee,
            totalLendings
        );
    }

    function recordRedeemInternal(
        Types.RedeemParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        address _redeemFrom,
        mapping(address => uint256) storage accFees
    ) internal returns (uint256 underlyingAmount, uint256 fee) {
        uint256 accFee = ExternalUtils.updateAccFee(
            _params.userParams.asset,
            _newInterest,
            _params.config,
            accFees
        ) - _params.collectedFee;

        uint256 sTokenAmount = _params.asset.sToken.unscaledAmount(
            _params.userParams.amount,
            _totalSupplies
        );

        // to prevent stack too deep
        {
            uint256 sTokenBalance = _params.asset.sToken.balanceOf(_redeemFrom);
            if (sTokenAmount >= sTokenBalance) {
                sTokenAmount = sTokenBalance;
                _params.collateralable = false;
            }
        }

        (underlyingAmount, fee) = _params.asset.sToken.burn(
            _redeemFrom,
            sTokenAmount,
            _totalSupplies,
            accFee
        );

        _params.rewards.stopMiningSupplyReward(
            _params.userParams.asset,
            _redeemFrom,
            sTokenAmount,
            _params.asset.sToken.totalSupply() + sTokenAmount
        );

        _params.config.setUsingAsCollateral(
            _redeemFrom,
            _params.asset.index,
            _params.asset.collateralable && _params.collateralable
        );

        emit Redeemed(_redeemFrom, _params.userParams.asset, underlyingAmount);
    }

    function executeRedeemInternal(
        Types.RedeemParams memory _params,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending,
        uint256 _uncollectedFee,
        mapping(address => uint256) storage totalLendings
    ) internal {
        IProtocolsHandler protocolsCache = _params.protocols;

        (, uint256 borrowed) = protocolsCache.redeemAndBorrow(
            _params.userParams.asset,
            _params.userParams.amount,
            _supplies,
            _protocolsSupplies,
            _params.userParams.to
        );

        uint256 totalLendingDelta = borrowed + _uncollectedFee;
        if (totalLendingDelta > 0) {
            //  uncollectedFee may cause underflow
            _totalLending = _totalLending > totalLendingDelta
                ? _totalLending - totalLendingDelta
                : 0;
            ExternalUtils.updateTotalLendings(
                protocolsCache,
                _params.userParams.asset,
                _totalLending,
                totalLendings
            );
        }
    }
}
