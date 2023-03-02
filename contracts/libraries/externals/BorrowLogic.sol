// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../internals/ExternalUtils.sol";
import "../internals/TransferHelper.sol";
import "../internals/Types.sol";

import "../../interfaces/IProtocolsHandler.sol";
import "../../interfaces/IReservePool.sol";
import "../../interfaces/IRewards.sol";
import "../../interfaces/IConfig.sol";

library BorrowLogic {
    using UserAssetBitMap for uint256;

    event Borrowed(
        address indexed borrower,
        address indexed asset,
        uint256 amount
    );

    function borrow(
        Types.BorrowParams memory _params,
        mapping(address => Types.Asset) storage assets,
        mapping(address => uint256) storage totalLendings,
        mapping(address => uint256) storage accFees,
        mapping(address => uint256) storage accFeeOffsets,
        mapping(address => uint256) storage feeIndexes,
        mapping(address => mapping(address => uint256)) storage userFeeIndexes
    ) external {
        require(_params.actionNotPaused, "BorrowLogic: action paused");

        require(
            _params.userParams.amount > 0,
            "BorrowLogic: Borrow 0 token is not allowed"
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
                msg.sender,
                _params.config,
                _params.rewards
            ),
            assets,
            accFees,
            accFeeOffsets,
            feeIndexes,
            userFeeIndexes
        );

        if (address(_params.reservePool) != address(0)) {
            _params.reservePool.borrow(_params.userParams, _params.executeNow);
        } else {
            executeBorrowInternal(_params, totalLending, totalLendings);
        }

        (bool isHealthy, , ) = ExternalUtils.isPositionHealthy(
            _params.config,
            _params.priceOracle,
            msg.sender,
            _params.userParams.asset,
            _params.underlyings,
            assets
        );

        require(isHealthy, "BorrowLogic: Insufficient collateral");
    }

    function recordBorrow(
        Types.RecordBorrowParams memory _params,
        mapping(address => Types.Asset) storage assets,
        mapping(address => uint256) storage accFees,
        mapping(address => uint256) storage accFeeOffsets,
        mapping(address => uint256) storage feeIndexes,
        mapping(address => mapping(address => uint256)) storage userFeeIndexes
    ) external {
        recordBorrowInternal(
            _params,
            assets,
            accFees,
            accFeeOffsets,
            feeIndexes,
            userFeeIndexes
        );
    }

    function executeBorrow(
        Types.BorrowParams memory _params,
        uint256 _totalLending,
        mapping(address => uint256) storage totalLendings
    ) external {
        executeBorrowInternal(_params, _totalLending, totalLendings);
    }

    function borrowLimit(
        IConfig _config,
        IPriceOracle _priceOracle,
        address _account,
        address _borrowAsset,
        address[] memory _underlyings,
        mapping(address => Types.Asset) storage assets
    ) external view returns (uint256 amount) {
        return
            ExternalUtils.borrowLimitInternal(
                _config.userDebtAndCollateral(_account),
                _config.assetConfigs(_borrowAsset).maxLTV,
                _priceOracle,
                _account,
                _borrowAsset,
                _underlyings,
                assets
            );
    }

    function recordBorrowInternal(
        Types.RecordBorrowParams memory _params,
        mapping(address => Types.Asset) storage assets,
        mapping(address => uint256) storage accFees,
        mapping(address => uint256) storage accFeeOffsets,
        mapping(address => uint256) storage feeIndexes,
        mapping(address => mapping(address => uint256)) storage userFeeIndexes
    ) internal {
        Types.Asset memory asset = assets[_params.userParams.asset];

        uint256 accFee = ExternalUtils.updateAccFee(
            _params.userParams.asset,
            _params.newInterest,
            _params.config,
            accFees
        );

        // to silence stack too deep
        accFee += accFeeOffsets[_params.userParams.asset];

        uint256 dTokenTotalSupply = asset.dToken.totalSupply();
        uint256 feeIndex = ExternalUtils.updateFeeIndex(
            _params.userParams.asset,
            dTokenTotalSupply,
            accFee,
            feeIndexes
        );

        uint256 dTokenAmount = asset.dToken.mint(
            _params.borrowBy,
            _params.userParams.amount,
            _params.totalBorrows
        );

        ExternalUtils.updateUserFeeIndex(
            _params.userParams.asset,
            _params.borrowBy,
            asset.dToken.balanceOf(_params.borrowBy),
            dTokenAmount,
            feeIndex,
            userFeeIndexes
        );

        ExternalUtils.updateAccFeeOffset(
            _params.userParams.asset,
            feeIndex,
            dTokenAmount,
            accFeeOffsets
        );

        _params.rewards.startMiningBorrowReward(
            _params.userParams.asset,
            _params.borrowBy,
            dTokenAmount,
            dTokenTotalSupply
        );

        _params.config.setBorrowing(
            _params.borrowBy,
            _params.userParams.asset,
            true
        );

        emit Borrowed(
            _params.borrowBy,
            _params.userParams.asset,
            _params.userParams.amount
        );
    }

    function executeBorrowInternal(
        Types.BorrowParams memory _params,
        uint256 _totalLending,
        mapping(address => uint256) storage totalLendings
    ) internal {
        IProtocolsHandler protocolsCache = _params.protocols;

        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_params.userParams.asset);

        (uint256 redeemed, ) = protocolsCache.redeemAndBorrow(
            _params.userParams.asset,
            _params.userParams.amount,
            supplies,
            protocolsSupplies,
            _params.userParams.to
        );

        ExternalUtils.updateTotalLendings(
            protocolsCache,
            _params.userParams.asset,
            _totalLending + redeemed,
            totalLendings
        );
    }
}
