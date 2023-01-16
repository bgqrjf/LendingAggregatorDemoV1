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
        require(_params.actionNotPaused, "BorrowLogic: actionPaused");

        require(
            _params.userParams.amount > 0,
            "Router: Borrow 0 token is not allowed"
        );
        require(
            borrowAllowed(_params, msg.sender, assets),
            "Router: Insufficient collateral"
        );

        if (address(_params.reservePool) != address(0)) {
            _params.reservePool.borrow(
                _params.userParams,
                msg.sender,
                _params.executeNow
            );
        } else {
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

            recordBorrow(
                Types.RecordBorrowParams(
                    _params.userParams,
                    newInterest,
                    protocolsBorrows + totalLending + reservePoolLentAmount,
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

            executeBorrow(_params, totalLending, totalLendings);
        }
    }

    function borrowAllowed(
        Types.BorrowParams memory _params,
        address _borrower,
        mapping(address => Types.Asset) storage assets
    ) internal view returns (bool) {
        uint256 maxDebtAllowed = borrowLimit(
            _params.config,
            _params.priceOracle,
            _borrower,
            _params.userParams.asset,
            _params.underlyings,
            assets
        );
        uint256 currentDebts = ExternalUtils.getUserDebts(
            _borrower,
            _params.config.userDebtAndCollateral(_borrower),
            _params.underlyings,
            _params.userParams.asset,
            _params.priceOracle,
            assets
        );

        return currentDebts + _params.userParams.amount <= maxDebtAllowed;
    }

    function borrowLimit(
        IConfig _config,
        IPriceOracle _priceOracle,
        address _account,
        address _borrowAsset,
        address[] memory _underlyings,
        mapping(address => Types.Asset) storage assets
    ) public view returns (uint256 amount) {
        uint256 userConfig = _config.userDebtAndCollateral(_account);

        for (uint256 i = 0; i < _underlyings.length; ++i) {
            if (userConfig.isUsingAsCollateral(i)) {
                address underlying = _underlyings[i];
                Types.Asset memory asset = assets[underlying];

                if (asset.paused) {
                    continue;
                }

                uint256 collateralAmount = underlying == _borrowAsset
                    ? asset.sToken.scaledBalanceOf(_account)
                    : _priceOracle.valueOfAsset(
                        underlying,
                        _borrowAsset,
                        asset.sToken.scaledBalanceOf(_account)
                    );

                amount +=
                    (_config.assetConfigs(underlying).maxLTV *
                        collateralAmount) /
                    Utils.MILLION;
            }
        }
    }

    function recordBorrow(
        Types.RecordBorrowParams memory _params,
        mapping(address => Types.Asset) storage assets,
        mapping(address => uint256) storage accFees,
        mapping(address => uint256) storage accFeeOffsets,
        mapping(address => uint256) storage feeIndexes,
        mapping(address => mapping(address => uint256)) storage userFeeIndexes
    ) public {
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

        _params.config.setBorrowing(_params.borrowBy, asset.index, true);

        emit Borrowed(
            _params.borrowBy,
            _params.userParams.asset,
            _params.userParams.amount
        );
    }

    function executeBorrow(
        Types.BorrowParams memory _params,
        uint256 _totalLending,
        mapping(address => uint256) storage totalLendings
    ) public {
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
