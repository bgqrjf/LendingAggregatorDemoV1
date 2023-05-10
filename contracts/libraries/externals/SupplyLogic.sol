// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../interfaces/IConfig.sol";
import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";

import "../internals/ExternalUtils.sol";
import "../internals/TransferHelper.sol";
import "../internals/Types.sol";

library SupplyLogic {
    event Supplied(
        address indexed supplier,
        address indexed asset,
        uint256 amount
    );

    function supply(
        Types.SupplyParams memory _params,
        mapping(address => uint256) storage totalLendings
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
            TransferHelper.collect(
                _params.userParams.asset,
                msg.sender,
                address(_params.protocols),
                _params.userParams.amount,
                0 // gasLimit
            );

            (
                ,
                uint256 protocolsSupplies,
                uint256 totalLending,
                uint256 totalSuppliedAmountWithFee,
                uint256 newInterest
            ) = ExternalUtils.getSupplyStatus(
                    _params.userParams.asset,
                    _params.reservePool,
                    _params.protocols,
                    totalLendings
                );

            recordSupplyInternal(
                Types.RecordSupplyParams(
                    _params.userParams,
                    _params.asset.sToken,
                    _params.asset.dToken,
                    totalSuppliedAmountWithFee,
                    newInterest
                )
            );

            executeSupplyInternal(
                Types.ExecuteSupplyParams(
                    _params.userParams.asset,
                    _params.userParams.amount,
                    totalLending,
                    protocolsSupplies
                ),
                _params.protocols,
                totalLendings
            );
        }

        if (_params.userParams.to == msg.sender) {
            _params.config.setUsingAsCollateral(
                _params.userParams.to,
                _params.userParams.asset,
                _params.asset.collateralable && _params.collateralable
            );
        }
    }

    function recordSupply(Types.RecordSupplyParams memory _params) external {
        recordSupplyInternal(_params);
    }

    function executeSupply(
        Types.ExecuteSupplyParams memory _params,
        IProtocolsHandler _protocols,
        mapping(address => uint256) storage totalLendings
    ) external {
        executeSupplyInternal(_params, _protocols, totalLendings);
    }

    function recordSupplyInternal(
        Types.RecordSupplyParams memory _params
    ) internal {
        uint256 uncollectedFee = _params.dToken.updateNewFee(
            _params.newInterest
        );

        _params.sToken.mint(
            _params.userParams.to,
            _params.userParams.amount,
            _params.totalUnderlying - uncollectedFee
        );

        emit Supplied(
            _params.userParams.to,
            _params.userParams.asset,
            _params.userParams.amount
        );
    }

    function executeSupplyInternal(
        Types.ExecuteSupplyParams memory _params,
        IProtocolsHandler _protocols,
        mapping(address => uint256) storage totalLendings
    ) internal {
        (uint256 repayed, ) = _protocols.repayAndSupply(
            _params.asset,
            _params.amount
        );

        ExternalUtils.updateTotalLendings(
            _protocols,
            _params.asset,
            _params.totalLending + repayed,
            totalLendings
        );
    }
}
