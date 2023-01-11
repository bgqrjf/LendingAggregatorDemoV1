// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./storages/RouterStorage.sol";

import "./libraries/TransferHelper.sol";
import "./libraries/UserAssetBitMap.sol";
import "./libraries/Utils.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract Router is RouterStorage, OwnableUpgradeable {
    using Math for uint256;
    using UserAssetBitMap for uint256;

    modifier onlyReservePool() {
        require(msg.sender == address(reservePool), "Router: onlyReservePool");
        _;
    }

    receive() external payable {}

    function initialize(
        address _protocolsHandler,
        address _priceOracle,
        address _config,
        address _rewards,
        address _sToken,
        address _dToken,
        address payable _reservePool,
        address payable _feeCollector
    ) external initializer {
        __Ownable_init();

        priceOracle = IPriceOracle(_priceOracle);
        protocols = IProtocolsHandler(_protocolsHandler);
        config = IConfig(_config);
        rewards = IRewards(_rewards);
        reservePool = IReservePool(_reservePool);
        sTokenImplement = _sToken;
        dTokenImplement = _dToken;
        feeCollector = _feeCollector;
    }

    // user externals
    function supply(
        Types.UserAssetParams memory _params,
        bool _collateralable,
        bool _executeNow
    ) external payable override {
        actionNotPaused(_params.asset, uint256(Action.supply));
        require(!tokenPaused[_params.asset], "Router: token paused");

        IReservePool reservePoolCache = reservePool;

        if (address(reservePoolCache) != address(0)) {
            TransferHelper.collect(
                _params.asset,
                msg.sender,
                address(reservePoolCache),
                _params.amount,
                0 // gasLimit
            );

            reservePoolCache.supply(_params, _executeNow, _collateralable);
        } else {
            (
                uint256[] memory supplies,
                uint256 protocolsSupplies,
                uint256 totalLending,
                uint256 newInterest
            ) = getSupplyStatus(_params.asset);

            _recordSupply(
                _params,
                protocolsSupplies + totalLending,
                newInterest,
                _collateralable
            );

            TransferHelper.collect(
                _params.asset,
                msg.sender,
                address(protocols),
                _params.amount,
                0 // gasLimit
            );

            _executeSupply(
                _params.asset,
                _params.amount,
                totalLending,
                supplies,
                protocolsSupplies
            );
        }
    }

    function redeem(
        Types.UserAssetParams memory _params,
        bool _collateralable,
        bool _executeNow
    ) external override {
        actionNotPaused(_params.asset, uint256(Action.redeem));

        IReservePool reservePoolCache = reservePool;

        if (address(reservePoolCache) != address(0)) {
            reservePoolCache.redeem(
                _params,
                msg.sender,
                _executeNow,
                _collateralable
            );
        } else {
            (
                uint256[] memory supplies,
                uint256 protocolsSupplies,
                uint256 totalLending,
                uint256 newInterest
            ) = getSupplyStatus(_params.asset);

            uint256 uncollectedFee;
            (_params.amount, uncollectedFee) = _recordRedeem(
                _params,
                protocolsSupplies + totalLending,
                newInterest,
                msg.sender,
                _collateralable
            );

            _executeRedeem(
                _params,
                supplies,
                protocolsSupplies,
                totalLending,
                uncollectedFee
            );
        }
    }

    function borrow(Types.UserAssetParams memory _params, bool _executeNow)
        external
        override
    {
        actionNotPaused(_params.asset, uint256(Action.borrow));

        require(_params.amount > 0, "Router: Borrow 0 token is not allowed");
        require(
            borrowAllowed(msg.sender, _params),
            "Router: Insufficient collateral"
        );

        IReservePool reservePoolCache = reservePool;

        if (address(reservePoolCache) != address(0)) {
            reservePoolCache.borrow(_params, msg.sender, _executeNow);
        } else {
            (
                ,
                uint256 protocolsBorrows,
                uint256 totalLending,
                uint256 reservePoolLentAmount,
                uint256 newInterest
            ) = getBorrowStatus(_params.asset);

            _recordBorrow(
                _params,
                newInterest,
                protocolsBorrows + totalLending + reservePoolLentAmount,
                msg.sender
            );

            _executeBorrow(_params, totalLending);
        }
    }

    function repay(Types.UserAssetParams memory _params, bool _executeNow)
        external
        payable
    {
        actionNotPaused(_params.asset, uint256(Action.repay));
        _repay(_params, _executeNow);
    }

    // reservePool callbacks
    function recordSupply(
        Types.UserAssetParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        bool _collateralable
    ) external override onlyReservePool {
        _recordSupply(_params, _totalSupplies, _newInterest, _collateralable);
    }

    function recordRedeem(
        Types.UserAssetParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        address _redeemFrom,
        bool _collateralable
    )
        external
        override
        onlyReservePool
        returns (uint256 underlyingAmount, uint256 fee)
    {
        return
            _recordRedeem(
                _params,
                _totalSupplies,
                _newInterest,
                _redeemFrom,
                _collateralable
            );
    }

    function recordBorrow(
        Types.UserAssetParams memory _params,
        uint256 _newInterest,
        uint256 _totalBorrows,
        address _borrowBy
    ) external override onlyReservePool {
        _recordBorrow(_params, _newInterest, _totalBorrows, _borrowBy);
    }

    function recordRepay(
        Types.UserAssetParams memory _params,
        uint256 newInterest,
        uint256 totalBorrows
    ) internal returns (uint256 repayAmount, uint256 fee) {
        Types.Asset memory asset = assets[_params.asset];

        uint256 dTokenTotalSupply = asset.dToken.totalSupply();
        uint256 userDebts = asset.dToken.scaledAmount(
            asset.dToken.balanceOf(_params.to),
            totalBorrows
        );

        repayAmount = _params.amount;
        if (repayAmount >= userDebts) {
            repayAmount = userDebts;
            config.setBorrowing(_params.to, asset.index, false);
        }

        uint256 dTokenAmount = asset.dToken.burn(
            _params.to,
            repayAmount,
            totalBorrows
        );

        uint256 accFee = updateAccFee(_params.asset, newInterest);
        uint256 feeIndex = updateFeeIndex(
            _params.asset,
            dTokenTotalSupply,
            accFee + accFeeOffsets[_params.asset]
        );

        fee =
            ((feeIndex - userFeeIndexes[_params.to][_params.asset]) *
                dTokenAmount) /
            Utils.QUINTILLION;

        collectedFees[_params.asset] += fee;

        rewards.stopMiningBorrowReward(
            _params.asset,
            _params.to,
            dTokenAmount,
            dTokenTotalSupply
        );

        emit Repayed(_params.to, _params.asset, repayAmount);
    }

    function executeSupply(
        address _asset,
        uint256 _amount,
        uint256 _totalLending,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies
    ) external payable override onlyReservePool {
        _executeSupply(
            _asset,
            _amount,
            _totalLending,
            _supplies,
            _protocolsSupplies
        );
    }

    function executeRedeem(
        Types.UserAssetParams memory _params,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending,
        uint256 _uncollectedFee
    ) external override onlyReservePool {
        _executeRedeem(
            _params,
            _supplies,
            _protocolsSupplies,
            _totalLending,
            _uncollectedFee
        );
    }

    function executeBorrow(
        Types.UserAssetParams memory _params,
        uint256 _totalLending
    ) external override onlyReservePool {
        _executeBorrow(_params, _totalLending);
    }

    function executeRepay(
        address _asset,
        uint256 _amount,
        uint256 _totalLending
    ) external override onlyReservePool {
        _executeRepay(_asset, _amount, _totalLending);
    }

    // internals
    function _repay(Types.UserAssetParams memory _params, bool _executeNow)
        internal
        returns (uint256 amount)
    {
        IReservePool reservePoolCache = reservePool;
        IProtocolsHandler protocolsCache = protocols;

        (
            ,
            uint256 protocolsBorrows,
            uint256 totalLending,
            uint256 reservePoolLentAmount,
            uint256 newInterest
        ) = getBorrowStatus(_params.asset);

        uint256 fee;
        (amount, fee) = recordRepay(
            _params,
            newInterest,
            protocolsBorrows + totalLending + reservePoolLentAmount
        );

        TransferHelper.collect(_params.asset, msg.sender, feeCollector, fee, 0);
        emit FeeCollected(_params.asset, feeCollector, fee);

        if (_params.asset == TransferHelper.ETH && _params.amount > amount) {
            refundETH(_params.amount - amount);
        }

        if (address(reservePoolCache) != address(0)) {
            TransferHelper.collect(
                _params.asset,
                msg.sender,
                address(reservePoolCache),
                amount - fee,
                0
            );

            reservePool.repay(_params, _executeNow);
        } else {
            TransferHelper.collect(
                _params.asset,
                msg.sender,
                address(protocolsCache),
                amount - fee,
                0
            );

            _executeRepay(_params.asset, amount - fee, totalLending);
        }

        updateTotalLendings(
            protocolsCache,
            _params.asset,
            totalLending > fee ? totalLending - fee : 0
        );
    }

    function _recordSupply(
        Types.UserAssetParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        bool _collateralable
    ) internal {
        Types.Asset memory asset = assets[_params.asset];

        updateAccFee(_params.asset, _newInterest);

        uint256 sTokenAmount = asset.sToken.mint(
            _params.to,
            _params.amount,
            _totalSupplies
        );

        rewards.startMiningSupplyReward(
            _params.asset,
            _params.to,
            sTokenAmount,
            asset.sToken.totalSupply()
        );

        config.setUsingAsCollateral(
            _params.to,
            asset.index,
            asset.collateralable && _collateralable
        );

        emit Supplied(_params.to, _params.asset, _params.amount);
    }

    function _recordRedeem(
        Types.UserAssetParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        address _redeemFrom,
        bool _collateralable
    ) internal returns (uint256 underlyingAmount, uint256 fee) {
        Types.Asset memory asset = assets[_params.asset];

        uint256 accFee = updateAccFee(_params.asset, _newInterest) -
            collectedFees[_params.asset];

        uint256 sTokenAmount = assets[_params.asset].sToken.unscaledAmount(
            _params.amount,
            _totalSupplies
        );

        uint256 sTokenBalance = asset.sToken.balanceOf(_redeemFrom);
        if (sTokenAmount >= sTokenBalance) {
            sTokenAmount = sTokenBalance;
            _collateralable = false;
        }

        (underlyingAmount, fee) = asset.sToken.burn(
            _redeemFrom,
            sTokenAmount,
            _totalSupplies,
            accFee
        );

        rewards.stopMiningSupplyReward(
            _params.asset,
            _redeemFrom,
            sTokenAmount,
            asset.sToken.totalSupply() + sTokenAmount
        );

        config.setUsingAsCollateral(
            _redeemFrom,
            asset.index,
            asset.collateralable && _collateralable
        );

        emit Redeemed(_redeemFrom, _params.asset, underlyingAmount);
    }

    function _recordBorrow(
        Types.UserAssetParams memory _params,
        uint256 _newInterest,
        uint256 _totalBorrows,
        address _borrowBy
    ) internal {
        Types.Asset memory asset = assets[_params.asset];

        uint256 accFee = updateAccFee(_params.asset, _newInterest);

        uint256 dTokenTotalSupply = asset.dToken.totalSupply();
        uint256 feeIndex = updateFeeIndex(
            _params.asset,
            dTokenTotalSupply,
            accFee + accFeeOffsets[_params.asset]
        );

        uint256 dTokenAmount = asset.dToken.mint(
            _borrowBy,
            _params.amount,
            _totalBorrows
        );

        updateUserFeeIndex(
            _params.asset,
            _borrowBy,
            asset.dToken.balanceOf(_borrowBy),
            dTokenAmount,
            feeIndex
        );
        updateAccFeeOffset(_params.asset, feeIndex, dTokenAmount);

        rewards.startMiningBorrowReward(
            _params.asset,
            _borrowBy,
            dTokenAmount,
            dTokenTotalSupply
        );

        config.setBorrowing(_borrowBy, asset.index, true);

        emit Borrowed(_borrowBy, _params.asset, _params.amount);
    }

    function _executeSupply(
        address _asset,
        uint256 _amount,
        uint256 _totalLending,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies
    ) internal {
        IProtocolsHandler protocolsCache = protocols;

        (uint256 repayed, ) = protocolsCache.repayAndSupply(
            _asset,
            _amount,
            _supplies,
            _protocolsSupplies
        );

        if (repayed > 0) {
            updateTotalLendings(
                protocolsCache,
                _asset,
                _totalLending + repayed
            );
        }
    }

    function _executeRedeem(
        Types.UserAssetParams memory _params,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending,
        uint256 _uncollectedFee
    ) internal {
        IProtocolsHandler protocolsCache = protocols;

        (, uint256 borrowed) = protocolsCache.redeemAndBorrow(
            _params.asset,
            _params.amount,
            _supplies,
            _protocolsSupplies,
            _params.to
        );

        uint256 totalLendingDelta = borrowed + _uncollectedFee;
        if (totalLendingDelta > 0) {
            //  uncollectedFee may cause underflow
            _totalLending = _totalLending > totalLendingDelta
                ? _totalLending - totalLendingDelta
                : 0;
            updateTotalLendings(protocolsCache, _params.asset, _totalLending);
        }
    }

    function _executeBorrow(
        Types.UserAssetParams memory _params,
        uint256 _totalLending
    ) internal {
        IProtocolsHandler protocolsCache = protocols;

        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_params.asset);

        (uint256 redeemed, ) = protocolsCache.redeemAndBorrow(
            _params.asset,
            _params.amount,
            supplies,
            protocolsSupplies,
            _params.to
        );

        updateTotalLendings(
            protocolsCache,
            _params.asset,
            _totalLending + redeemed
        );
    }

    function _executeRepay(
        address _asset,
        uint256 _amount,
        uint256 _totalLending
    ) internal {
        IProtocolsHandler protocolsCache = protocols;

        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_asset);

        (, uint256 supplied) = protocolsCache.repayAndSupply(
            _asset,
            _amount,
            supplies,
            protocolsSupplies
        );

        updateTotalLendings(
            protocolsCache,
            _asset,
            _totalLending > supplied ? _totalLending - supplied : 0
        );
    }

    // --
    function liquidate(
        Types.UserAssetParams memory _repayParams,
        Types.UserAssetParams memory _redeemParams
    ) external payable {
        actionNotPaused(_repayParams.asset, uint256(Action.liquidate));

        _repayParams.amount = validateLiquidatation(
            _repayParams,
            _redeemParams
        );

        _repayParams.amount = _repay(_repayParams, true);

        IProtocolsHandler protocolsCache = protocols;
        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_redeemParams.asset);

        (uint256 totalLending, ) = protocolsCache.simulateLendings(
            _redeemParams.asset,
            totalLendings[_redeemParams.asset]
        );

        // preprocessing data
        {
            uint256 assetValue = priceOracle.valueOfAsset(
                _repayParams.asset,
                _redeemParams.asset,
                _repayParams.amount
            );

            _redeemParams.amount =
                (assetValue *
                    config
                        .assetConfigs(_redeemParams.asset)
                        .liquidateRewardRatio) /
                Utils.MILLION;
            // require(redeemAmount > _redeemParams.amount, "insufficient redeem amount");
        }
        uint256 uncollectedFee;
        (_redeemParams.amount, uncollectedFee) = recordLiquidateRedeem(
            _redeemParams,
            protocolsSupplies + totalLending
        );

        _executeRedeem(
            _redeemParams,
            supplies,
            protocolsSupplies,
            totalLending,
            uncollectedFee
        );
    }

    function claimRewards(address _account) external override {
        actionNotPaused(address(0), uint256(Action.claimRewards));
        uint256 userConfig = config.userDebtAndCollateral(_account);
        uint256[] memory rewardsToClaim;

        for (uint256 i = 0; i < underlyings.length; ++i) {
            if (userConfig.isUsingAsCollateralOrBorrowing(i)) {
                Types.Asset memory asset = assets[underlyings[i]];

                if (userConfig.isUsingAsCollateral(i)) {
                    address underlying = asset.sToken.underlying();
                    uint256[] memory amounts = rewards.claim(
                        underlying,
                        _account,
                        asset.sToken.totalSupply()
                    );

                    for (uint256 j = 0; j < amounts.length; j++) {
                        rewardsToClaim[j] += amounts[j];
                    }
                }

                if (userConfig.isBorrowing(i)) {
                    address underlying = asset.dToken.underlying();
                    uint256[] memory amounts = rewards.claim(
                        underlying,
                        _account,
                        asset.dToken.totalSupply()
                    );
                    for (uint256 j = 0; j < amounts.length; j++) {
                        rewardsToClaim[j] += amounts[j];
                    }
                }
            }
        }

        protocols.claimRewards(_account, rewardsToClaim);
    }

    function borrowAllowed(
        address _borrower,
        Types.UserAssetParams memory _params
    ) internal view returns (bool) {
        uint256 maxDebtAllowed = borrowLimit(_borrower, _params.asset);
        uint256 currentDebts = getUserDebts(
            _borrower,
            config.userDebtAndCollateral(_borrower),
            underlyings,
            _params.asset
        );
        return currentDebts + _params.amount <= maxDebtAllowed;
    }

    function getUserDebts(
        address _account,
        uint256 _userConfig,
        address[] memory _underlyings,
        address _quote
    ) internal view returns (uint256 amount) {
        for (uint256 i = 0; i < _underlyings.length; ++i) {
            if (_userConfig.isBorrowing(i)) {
                address underlying = _underlyings[i];
                uint256 balance = assets[underlying].dToken.scaledDebtOf(
                    _account
                );

                amount += underlying == _quote
                    ? balance
                    : priceOracle.valueOfAsset(underlying, _quote, balance);
            }
        }
    }

    function validateLiquidatation(
        Types.UserAssetParams memory _repayParams,
        Types.UserAssetParams memory _redeemParams
    ) internal view returns (uint256) {
        uint256 userConfig = config.userDebtAndCollateral(_repayParams.to);
        Types.Asset memory repayAsset = assets[_repayParams.asset];
        Types.Asset memory redeemAsset = assets[_redeemParams.asset];

        uint256 debtsValue = getUserDebts(
            _repayParams.to,
            userConfig,
            underlyings,
            _repayParams.asset
        );

        (
            uint256 liquidationThreshold,
            uint256 maxLiquidationAmount,
            bool blackListed
        ) = getLiquidationData(_repayParams.to, _repayParams.asset);

        require(
            tokenPaused[_redeemParams.asset] == blackListed,
            "Router: Paused token not liquidated"
        );

        require(
            userConfig.isUsingAsCollateral(redeemAsset.index),
            "Router: Token is not using as collateral"
        );

        require(
            userConfig.isBorrowing(repayAsset.index),
            "Router: Token is not borrowing"
        );

        require(
            debtsValue > liquidationThreshold,
            "Router: Liquidate not allowed"
        );

        return
            _repayParams.amount < maxLiquidationAmount
                ? _repayParams.amount
                : maxLiquidationAmount;
    }

    // record actions

    function recordLiquidateRedeem(
        Types.UserAssetParams memory _params,
        uint256 totalSupplies
    ) internal returns (uint256 underlyingAmount, uint256 fee) {
        Types.Asset memory asset = assets[_params.asset];

        uint256 totalSupply = asset.sToken.totalSupply();

        uint256 sTokenAmount = assets[_params.asset].sToken.unscaledAmount(
            _params.amount,
            totalSupplies
        );

        uint256 sTokenBalance = assets[_params.asset].sToken.balanceOf(
            _params.to
        );

        if (sTokenAmount > sTokenBalance) {
            sTokenAmount = sTokenBalance;
            config.setUsingAsCollateral(msg.sender, asset.index, false);
        }

        (underlyingAmount, fee) = assets[_params.asset].sToken.burn(
            _params.to,
            sTokenAmount,
            totalSupplies,
            accFees[_params.asset] - collectedFees[_params.asset]
        );

        rewards.stopMiningSupplyReward(
            _params.asset,
            msg.sender,
            underlyingAmount,
            totalSupply
        );
    }

    function sync(address _asset) external override {
        (uint256 totalLending, uint256 newInterest) = protocols
            .simulateLendings(_asset, totalLendings[_asset]);

        updateTotalLendings(protocols, _asset, totalLending);
        updateAccFee(_asset, newInterest);
    }

    function updateAccFee(address _asset, uint256 _newInterest)
        internal
        returns (uint256 accFee)
    {
        if (_newInterest > 0) {
            accFee = accFees[_asset];

            accFee +=
                (_newInterest * config.assetConfigs(_asset).feeRate) /
                Utils.MILLION;

            accFees[_asset] = accFee;
            emit AccFeeUpdated(_asset, accFee);
        }
    }

    function updateTotalLendings(
        IProtocolsHandler _protocol,
        address _asset,
        uint256 _new
    ) internal {
        _protocol.updateSimulates(_asset, _new);
        totalLendings[_asset] = _new;
        emit TotalLendingsUpdated(_asset, _new);
    }

    function updateFeeIndex(
        address _underlying,
        uint256 _totalSupply,
        uint256 _accFee
    ) internal returns (uint256 newIndex) {
        if (_totalSupply > 0) {
            newIndex = (_accFee * Utils.QUINTILLION) / _totalSupply;
            feeIndexes[_underlying] = newIndex;
            emit FeeIndexUpdated(_underlying, newIndex);
        } else {
            newIndex = feeIndexes[_underlying];
        }
    }

    function updateUserFeeIndex(
        address _underlying,
        address _account,
        uint256 _dTokenBalance,
        uint256 _newAmount,
        uint256 _feeIndex
    ) internal returns (uint256 newIndex) {
        if (_newAmount > 0) {
            newIndex =
                (((_feeIndex - userFeeIndexes[_account][_underlying]) *
                    (_dTokenBalance - _newAmount)) + (_feeIndex * _newAmount)) /
                _dTokenBalance;

            userFeeIndexes[_account][_underlying] = newIndex;

            emit UserFeeIndexUpdated(_account, _underlying, newIndex);
        } else {
            newIndex = userFeeIndexes[_account][_underlying];
        }
    }

    function updateAccFeeOffset(
        address _asset,
        uint256 _feeIndex,
        uint256 _newOffset
    ) internal {
        if (_newOffset > 0) {
            uint256 newFeeOffset = accFeeOffsets[_asset] +
                (_feeIndex * _newOffset).ceilDiv(Utils.QUINTILLION);

            accFeeOffsets[_asset] = newFeeOffset;

            emit AccFeeOffsetUpdated(_asset, newFeeOffset);
        }
    }

    function refundETH(uint256 _amount) internal {
        if (address(this).balance >= _amount) {
            TransferHelper.transferETH(msg.sender, _amount, 0);
        }
    }

    function borrowLimit(address _account, address _borrowAsset)
        public
        view
        returns (uint256 amount)
    {
        uint256 userConfig = config.userDebtAndCollateral(_account);
        address[] memory underlyingsCache = underlyings;

        for (uint256 i = 0; i < underlyingsCache.length; ++i) {
            if (userConfig.isUsingAsCollateral(i)) {
                address underlying = underlyingsCache[i];

                uint256 collateralAmount = underlying == _borrowAsset
                    ? assets[underlying].sToken.scaledBalanceOf(_account)
                    : priceOracle.valueOfAsset(
                        underlying,
                        _borrowAsset,
                        assets[underlying].sToken.scaledBalanceOf(_account)
                    );

                (uint256 amountNew, ) = calculateAmountByRatio(
                    underlying,
                    collateralAmount,
                    config.assetConfigs(underlying).maxLTV
                );

                amount += amountNew;
            }
        }
    }

    function getLiquidationData(address _account, address _repayAsset)
        public
        view
        returns (
            uint256 liquidationAmount,
            uint256 maxLiquidationAmount,
            bool blackListed
        )
    {
        uint256 userConfig = config.userDebtAndCollateral(_account);
        address[] memory underlyingsCache = underlyings;

        for (uint256 i = 0; i < underlyingsCache.length; ++i) {
            if (userConfig.isUsingAsCollateral(i)) {
                address underlying = underlyingsCache[i];

                uint256 collateralAmount = underlying == _repayAsset
                    ? assets[underlying].sToken.scaledBalanceOf(_account)
                    : priceOracle.valueOfAsset(
                        underlying,
                        _repayAsset,
                        assets[underlying].sToken.scaledBalanceOf(_account)
                    );

                Types.AssetConfig memory collateralConfig = config.assetConfigs(
                    underlying
                );

                (
                    uint256 liquidationAmountNew,
                    bool blackListedNew
                ) = calculateAmountByRatio(
                        underlying,
                        collateralAmount,
                        collateralConfig.liquidateLTV
                    );

                (uint256 maxLiquidationAmountNew, ) = calculateAmountByRatio(
                    underlying,
                    collateralAmount,
                    collateralConfig.maxLiquidateRatio
                );

                liquidationAmount += liquidationAmountNew;
                maxLiquidationAmount += maxLiquidationAmountNew;
                if (!blackListed && blackListedNew) {
                    blackListed = true;
                }
            }
        }
    }

    function calculateAmountByRatio(
        address _underlying,
        uint256 _collateralAmount,
        uint256 _ratio
    ) public view returns (uint256 amount, bool blackListed) {
        if (tokenPaused[_underlying]) {
            blackListed = true;
        } else {
            amount = (_ratio * _collateralAmount) / Utils.MILLION;
        }
    }

    function userStatus(address _account, address _quote)
        public
        view
        returns (
            uint256 collateralValue,
            uint256 borrowingValue,
            bool blackListedCollateral
        )
    {
        uint256 userConfig = config.userDebtAndCollateral(_account);
        address[] memory underlyingsCache = underlyings;
        for (uint256 i = 0; i < underlyingsCache.length; ++i) {
            if (userConfig.isUsingAsCollateralOrBorrowing(i)) {
                address underlying = underlyingsCache[i];
                Types.Asset memory asset = assets[underlying];

                if (userConfig.isUsingAsCollateral(i)) {
                    uint256 balance = asset.sToken.scaledBalanceOf(_account);

                    if (tokenPaused[underlying]) {
                        blackListedCollateral = tokenPaused[underlying];
                    } else {
                        collateralValue += underlying == _quote
                            ? balance
                            : priceOracle.valueOfAsset(
                                underlying,
                                _quote,
                                balance
                            );
                    }
                }

                if (userConfig.isBorrowing(i)) {
                    uint256 balance = asset.dToken.scaledDebtOf(_account);

                    borrowingValue += underlying == _quote
                        ? balance
                        : priceOracle.valueOfAsset(underlying, _quote, balance);
                }
            }
        }
    }

    function getUnderlyings()
        external
        view
        override
        returns (address[] memory)
    {
        return underlyings;
    }

    function getAssets()
        external
        view
        override
        returns (Types.Asset[] memory _assets)
    {
        _assets = new Types.Asset[](underlyings.length);
        for (uint256 i = 0; i < _assets.length; ++i) {
            _assets[i] = assets[underlyings[i]];
        }
    }

    function getSupplyStatus(address _underlying)
        public
        view
        override
        returns (
            uint256[] memory supplies,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 newInterest
        )
    {
        IProtocolsHandler protocolsCache = protocols;
        (supplies, protocolsSupplies) = protocolsCache.totalSupplied(
            _underlying
        );
        (totalLending, newInterest) = protocolsCache.simulateLendings(
            _underlying,
            totalLendings[_underlying]
        );
    }

    function getBorrowStatus(address _underlying)
        public
        view
        override
        returns (
            uint256[] memory borrows,
            uint256 protocolsBorrows,
            uint256 totalLending,
            uint256 reservePoolLentAmount,
            uint256 newInterest
        )
    {
        IProtocolsHandler protocolsCache = protocols;
        (borrows, protocolsBorrows) = protocolsCache.totalBorrowed(_underlying);
        (totalLending, newInterest) = protocolsCache.simulateLendings(
            _underlying,
            totalLendings[_underlying]
        );

        reservePoolLentAmount = address(reservePool) == address(0)
            ? 0
            : reservePool.lentAmounts(_underlying);

        return (
            borrows,
            protocolsBorrows,
            totalLending,
            reservePoolLentAmount,
            newInterest
        );
    }

    function totalSupplied(address _underlying)
        public
        view
        override
        returns (uint256)
    {
        (, uint256 protocolsSupplies, uint256 totalLending, ) = getSupplyStatus(
            _underlying
        );

        uint256 fee = accFees[_underlying] - collectedFees[_underlying];

        return protocolsSupplies + totalLending - fee;
    }

    function totalBorrowed(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        (
            ,
            uint256 protocolsBorrows,
            uint256 totalLending,
            uint256 reservePoolLentAmount,

        ) = getBorrowStatus(_underlying);

        return protocolsBorrows + totalLending + reservePoolLentAmount;
    }

    function actionNotPaused(address _token, uint256 _action) internal view {
        require(
            (blockedActions[_token] >> _action) & 1 == 0 &&
                (blockedActions[address(0)] >> _action) & 1 == 0,
            "Router: action paused"
        );
    }

    //  admin functions
    function blockActions(address _asset, uint256 _actions) external onlyOwner {
        blockedActions[_asset] = _actions;
    }

    function toggleToken(address _asset) external onlyOwner {
        tokenPaused[_asset] = !tokenPaused[_asset];
    }

    function addProtocol(IProtocol _protocol) external override onlyOwner {
        protocols.addProtocol(_protocol);
        rewards.addProtocol(_protocol);
    }

    function addAsset(Types.NewAssetParams memory _newAsset)
        external
        override
        onlyOwner
        returns (Types.Asset memory asset)
    {
        uint8 underlyingCount = uint8(underlyings.length);
        require(
            underlyingCount < UserAssetBitMap.MAX_RESERVES_COUNT,
            "Router: asset list full"
        );
        underlyings.push(_newAsset.underlying);

        asset = Types.Asset(
            underlyingCount,
            ISToken(Clones.clone(sTokenImplement)),
            IDToken(Clones.clone(dTokenImplement)),
            _newAsset.collateralable
        );

        asset.sToken.initialize(
            _newAsset.underlying,
            _newAsset.sTokenName,
            _newAsset.sTokenSymbol
        );

        asset.dToken.initialize(
            _newAsset.underlying,
            _newAsset.dTokenName,
            _newAsset.dTokenSymbol
        );

        assets[_newAsset.underlying] = asset;
        config.setAssetConfig(_newAsset.underlying, _newAsset.config);
    }

    function updateSToken(address _sToken) external override onlyOwner {
        sTokenImplement = _sToken;
    }

    function updateDToken(address _dToken) external override onlyOwner {
        dTokenImplement = _dToken;
    }

    function updateConfig(IConfig _config) external override onlyOwner {
        config = _config;
    }

    function updateProtocolsHandler(IProtocolsHandler _protocolsHandler)
        external
        override
        onlyOwner
    {
        protocols = _protocolsHandler;
    }

    function updatePriceOracle(IPriceOracle _priceOracle)
        external
        override
        onlyOwner
    {
        priceOracle = _priceOracle;
    }
}
