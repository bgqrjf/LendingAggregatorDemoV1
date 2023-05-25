// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../interfaces/IConfig.sol";
import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";

import "../internals/ExternalUtils.sol";
import "../internals/TransferHelper.sol";
import "../internals/Types.sol";

library BorrowLogic {
    using UserAssetBitMap for uint256;

    event Borrowed(
        address indexed borrower,
        address indexed asset,
        uint256 amount
    );

    function borrow(
        Types.BorrowParams memory _params,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets,
        mapping(address => uint256) storage totalLendings
    ) external {
        require(_params.actionNotPaused, "BorrowLogic: action paused");
        require(
            address(assets[_params.userParams.asset].dToken) != address(0),
            "BorrowLogic: asset not exists"
        );

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

        recordBorrowInternal(
            Types.RecordBorrowParams(
                _params.userParams,
                newInterest,
                totalBorrowedAmount,
                msg.sender
            ),
            assets
        );

        if (address(_params.reservePool) != address(0)) {
            _params.reservePool.borrow(_params.userParams, _params.executeNow);
        } else {
            executeBorrowInternal(
                _params.userParams,
                _params.protocols,
                totalLending,
                totalLendings
            );
        }

        if (assets[_params.userParams.asset].dToken.balanceOf(msg.sender) > 0) {
            _params.config.setBorrowing(
                msg.sender,
                _params.userParams.asset,
                true
            );
        }

        (bool isHealthy, , ) = ExternalUtils.isPositionHealthy(
            _params.config,
            _params.priceOracle,
            msg.sender,
            _params.userParams.asset,
            underlyings,
            assets
        );

        require(isHealthy, "BorrowLogic: Insufficient collateral");

        emit Borrowed(
            msg.sender,
            _params.userParams.asset,
            _params.userParams.amount
        );
    }

    function recordBorrow(
        Types.RecordBorrowParams memory _params,
        mapping(address => Types.Asset) storage assets
    ) external {
        recordBorrowInternal(_params, assets);
    }

    function executeBorrow(
        Types.UserAssetParams memory _params,
        IProtocolsHandler _protocols,
        uint256 _totalLending,
        mapping(address => uint256) storage totalLendings
    ) external {
        executeBorrowInternal(
            _params,
            _protocols,
            _totalLending,
            totalLendings
        );
    }

    function borrowLimit(
        IConfig _config,
        IPriceOracle _priceOracle,
        address _account,
        address _borrowAsset,
        address[] storage underlyings,
        mapping(address => Types.Asset) storage assets
    ) external view returns (uint256 amount) {
        return
            ExternalUtils.borrowLimitInternal(
                _config.userDebtAndCollateral(_account),
                _config.assetConfigs(_borrowAsset).maxLTV,
                _priceOracle,
                _account,
                _borrowAsset,
                underlyings,
                assets
            );
    }

    function recordBorrowInternal(
        Types.RecordBorrowParams memory _params,
        mapping(address => Types.Asset) storage assets
    ) internal {
        assets[_params.userParams.asset].dToken.mint(
            _params.borrowBy,
            _params.userParams.amount,
            _params.totalBorrows,
            _params.newInterest
        );
    }

    function executeBorrowInternal(
        Types.UserAssetParams memory _params,
        IProtocolsHandler _protocols,
        uint256 _totalLending,
        mapping(address => uint256) storage totalLendings
    ) internal {
        (, uint256 protocolsSupplies) = _protocols.totalSupplied(_params.asset);

        (uint256 redeemed, ) = _protocols.redeemAndBorrow(
            _params.asset,
            _params.amount,
            protocolsSupplies,
            _params.to
        );

        ExternalUtils.updateTotalLendings(
            _protocols,
            _params.asset,
            _totalLending + redeemed,
            totalLendings
        );
    }
}
