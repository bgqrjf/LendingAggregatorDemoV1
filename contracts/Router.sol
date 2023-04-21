// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./storages/RouterStorage.sol";
import "./MultiImplementationBeaconProxy.sol";

import "./libraries/externals/SupplyLogic.sol";
import "./libraries/externals/RedeemLogic.sol";
import "./libraries/externals/BorrowLogic.sol";
import "./libraries/externals/RepayLogic.sol";
import "./libraries/externals/LiquidateLogic.sol";
import "./libraries/externals/RewardLogic.sol";

import "./libraries/internals/TransferHelper.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Router is RouterStorage, OwnableUpgradeable {
    using Math for uint256;

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
            totalLendings
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
                priceOracle
            ),
            underlyings,
            totalLendings,
            assets
        );
    }

    function borrow(
        Types.UserAssetParams memory _params,
        bool _executeNow
    ) external override {
        BorrowLogic.borrow(
            Types.BorrowParams(
                _params,
                _executeNow,
                actionNotPaused(_params.asset, Action.borrow),
                protocols,
                reservePool,
                rewards,
                config,
                priceOracle
            ),
            underlyings,
            assets,
            totalLendings
        );
    }

    function repay(
        Types.UserAssetParams memory _params,
        bool _executeNow
    ) external payable {
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
                assets[_params.asset]
            ),
            totalLendings
        );
    }

    // _redeemParams.amount is the minAmount redeem which is used as slippage validation
    function liquidate(
        Types.UserAssetParams memory _repayParams,
        Types.UserAssetParams memory _redeemParams
    ) external payable {
        LiquidateLogic.liquidate(
            Types.LiquidateParams(
                _repayParams,
                _redeemParams,
                feeCollector,
                protocols,
                reservePool,
                rewards,
                config,
                priceOracle,
                actionNotPaused(_repayParams.asset, Action.liquidate)
            ),
            underlyings,
            assets,
            totalLendings
        );
    }

    function claimRewards(address _account) external override {
        RewardLogic.claimRewards(
            Types.ClaimRewardsParams(
                actionNotPaused(address(0), Action.claimRewards),
                _account,
                protocols,
                config,
                rewards,
                underlyings
            ),
            assets
        );
    }

    function sync(address _asset) external override {
        ExternalUtils.sync(_asset, protocols, totalLendings);
    }

    // reservePool callbacks
    function recordSupply(
        Types.UserAssetParams memory _params,
        uint256 totalUnderlying,
        uint256 newInterest
    ) external override onlyReservePool {
        SupplyLogic.recordSupply(
            Types.RecordSupplyParams(
                _params,
                assets[_params.asset].sToken,
                assets[_params.asset].dToken,
                totalUnderlying,
                newInterest
            )
        );
    }

    function recordRedeem(
        Types.UserAssetParams memory _params,
        uint256 _totalSupplies,
        uint256 _newInterest,
        address _redeemFrom,
        bool _collateralable
    ) external override onlyReservePool returns (uint256 underlyingAmount) {
        return
            RedeemLogic.recordRedeem(
                Types.RecordRedeemParams(
                    _params,
                    _totalSupplies,
                    _newInterest,
                    _redeemFrom,
                    true,
                    _collateralable,
                    rewards
                ),
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
                rewards
            ),
            assets
        );
    }

    function executeSupply(
        Types.ExecuteSupplyParams memory params
    ) external payable override onlyReservePool {
        SupplyLogic.executeSupply(params, protocols, totalLendings);
    }

    function executeRedeem(
        Types.ExecuteRedeemParams memory _params
    ) external override onlyReservePool {
        _params.protocols = protocols;
        RedeemLogic.executeRedeem(_params, totalLendings);
    }

    function executeBorrow(
        Types.UserAssetParams memory _params
    ) external override onlyReservePool {
        IProtocolsHandler protocolsCache = protocols;
        (uint256 totalLending, ) = protocolsCache.simulateLendings(
            _params.asset,
            totalLendings[_params.asset]
        );

        BorrowLogic.executeBorrow(
            _params,
            protocols,
            totalLending,
            totalLendings
        );
    }

    function executeRepay(
        address _asset,
        uint256 _amount
    ) external override onlyReservePool {
        IProtocolsHandler protocolsCache = protocols;
        (uint256 totalLending, ) = protocolsCache.simulateLendings(
            _asset,
            totalLendings[_asset]
        );

        RepayLogic.executeRepay(
            protocolsCache,
            _asset,
            _amount,
            totalLending,
            totalLendings
        );
    }

    // views
    function borrowLimit(
        address _account,
        address _borrowAsset
    ) external view override returns (uint256 amount) {
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

    function getLiquidationData(
        address _account,
        address _repayAsset
    )
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

    function userStatus(
        address _account,
        address _quote
    )
        external
        view
        override
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

    function getSupplyStatus(
        address _underlying
    )
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

    function getBorrowStatus(
        address _underlying
    )
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

    function totalSupplied(
        address _underlying
    ) external view override returns (uint256) {
        (
            ,
            ,
            ,
            uint256 totalSuppliedAmountWithFee,
            uint newInterest
        ) = ExternalUtils.getSupplyStatus(
                _underlying,
                reservePool,
                protocols,
                totalLendings
            );

        IDToken dToken = assets[_underlying].dToken;
        (uint newAccFee, ) = dToken.calculateFee(newInterest);
        uint fee = newAccFee - dToken.collectedFee();

        return totalSuppliedAmountWithFee - fee;
    }

    function totalBorrowed(
        address _underlying
    ) external view override returns (uint256 totalBorrowedAmount) {
        (, totalBorrowedAmount, , ) = ExternalUtils.getBorrowStatus(
            _underlying,
            reservePool,
            protocols,
            totalLendings
        );
    }

    // validations
    function isPoisitionHealthy(
        address _underlying,
        address _account
    )
        public
        view
        override
        returns (
            bool isHealthy,
            uint256 maxDebtAllowed,
            uint256 collateralAmount
        )
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

    function isUsingAsCollateral(
        address _underlying,
        address _account
    ) public view override returns (bool) {
        return
            UserAssetBitMap.isUsingAsCollateral(
                config.userDebtAndCollateral(_account),
                assets[_underlying].index
            );
    }

    function isBorrowing(
        address _underlying,
        address _account
    ) public view override returns (bool) {
        return
            UserAssetBitMap.isBorrowing(
                config.userDebtAndCollateral(_account),
                assets[_underlying].index
            );
    }

    function actionNotPaused(
        address _token,
        Action _action
    ) internal view returns (bool) {
        return
            (uint256(blockedActions[_token]) >> uint256(_action)) & 1 == 0 &&
            (uint256(blockedActions[address(0)]) >> uint256(_action)) & 1 == 0;
    }

    //  admin functions
    function setBlockActions(
        address _asset,
        uint256 _action
    ) external onlyOwner {
        blockedActions[_asset] = _action;
        emit BlockActionsSet(_asset, _action);
    }

    function toggleToken(address _asset) external onlyOwner {
        assets[_asset].paused = !assets[_asset].paused;
        emit TokenPausedSet(_asset, assets[_asset].paused);
    }

    function addProtocol(IProtocol _protocol) external override onlyOwner {
        protocols.addProtocol(_protocol);
        rewards.addProtocol(_protocol);
        emit ProtocolAdded(_protocol);
    }

    function updateProtocol(
        IProtocol _old,
        IProtocol _new
    ) external override onlyOwner {
        protocols.updateProtocol(_old, _new);
        emit ProtocolUpdated(_old, _new);
    }

    function addAsset(
        Types.NewAssetParams memory _newAsset
    ) external override onlyOwner returns (Types.Asset memory asset) {
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
            ISToken(
                address(
                    new MultiImplementationBeaconProxy(
                        keySToken,
                        abi.encodeWithSelector(
                            ISToken.initialize.selector,
                            _newAsset.underlying,
                            _newAsset.sTokenName,
                            _newAsset.sTokenSymbol
                        )
                    )
                )
            ),
            IDToken(
                address(
                    new MultiImplementationBeaconProxy(
                        keyDToken,
                        abi.encodeWithSelector(
                            IDToken.initialize.selector,
                            _newAsset.underlying,
                            _newAsset.dTokenName,
                            _newAsset.dTokenSymbol,
                            _newAsset.feeRate
                        )
                    )
                )
            )
        );

        assets[_newAsset.underlying] = asset;
        config.setAssetConfig(_newAsset.underlying, _newAsset.config);

        _updateReservePoolConfig(
            _newAsset.underlying,
            _newAsset.maxReserve,
            _newAsset.executeSupplyThreshold
        );

        emit AssetAdded(_newAsset.underlying, asset);
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
            emit ReservePoolConfigUpdated(
                _asset,
                _maxReserve,
                _executeSupplyThreshold
            );
        }
    }

    function updateSToken(address _sToken) external override onlyOwner {
        sTokenImplement = _sToken;
        emit STokenUpdated(_sToken);
    }

    function updateDToken(address _dToken) external override onlyOwner {
        dTokenImplement = _dToken;
        emit DTokenUpdated(_dToken);
    }

    function updateConfig(IConfig _config) external override onlyOwner {
        config = _config;
        emit ConfigUpdated(_config);
    }

    function updateProtocolsHandler(
        IProtocolsHandler _protocolsHandler
    ) external override onlyOwner {
        protocols = _protocolsHandler;
        emit ProtocolsHandlerUpdated(_protocolsHandler);
    }

    function updatePriceOracle(
        IPriceOracle _priceOracle
    ) external override onlyOwner {
        priceOracle = _priceOracle;
        emit PriceOracleUpdated(_priceOracle);
    }

    // --- getters
    function getAsset(
        address _underlying
    ) external view override returns (Types.Asset memory asset) {
        return assets[_underlying];
    }

    function implementations(
        bytes32 implementationKey
    ) external view override returns (address) {
        if (implementationKey == keyDToken) {
            return dTokenImplement;
        } else if (implementationKey == keySToken) {
            return sTokenImplement;
        } else {
            revert("Router: implementationKey not exists");
        }
    }
}
