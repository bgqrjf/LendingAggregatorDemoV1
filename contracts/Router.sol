// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./storages/RouterStorage.sol";

import "./libraries/TransferHelper.sol";
import "./libraries/UserAssetBitMap.sol";
import "./libraries/Utils.sol";
import "./libraries/Math.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract Router is RouterStorage, OwnableUpgradeable {
    using Math for uint256;
    using UserAssetBitMap for uint256;

    receive() external payable {}

    function initialize(
        address _protocolsHandler,
        address _priceOracle,
        address _config,
        address _rewards,
        address _sToken,
        address _dToken,
        address payable _feeCollector
    ) external initializer {
        __Ownable_init();

        priceOracle = IPriceOracle(_priceOracle);
        protocols = IProtocolsHandler(_protocolsHandler);
        config = IConfig(_config);
        rewards = IRewards(_rewards);
        sTokenImplement = _sToken;
        dTokenImplement = _dToken;
        feeCollector = _feeCollector;
    }

    function supply(Types.UserAssetParams memory _params, bool _collateralable)
        external
        payable
    {
        actionNotPaused(_params.asset, uint256(Action.supply));
        require(!tokenPaused[_params.asset], "Router: token paused");

        IProtocolsHandler protocolsCache = protocols;

        (uint256 totalLending, uint256 newInterest) = protocolsCache
            .simulateLendings(_params.asset, totalLendings[_params.asset]);

        TransferHelper.collect(
            _params.asset,
            msg.sender,
            address(protocolsCache),
            _params.amount,
            0 // gasLimit
        );

        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_params.asset);

        recordSupply(
            _params,
            protocolsSupplies + totalLending,
            newInterest,
            _collateralable
        );

        // execute supply
        (uint256 repayed, uint256 supplied) = protocolsCache.repayAndSupply(
            _params.asset,
            _params.amount,
            supplies,
            protocolsSupplies
        );

        if (repayed > 0 || newInterest > 0) {
            totalLending = totalLending + repayed;
            updateTotalLendings(protocolsCache, _params.asset, totalLending);
        }

        emit Supplied(_params.to, _params.asset, repayed + supplied);
    }

    // _params.amount is LPToken
    function redeem(Types.UserAssetParams memory _params, bool _collateralable)
        external
    {
        actionNotPaused(_params.asset, uint256(Action.redeem));
        IProtocolsHandler protocolsCache = protocols;
        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_params.asset);

        (uint256 totalLending, uint256 newInterest) = protocolsCache
            .simulateLendings(_params.asset, totalLendings[_params.asset]);

        uint256 uncollectedFee;
        (_params.amount, uncollectedFee) = recordRedeem(
            _params,
            protocolsSupplies + totalLending,
            newInterest,
            _collateralable
        );

        _redeem(
            _params,
            supplies,
            protocolsSupplies,
            totalLending,
            uncollectedFee
        );
    }

    function _redeem(
        Types.UserAssetParams memory _params,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending,
        uint256 _uncollectedFee
    ) internal {
        IProtocolsHandler protocolsCache = protocols;

        (uint256 redeemed, uint256 borrowed) = protocolsCache.redeemAndBorrow(
            _params.asset,
            _params.amount,
            _supplies,
            _protocolsSupplies,
            _params.to
        );

        if (borrowed > 0 || _uncollectedFee > 0) {
            uint256 totalLendingDelta = borrowed + _uncollectedFee;
            _totalLending = _totalLending > totalLendingDelta
                ? _totalLending - totalLendingDelta
                : 0;
            updateTotalLendings(protocolsCache, _params.asset, _totalLending);
        }

        emit Redeemed(msg.sender, _params.asset, redeemed + borrowed);
    }

    function borrow(Types.UserAssetParams memory _params) external {
        actionNotPaused(_params.asset, uint256(Action.borrow));

        require(_params.amount > 0, "Router: Borrow 0 token is not allowed");
        require(borrowAllowed(_params), "Router: Insufficient collateral");

        IProtocolsHandler protocolsCache = protocols;

        (uint256 totalLending, uint256 newInterest) = protocolsCache
            .simulateLendings(_params.asset, totalLendings[_params.asset]);

        (, uint256 protocolsBorrows) = protocolsCache.totalBorrowed(
            _params.asset
        );

        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_params.asset);

        recordBorrow(_params, newInterest, protocolsBorrows + totalLending);

        // execute Brorrow
        (uint256 redeemed, uint256 borrowed) = protocolsCache.redeemAndBorrow(
            _params.asset,
            _params.amount,
            supplies,
            protocolsSupplies,
            _params.to
        );

        if (redeemed > 0 || newInterest > 0) {
            totalLending += redeemed;
            updateTotalLendings(protocolsCache, _params.asset, totalLending);
        }

        emit Borrowed(msg.sender, _params.asset, redeemed + borrowed);
    }

    function repay(Types.UserAssetParams memory _params) external payable {
        actionNotPaused(_params.asset, uint256(Action.repay));
        _repay(_params);
    }

    function _repay(Types.UserAssetParams memory _params) internal {
        IProtocolsHandler protocolsCache = protocols;

        (, uint256 protocolsBorrows) = protocolsCache.totalBorrowed(
            _params.asset
        );

        (uint256 totalLending, uint256 newInterest) = protocolsCache
            .simulateLendings(_params.asset, totalLendings[_params.asset]);

        uint256 fee;
        (_params.amount, fee) = recordRepay(
            _params,
            newInterest,
            protocolsBorrows + totalLending
        );

        // handle transfer
        {
            TransferHelper.collect(
                _params.asset,
                msg.sender,
                address(protocolsCache),
                _params.amount - fee,
                0
            );

            TransferHelper.collect(
                _params.asset,
                msg.sender,
                feeCollector,
                fee,
                0
            );
            emit FeeCollected(_params.asset, feeCollector, fee);

            // transfer over provided ETH back to user
            if (
                _params.asset == TransferHelper.ETH &&
                msg.value > _params.amount
            ) {
                refundETH(msg.value - _params.amount);
            }
        }

        // execute repay
        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_params.asset);
        (uint256 repayed, uint256 supplied) = protocolsCache.repayAndSupply(
            _params.asset,
            _params.amount - fee,
            supplies,
            protocolsSupplies
        );

        totalLending = totalLending > fee ? totalLending - fee : 0;
        totalLending = totalLending - supplied;
        updateTotalLendings(protocolsCache, _params.asset, totalLending);

        emit Repayed(_params.to, _params.asset, repayed + supplied + fee);
    }

    function liquidate(
        Types.UserAssetParams memory _repayParams,
        Types.UserAssetParams memory _redeemParams
    ) external payable {
        actionNotPaused(_repayParams.asset, uint256(Action.liquidate));
        Types.BorrowConfig memory bc = config.borrowConfigs(_repayParams.asset);

        _repayParams.amount = validateLiquidatation(
            _repayParams,
            _redeemParams,
            bc
        );

        _repay(_repayParams);

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
                        .borrowConfigs(_redeemParams.asset)
                        .liquidateRewardRatio) /
                Utils.MILLION;
        }
        uint256 uncollectedFee;
        (_redeemParams.amount, uncollectedFee) = recordLiquidateRedeem(
            _redeemParams,
            protocolsSupplies + totalLending
        );

        _redeem(
            _redeemParams,
            supplies,
            protocolsSupplies,
            totalLending,
            uncollectedFee
        );
    }

    function claimRewards(address _account) external {
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

    function borrowAllowed(Types.UserAssetParams memory _params)
        internal
        view
        returns (bool)
    {
        Types.BorrowConfig memory bc = config.borrowConfigs(_params.asset);
        (uint256 collateralValue, uint256 debtsValue, ) = userStatus(
            _params.to,
            _params.asset
        );

        uint256 borrowLimit = (collateralValue * bc.maxLTV) / Utils.MILLION;
        return _params.amount + debtsValue <= borrowLimit;
    }

    function validateLiquidatation(
        Types.UserAssetParams memory _repayParams,
        Types.UserAssetParams memory _redeemParams,
        Types.BorrowConfig memory _bc
    ) internal view returns (uint256) {
        (
            uint256 collateralValue,
            uint256 debtsValue,
            bool blackListed
        ) = userStatus(_repayParams.to, _repayParams.asset);

        uint256 userConfig = config.userDebtAndCollateral(_repayParams.to);
        Types.Asset memory repayAsset = assets[_repayParams.asset];
        Types.Asset memory redeemAsset = assets[_redeemParams.asset];

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
            debtsValue * Utils.MILLION > _bc.liquidateLTV * collateralValue,
            "Router: Liquidate not allowed"
        );

        uint256 maxLiquidation = (debtsValue * _bc.maxLiquidateRatio) /
            Utils.MILLION;

        return
            _repayParams.amount < maxLiquidation
                ? _repayParams.amount
                : maxLiquidation;
    }

    // record actions
    function recordSupply(
        Types.UserAssetParams memory _params,
        uint256 totalSupplies,
        uint256 newInterest,
        bool _collateralable
    ) internal {
        Types.Asset memory asset = assets[_params.asset];

        updateAccFee(_params.asset, newInterest);

        uint256 sTokenAmount = asset.sToken.mint(
            _params.to,
            _params.amount,
            totalSupplies
        );

        rewards.startMiningSupplyReward(
            _params.asset,
            _params.to,
            sTokenAmount,
            asset.sToken.totalSupply()
        );

        config.setUsingAsCollateral(_params.to, asset.index, _collateralable);
    }

    function recordRedeem(
        Types.UserAssetParams memory _params,
        uint256 totalSupplies,
        uint256 newInterest,
        bool _collateralable
    ) internal returns (uint256 underlyingAmount, uint256 fee) {
        Types.Asset memory asset = assets[_params.asset];

        uint256 accFee = updateAccFee(_params.asset, newInterest);

        uint256 sTokenBalance = asset.sToken.balanceOf(msg.sender);
        if (_params.amount >= sTokenBalance) {
            _params.amount = sTokenBalance;
            _collateralable = false;
        }

        (underlyingAmount, fee) = asset.sToken.burn(
            msg.sender,
            _params.amount,
            totalSupplies,
            accFee - collectedFees[_params.asset]
        );

        rewards.stopMiningSupplyReward(
            _params.asset,
            msg.sender,
            _params.amount,
            asset.sToken.totalSupply() + _params.amount
        );

        config.setUsingAsCollateral(msg.sender, asset.index, _collateralable);
    }

    function recordBorrow(
        Types.UserAssetParams memory _params,
        uint256 newInterest,
        uint256 totalBorrows
    ) internal {
        Types.Asset memory asset = assets[_params.asset];

        uint256 accFee = updateAccFee(_params.asset, newInterest);

        uint256 dTokenTotalSupply = asset.dToken.totalSupply();
        uint256 feeIndex = updateFeeIndex(
            _params.asset,
            dTokenTotalSupply,
            accFee + accFeeOffsets[_params.asset]
        );

        uint256 dTokenAmount = asset.dToken.mint(
            msg.sender,
            _params.amount,
            totalBorrows
        );

        updateUserFeeIndex(
            _params.asset,
            msg.sender,
            asset.dToken.balanceOf(msg.sender),
            dTokenAmount,
            feeIndex
        );
        updateAccFeeOffset(_params.asset, feeIndex, dTokenAmount);

        rewards.startMiningBorrowReward(
            _params.asset,
            msg.sender,
            dTokenAmount,
            dTokenTotalSupply
        );

        config.setBorrowing(msg.sender, asset.index, true);
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
    }

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
        accFee = accFees[_asset];
        if (_newInterest > 0) {
            accFee +=
                (_newInterest * config.borrowConfigs(_asset).feeRate) /
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
                (_feeIndex * _newOffset).divCeil(Utils.QUINTILLION);

            accFeeOffsets[_asset] = newFeeOffset;

            emit AccFeeOffsetUpdated(_asset, newFeeOffset);
        }
    }

    function refundETH(uint256 _amount) internal {
        if (address(this).balance >= _amount) {
            TransferHelper.transferETH(msg.sender, _amount, 0);
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

    function totalSupplied(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        IProtocolsHandler protocolsCache = protocols;
        (, uint256 protocolsSupplies) = protocolsCache.totalSupplied(
            _underlying
        );
        (uint256 totalLending, ) = protocolsCache.simulateLendings(
            _underlying,
            totalLendings[_underlying]
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
        IProtocolsHandler protocolsCache = protocols;
        (, uint256 protocolsBorrows) = protocolsCache.totalBorrowed(
            _underlying
        );
        (uint256 totalLending, ) = protocolsCache.simulateLendings(
            _underlying,
            totalLendings[_underlying]
        );

        return protocolsBorrows + totalLending;
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
        config.setBorrowConfig(_newAsset.underlying, _newAsset.borrowConfig);
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
