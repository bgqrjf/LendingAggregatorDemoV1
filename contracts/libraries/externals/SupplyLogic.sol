// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../internals/ExternalUtils.sol";
import "../internals/TransferHelper.sol";
import "../internals/Types.sol";

import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";
import "../../interfaces/IConfig.sol";

library SupplyLogic {
    event Supplied(
        address indexed supplier,
        address indexed asset,
        uint256 amount
    );

    function supply(
        Types.SupplyParams memory _params,
        mapping(address => uint256) storage totalLendings,
        mapping(address => uint256) storage accFees
    ) external {
        require(_params.actionNotPaused, "SupplyLogic: action paused");

        if (address(_params.reservePool) != address(0)) {
            TransferHelper.collect(
                _params.userParams.asset,
                msg.sender,
                address(_params.reservePool),
                _params.userParams.amount,
                0 // gasLimit
            );

            _params.reservePool.supply(
                _params.userParams,
                _params.collateralable,
                _params.executeNow
            );
        } else {
            (
                uint256[] memory supplies,
                uint256 protocolsSupplies,
                uint256 totalLending,
                uint256 totalBorrowedAmountWithFee,
                uint256 newInterest
            ) = ExternalUtils.getSupplyStatus(
                    _params.userParams.asset,
                    _params.reservePool,
                    _params.protocols,
                    totalLendings
                );

            recordSupplyInternal(
                _params,
                totalBorrowedAmountWithFee,
                newInterest,
                accFees
            );

            TransferHelper.collect(
                _params.userParams.asset,
                msg.sender,
                address(_params.protocols),
                _params.userParams.amount,
                0 // gasLimit
            );

            executeSupplyInternal(
                _params,
                totalLending,
                supplies,
                protocolsSupplies,
                totalLendings
            );
        }
    }

    function recordSupply(
        Types.SupplyParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        mapping(address => uint256) storage accFees
    ) external {
        recordSupplyInternal(_params, _totalSupplies, _newInterest, accFees);
    }

    function executeSupply(
        Types.SupplyParams memory _params,
        uint256 _totalLending,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        mapping(address => uint256) storage totalLendings
    ) external {
        executeSupplyInternal(
            _params,
            _totalLending,
            _supplies,
            _protocolsSupplies,
            totalLendings
        );
    }

    function recordSupplyInternal(
        Types.SupplyParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        mapping(address => uint256) storage accFees
    ) internal {
        ExternalUtils.updateAccFee(
            _params.userParams.asset,
            _newInterest,
            _params.config,
            accFees
        );

        uint256 sTokenAmount = _params.asset.sToken.mint(
            _params.userParams.to,
            _params.userParams.amount,
            _totalSupplies
        );

        _params.rewards.startMiningSupplyReward(
            _params.userParams.asset,
            _params.userParams.to,
            sTokenAmount,
            _params.asset.sToken.totalSupply()
        );

        _params.config.setUsingAsCollateral(
            _params.userParams.to,
            _params.asset.index,
            _params.asset.collateralable && _params.collateralable
        );

        emit Supplied(
            _params.userParams.to,
            _params.userParams.asset,
            _params.userParams.amount
        );
    }

    function executeSupplyInternal(
        Types.SupplyParams memory _params,
        uint256 _totalLending,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        mapping(address => uint256) storage totalLendings
    ) internal {
        (uint256 repayed, ) = _params.protocols.repayAndSupply(
            _params.userParams.asset,
            _params.userParams.amount,
            _supplies,
            _protocolsSupplies
        );

        if (repayed > 0) {
            ExternalUtils.updateTotalLendings(
                _params.protocols,
                _params.userParams.asset,
                _totalLending + repayed,
                totalLendings
            );
        }
    }
}
