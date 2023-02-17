// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./storages/RouterStorage.sol";

import "./libraries/externals/SupplyLogic.sol";
import "./libraries/externals/RedeemLogic.sol";
import "./libraries/externals/BorrowLogic.sol";
import "./libraries/externals/RepayLogic.sol";
import "./libraries/externals/LiquidateLogic.sol";

import "./libraries/internals/TransferHelper.sol";
import "./libraries/internals/UserAssetBitMap.sol";
import "./libraries/internals/Utils.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "hardhat/console.sol";

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
        SupplyLogic.supply(
            Types.SupplyParams(
                _params,
                _collateralable,
                _executeNow,
                actionNotPaused(_params.asset, Action.supply),
                protocols,
                reservePool,
                rewards,
                config,
                assets[_params.asset]
            ),
            totalLendings,
            accFees
        );
    }

    function redeem(
        Types.UserAssetParams memory _params,
        bool _collateralable,
        bool _executeNow
    ) external override {
        RedeemLogic.redeem(
            Types.RedeemParams(
                _params,
                _collateralable,
                _executeNow,
                actionNotPaused(_params.asset, Action.redeem),
                protocols,
                reservePool,
                rewards,
                config,
                priceOracle,
                collectedFees[_params.asset],
                underlyings
            ),
            totalLendings,
            accFees,
            assets
        );
    }

    function borrow(Types.UserAssetParams memory _params, bool _executeNow)
        external
        override
    {
        BorrowLogic.borrow(
            Types.BorrowParams(
                _params,
                _executeNow,
                actionNotPaused(_params.asset, Action.borrow),
                protocols,
                reservePool,
                rewards,
                config,
                priceOracle,
                collectedFees[_params.asset],
                underlyings
            ),
            assets,
            totalLendings,
            accFees,
            accFeeOffsets,
            feeIndexes,
            userFeeIndexes
        );
    }

    function repay(Types.UserAssetParams memory _params, bool _executeNow)
        external
        payable
    {
        RepayLogic.repay(
            Types.RepayParams(
                _params,
                _executeNow,
                actionNotPaused(_params.asset, Action.repay),
                feeCollector,
                protocols,
                reservePool,
                rewards,
                config,
                priceOracle,
                collectedFees[_params.asset],
                accFeeOffsets[_params.asset],
                userFeeIndexes[_params.to][_params.asset],
                assets[_params.asset]
            ),
            totalLendings,
            accFees,
            collectedFees,
            feeIndexes
        );
    }

    // _redeemParams.amount is the minAmount redeem which is used as slippage validation
    function liquidate(
        Types.UserAssetParams memory _repayParams,
        Types.UserAssetParams memory _redeemParams
    ) external payable {
        LiquidateLogic.liquidate(
            Types.LiquidateParams(
                Types.RepayParams(
                    _repayParams,
                    true,
                    actionNotPaused(_repayParams.asset, Action.repay),
                    feeCollector,
                    protocols,
                    reservePool,
                    rewards,
                    config,
                    priceOracle,
                    collectedFees[_repayParams.asset],
                    accFeeOffsets[_repayParams.asset],
                    userFeeIndexes[_repayParams.to][_repayParams.asset],
                    assets[_repayParams.asset]
                ),
                Types.RedeemParams(
                    _redeemParams,
                    true,
                    true,
                    actionNotPaused(_redeemParams.asset, Action.redeem),
                    protocols,
                    reservePool,
                    rewards,
                    config,
                    priceOracle,
                    collectedFees[_redeemParams.asset],
                    underlyings
                ),
                actionNotPaused(_repayParams.asset, Action.liquidate),
                underlyings
            ),
            assets,
            totalLendings,
            accFees,
            collectedFees,
            feeIndexes
        );
    }

    function claimRewards(address _account) external override {
        actionNotPaused(address(0), Action.claimRewards);
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

    function sync(address _asset) external override {
        ExternalUtils.sync(_asset, protocols, config, totalLendings, accFees);
    }

    // reservePool callbacks
    function recordSupply(
        Types.UserAssetParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        bool _collateralable
    ) external override onlyReservePool {
        SupplyLogic.recordSupply(
            Types.SupplyParams(
                _params,
                _collateralable,
                false, // not used in libirary
                false, // not used in library
                protocols,
                reservePool,
                rewards,
                config,
                assets[_params.asset]
            ),
            _totalSupplies,
            _newInterest,
            accFees
        );
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
            RedeemLogic.recordRedeem(
                Types.RedeemParams(
                    _params,
                    _collateralable,
                    false, // not used in libirary
                    false, // not used in library
                    protocols,
                    reservePool,
                    rewards,
                    config,
                    priceOracle,
                    collectedFees[_params.asset],
                    underlyings
                ),
                _totalSupplies,
                _newInterest,
                _redeemFrom,
                accFees,
                assets
            );
    }

    function recordBorrow(
        Types.UserAssetParams memory _params,
        uint256 _newInterest,
        uint256 _totalBorrows,
        address _borrowBy
    ) external override onlyReservePool {
        BorrowLogic.recordBorrow(
            Types.RecordBorrowParams(
                _params,
                _newInterest,
                _totalBorrows,
                _borrowBy,
                config,
                rewards
            ),
            assets,
            accFees,
            accFeeOffsets,
            feeIndexes,
            userFeeIndexes
        );
    }

    function executeSupply(
        address _asset,
        uint256 _amount,
        uint256 _totalLending,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies
    ) external payable override onlyReservePool {
        SupplyLogic.executeSupply(
            Types.SupplyParams(
                Types.UserAssetParams(
                    _asset,
                    _amount,
                    address(0) // not used in library
                ),
                false, // not used in library
                false, // not used in library
                true, // not used in library
                protocols,
                reservePool,
                rewards,
                config,
                assets[_asset]
            ),
            _totalLending,
            _supplies,
            _protocolsSupplies,
            totalLendings
        );
    }

    function executeRedeem(
        Types.UserAssetParams memory _params,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending,
        uint256 _uncollectedFee
    ) external override onlyReservePool {
        RedeemLogic.executeRedeem(
            Types.RedeemParams(
                _params,
                false,
                true,
                true,
                protocols,
                reservePool,
                rewards,
                config,
                priceOracle,
                collectedFees[_params.asset],
                underlyings
            ),
            _supplies,
            _protocolsSupplies,
            _totalLending,
            totalLendings
        );
    }

    function executeBorrow(Types.UserAssetParams memory _params)
        external
        override
        onlyReservePool
    {
        IProtocolsHandler protocolsCache = protocols;
        (uint256 totalLending, ) = protocolsCache.simulateLendings(
            _params.asset,
            totalLendings[_params.asset]
        );

        BorrowLogic.executeBorrow(
            Types.BorrowParams(
                _params,
                true, // not used in library
                true, // not used in library
                protocolsCache,
                reservePool,
                rewards,
                config,
                priceOracle,
                collectedFees[_params.asset],
                underlyings
            ),
            totalLending,
            totalLendings
        );
    }

    function executeRepay(address _asset, uint256 _amount)
        external
        override
        onlyReservePool
    {
        IProtocolsHandler protocolsCache = protocols;
        (uint256 totalLending, ) = protocolsCache.simulateLendings(
            _asset,
            totalLendings[_asset]
        );

        RepayLogic.executeRepay(
            protocols,
            _asset,
            _amount,
            totalLending,
            totalLendings
        );
    }

    // views
    function borrowLimit(address _account, address _borrowAsset)
        external
        view
        returns (uint256 amount)
    {
        return
            BorrowLogic.borrowLimit(
                config,
                priceOracle,
                _account,
                _borrowAsset,
                underlyings,
                assets
            );
    }

    function getLiquidationData(address _account, address _repayAsset)
        external
        view
        returns (
            uint256 liquidationAmount,
            uint256 maxLiquidationAmount,
            bool blackListed
        )
    {
        return
            LiquidateLogic.getLiquidationData(
                _account,
                _repayAsset,
                underlyings,
                config,
                priceOracle,
                assets
            );
    }

    function userStatus(address _account, address _quote)
        external
        view
        returns (
            uint256 collateralValue,
            uint256 borrowingValue,
            bool blackListedCollateral
        )
    {
        return
            ExternalUtils.userStatus(
                _account,
                _quote,
                priceOracle,
                config,
                underlyings,
                assets
            );
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
        external
        view
        override
        returns (
            uint256[] memory supplies,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 totalSuppliedAmountWithFee,
            uint256 newInterest
        )
    {
        return
            ExternalUtils.getSupplyStatus(
                _underlying,
                reservePool,
                protocols,
                totalLendings
            );
    }

    function getBorrowStatus(address _underlying)
        external
        view
        override
        returns (
            uint256[] memory borrows,
            uint256 totalBorrowedAmount,
            uint256 totalLending,
            uint256 newInterest
        )
    {
        return
            ExternalUtils.getBorrowStatus(
                _underlying,
                reservePool,
                protocols,
                totalLendings
            );
    }

    function getSupplyRate(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        (
            ,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 totalSuppliedAmountWithFee,

        ) = ExternalUtils.getSupplyStatus(
                _underlying,
                reservePool,
                protocols,
                totalLendings
            );

        (uint256 protocolsSupplyRate, uint256 protocolsBorrowRate) = protocols
            .getRates(_underlying);

        uint256 lendingRate = ((protocolsBorrowRate - protocolsSupplyRate) *
            (totalBorrowed(_underlying))) / (totalSuppliedAmountWithFee);

        return
            (protocolsSupplyRate *
                protocolsSupplies +
                lendingRate *
                totalLending) / (totalSuppliedAmountWithFee * Utils.MILLION);
    }

    function getBorrowRate(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        (
            uint256[] memory borrows,
            uint256 totalBorrowedAmount,
            uint256 totalLending,

        ) = ExternalUtils.getBorrowStatus(
                _underlying,
                reservePool,
                protocols,
                totalLendings
            );

        (uint256 protocolsSupplyRate, uint256 protocolsBorrowRate) = protocols
            .getRates(_underlying);

        uint256 lendingRate = ((protocolsBorrowRate - protocolsSupplyRate) *
            (totalBorrowedAmount)) / (totalSupplied(_underlying));

        uint256 protocolsBorrows = Utils.samOf(borrows);

        return
            (protocolsBorrowRate *
                protocolsBorrows +
                lendingRate *
                totalLending) / (totalBorrowedAmount * Utils.MILLION);
    }

    function getLendingRate(address _underlying)
        external
        view
        override
        returns (uint256 lendingRate)
    {
        (uint256 protocolsSupplyRate, uint256 protocolsBorrowRate) = protocols
            .getRates(_underlying);

        lendingRate =
            ((protocolsBorrowRate - protocolsSupplyRate) *
                (totalBorrowed(_underlying))) /
            (totalSupplied(_underlying));
    }

    function totalSupplied(address _underlying)
        public
        view
        override
        returns (uint256)
    {
        (, , , uint256 totalSuppliedAmountWithFee, ) = ExternalUtils
            .getSupplyStatus(
                _underlying,
                reservePool,
                protocols,
                totalLendings
            );

        uint256 fee = accFees[_underlying] - collectedFees[_underlying];

        return totalSuppliedAmountWithFee - fee;
    }

    function totalBorrowed(address _underlying)
        public
        view
        override
        returns (uint256 totalBorrowedAmount)
    {
        (, totalBorrowedAmount, , ) = ExternalUtils.getBorrowStatus(
            _underlying,
            reservePool,
            protocols,
            totalLendings
        );
    }

    // validations
    function isPoisitionHealthy(address _underlying, address _account)
        public
        view
        override
        returns (bool)
    {
        return
            ExternalUtils.isPositionHealthy(
                config,
                priceOracle,
                _account,
                _underlying,
                underlyings,
                assets
            );
    }

    function actionNotPaused(address _token, Action _action)
        internal
        view
        returns (bool)
    {
        return
            (uint256(blockedActions[_token]) >> uint256(_action)) & 1 == 0 &&
            (uint256(blockedActions[address(0)]) >> uint256(_action)) & 1 == 0;
    }

    //  admin functions
    function setBlockActions(address _asset, uint256 _action)
        external
        onlyOwner
    {
        blockedActions[_asset] = _action;
        emit BlockActionsSet(_asset, _action);
    }

    function toggleToken(address _asset) external onlyOwner {
        assets[_asset].paused = !assets[_asset].paused;
        emit TokenPaused(_asset);
    }

    function addProtocol(IProtocol _protocol) external override onlyOwner {
        protocols.addProtocol(_protocol);
        rewards.addProtocol(_protocol);
    }

    function updateProtocol(IProtocol _old, IProtocol _new)
        external
        override
        onlyOwner
    {
        protocols.updateProtocol(_old, _new);
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
            _newAsset.collateralable,
            false,
            ISToken(Clones.clone(sTokenImplement)),
            IDToken(Clones.clone(dTokenImplement))
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

        _updateReservePoolConfig(
            _newAsset.underlying,
            _newAsset.maxReserve,
            _newAsset.executeSupplyThreshold
        );


        emit AddAsset(asset);
    }

    function updateReservePoolConfig(
        address _asset,
        uint256 _maxReserve,
        uint256 _executeSupplyThreshold
    ) external onlyOwner {
        _updateReservePoolConfig(_asset, _maxReserve, _executeSupplyThreshold);
    }

    function _updateReservePoolConfig(
        address _asset,
        uint256 _maxReserve,
        uint256 _executeSupplyThreshold
    ) internal {
        if (address(reservePool) != address(0)) {
            reservePool.setConfig(_asset, _maxReserve, _executeSupplyThreshold);
        }
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

    // --- getters
    function getAsset(address _underlying)
        external
        view
        override
        returns (Types.Asset memory asset)
    {
        return assets[_underlying];
    }
}
