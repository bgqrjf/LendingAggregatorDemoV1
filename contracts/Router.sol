// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IRouter.sol";

import "./libraries/TransferHelper.sol";
import "./libraries/UserAssetBitMap.sol";
import "./libraries/Utils.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract Router is IRouter, OwnableUpgradeable {
    IConfig public config;
    IPriceOracle public priceOracle;
    IProtocolsHandler public protocols;
    IRewards public rewards;
    address public sTokenImplement;
    address public dTokenImplement;
    address[] public underlyings;
    mapping(address => Types.Asset) public assets;
    mapping(address => uint256) public totalLendings;
    mapping(address => uint256) public userSupplied;

    receive() external payable {}

    function initialize(
        address _protocolsHandler,
        address _priceOracle,
        address _config,
        address _rewards,
        address _sToken,
        address _dToken
    ) external initializer {
        __Ownable_init();

        priceOracle = IPriceOracle(_priceOracle);
        protocols = IProtocolsHandler(_protocolsHandler);
        config = IConfig(_config);
        rewards = IRewards(_rewards);
        sTokenImplement = _sToken;
        dTokenImplement = _dToken;
    }

    function supply(Types.UserAssetParams memory _params, bool _collateralable)
        public
        payable
    {
        IProtocolsHandler protocolsCache = protocols;
        Types.Asset memory asset = assets[_params.asset];

        uint256 totalLending = protocolsCache.simulateLendings(
            _params.asset,
            totalLendings[_params.asset]
        );

        TransferHelper.collect(
            _params.asset,
            msg.sender,
            address(protocolsCache),
            _params.amount,
            0 // gasLimit
        );

        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_params.asset);
        uint256 sTokenAmount = asset.sToken.mint(
            _params.to,
            _params.amount,
            protocolsSupplies + totalLending
        );

        uint256 repayed = protocolsCache.repay(_params);
        if (repayed > 0) {
            totalLending += repayed;
            updatetotalLendings(_params.asset, totalLending);
            protocolsCache.simulateSupply(_params.asset, totalLending);
        }

        if (_params.amount > repayed) {
            protocolsCache.supply(
                _params.asset,
                _params.amount - repayed,
                supplies,
                protocolsSupplies
            );
        }

        // store on strategy aToken and cToken amount
        config.setUsingAsCollateral(_params.to, asset.index, _collateralable);

        rewards.startMiningSupplyReward(
            _params.asset,
            _params.to,
            sTokenAmount,
            asset.sToken.totalSupply()
        );

        emit Supplied(_params.to, _params.asset, _params.amount);
    }

    // _params.amount is LPToken
    function redeem(Types.UserAssetParams memory _params, bool _collateralable)
        public
    {
        IProtocolsHandler protocolsCache = protocols;
        Types.Asset memory asset = assets[_params.asset];
        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_params.asset);

        uint256 totalLending = protocolsCache.simulateLendings(
            _params.asset,
            totalLendings[_params.asset]
        );

        uint256 totalSupply = asset.sToken.totalSupply();

        uint256 sTokenBalance = asset.sToken.balanceOf(msg.sender);
        if (_params.amount > sTokenBalance) {
            _params.amount = sTokenBalance;
        }

        uint256 underlyingAmount = asset.sToken.burn(
            msg.sender,
            _params.amount,
            protocolsSupplies + totalLending
        );

        uint256 sTokenAmount;
        (_params.amount, sTokenAmount) = (underlyingAmount, _params.amount);

        // pay in protocol
        _redeem(
            _params,
            sTokenAmount,
            totalSupply,
            supplies,
            protocolsSupplies,
            totalLending
        );
        config.setUsingAsCollateral(msg.sender, asset.index, _collateralable);
    }

    function _redeem(
        Types.UserAssetParams memory _params,
        uint256 _sTokenAmount,
        uint256 _sTokenTotalSupply,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending
    ) internal {
        IProtocolsHandler protocolsCache = protocols;

        uint256 protocolsRedeemed;
        uint256 redeemed;
        if (_protocolsSupplies > 0) {
            (protocolsRedeemed, redeemed) = protocolsCache.redeem(
                _params.asset,
                _params.amount,
                _supplies,
                _protocolsSupplies,
                _params.to
            );
        }

        if (_params.amount > protocolsRedeemed) {
            _params.amount -= protocolsRedeemed;
            uint256 borrowed = protocolsCache.borrow(_params);
            _totalLending = _totalLending > borrowed
                ? _totalLending - borrowed
                : 0;

            redeemed += borrowed;
            updatetotalLendings(_params.asset, _totalLending);
            protocolsCache.simulateSupply(_params.asset, _totalLending);
        }

        rewards.stopMiningSupplyReward(
            _params.asset,
            msg.sender,
            _sTokenAmount,
            _sTokenTotalSupply
        );

        emit Redeemed(msg.sender, _params.asset, redeemed);
    }

    function borrow(Types.UserAssetParams memory _params) public {
        require(borrowAllowed(_params), "Router: borrow not allowed");

        IProtocolsHandler protocolsCache = protocols;
        Types.Asset memory asset = assets[_params.asset];
        uint256 totalLending = protocolsCache.simulateLendings(
            _params.asset,
            totalLendings[_params.asset]
        );

        (, uint256 protocolsBorrows) = protocolsCache.totalBorrowed(
            _params.asset
        );

        uint256 dTokenAmount = asset.dToken.mint(
            msg.sender,
            _params.amount,
            protocolsBorrows + totalLendings[_params.asset]
        );

        config.setBorrowing(msg.sender, asset.index, true);

        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_params.asset);

        uint256 protocolsRedeemed;
        uint256 borrowed;
        if (protocolsSupplies > 0) {
            (protocolsRedeemed, borrowed) = protocolsCache.redeem(
                _params.asset,
                _params.amount,
                supplies,
                protocolsSupplies,
                _params.to
            );

            if (borrowed > 0) {
                totalLending += borrowed;
                updatetotalLendings(_params.asset, totalLending);
                protocolsCache.simulateBorrow(_params.asset, totalLending);
            }
        }

        if (_params.amount > protocolsRedeemed) {
            _params.amount -= protocolsRedeemed;
            borrowed += protocolsCache.borrow(_params);
        }

        rewards.startMiningBorrowReward(
            _params.asset,
            _params.to,
            dTokenAmount,
            asset.dToken.totalSupply()
        );

        emit Borrowed(msg.sender, _params.asset, _params.amount);
    }

    function repay(Types.UserAssetParams memory _params) public payable {
        IProtocolsHandler protocolsCache = protocols;

        Types.Asset memory asset = assets[_params.asset];
        uint256 userDebts = asset.dToken.scaledDebtOf(_params.to);
        if (_params.amount > userDebts) {
            _params.amount = userDebts;
        }

        TransferHelper.collect(
            _params.asset,
            msg.sender,
            address(protocolsCache),
            _params.amount,
            0
        );

        if (_params.asset == TransferHelper.ETH && msg.value > _params.amount) {
            TransferHelper.transferETH(
                msg.sender,
                _params.amount - userDebts,
                0
            );
        }

        uint256 totalLending = protocolsCache.simulateLendings(
            _params.asset,
            totalLendings[_params.asset]
        );

        (, uint256 protocolsBorrows) = protocolsCache.totalBorrowed(
            _params.asset
        );

        uint256 totalSupply = asset.dToken.totalSupply();
        uint256 dTokenAmount = asset.dToken.burn(
            _params.to,
            _params.amount,
            protocolsBorrows + totalLending
        );

        uint256 repayed = protocolsCache.repay(_params);
        if (_params.amount > repayed) {
            (
                uint256[] memory supplies,
                uint256 protocolsSupplies
            ) = protocolsCache.totalSupplied(_params.asset);
            uint256 supplied = protocolsCache.supply(
                _params.asset,
                _params.amount - repayed,
                supplies,
                protocolsSupplies
            );

            if (supplied > 0) {
                totalLending -= supplied;
                updatetotalLendings(_params.asset, totalLending);
                protocolsCache.simulateBorrow(_params.asset, totalLending);
            }
        }

        rewards.stopMiningBorrowReward(
            _params.asset,
            _params.to,
            dTokenAmount,
            totalSupply
        );

        emit Repayed(_params.to, _params.asset, _params.amount);
    }

    function liquidate(
        Types.UserAssetParams memory _repayParams,
        Types.UserAssetParams memory _redeemParams
    ) public payable {
        Types.BorrowConfig memory bc = config.borrowConfigs(_repayParams.asset);
        _repayParams.amount = validateLiquidatation(_repayParams, bc);

        repay(_repayParams);

        IProtocolsHandler protocolsCache = protocols;
        ISToken sToken = assets[_redeemParams.asset].sToken;

        uint256 assetValue = priceOracle.valueOfAsset(
            _repayParams.asset,
            _redeemParams.asset,
            _repayParams.amount
        );

        _redeemParams.amount = Utils.minOf(
            (assetValue * bc.liquidateRewardRatio) / Utils.MILLION,
            sToken.scaledBalanceOf(_repayParams.to)
        );

        (uint256[] memory supplies, uint256 protocolsSupplies) = protocolsCache
            .totalSupplied(_redeemParams.asset);
        uint256 totalLending = protocolsCache.simulateLendings(
            _redeemParams.asset,
            totalLendings[_redeemParams.asset]
        );

        uint256 underlyingAmount = sToken.burn(
            _repayParams.to,
            sToken.unscaledAmount(_redeemParams.amount),
            protocolsSupplies + totalLending
        );

        uint256 sTokenAmount;
        (_redeemParams.amount, sTokenAmount) = (
            underlyingAmount,
            _redeemParams.amount
        );

        _redeem(
            _redeemParams,
            sTokenAmount,
            sToken.totalSupply(),
            supplies,
            protocolsSupplies,
            totalLending
        );
    }

    function claimRewards(address _account) external {
        uint256 userConfig = config.userDebtAndCollateral(_account);
        uint256[] memory rewardsToClaim;

        for (uint256 i = 0; i < underlyings.length; i++) {
            if (UserAssetBitMap.isUsingAsCollateralOrBorrowing(userConfig, i)) {
                Types.Asset memory asset = assets[underlyings[i]];

                if (UserAssetBitMap.isUsingAsCollateral(userConfig, i)) {
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

                if (UserAssetBitMap.isBorrowing(userConfig, i)) {
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
        (uint256 collateralValue, uint256 debtsValue) = userStatus(
            _params.to,
            _params.asset
        );

        uint256 borrowLimit = (collateralValue * bc.liquidateLTV) /
            Utils.MILLION;
        return _params.amount + debtsValue < borrowLimit;
    }

    function validateLiquidatation(
        Types.UserAssetParams memory _params,
        Types.BorrowConfig memory _bc
    ) internal view returns (uint256) {
        (uint256 collateralValue, uint256 debtsValue) = userStatus(
            _params.to,
            _params.asset
        );

        require(
            debtsValue * Utils.MILLION > _bc.liquidateLTV * collateralValue,
            "Router: Liquidate not allowed"
        );

        uint256 maxLiquidation = (debtsValue * _bc.maxLiquidateRatio) /
            Utils.MILLION;

        return
            _params.amount < maxLiquidation ? _params.amount : maxLiquidation;
    }

    function updatetotalLendings(address _asset, uint256 _new) internal {
        uint256 old = totalLendings[_asset];
        totalLendings[_asset] = _new;
        emit TotalLendingsUpdated(_asset, old, _new);
    }

    function userStatus(address _account, address _quote)
        public
        view
        returns (uint256 collateralValue, uint256 borrowingValue)
    {
        uint256 userConfig = config.userDebtAndCollateral(_account);
        for (uint256 i = 0; i < underlyings.length; i++) {
            if (UserAssetBitMap.isUsingAsCollateralOrBorrowing(userConfig, i)) {
                Types.Asset memory asset = assets[underlyings[i]];

                if (UserAssetBitMap.isUsingAsCollateral(userConfig, i)) {
                    address underlying = asset.sToken.underlying();
                    uint256 balance = asset.sToken.scaledBalanceOf(_account);

                    collateralValue += underlying == _quote
                        ? balance
                        : priceOracle.valueOfAsset(underlying, _quote, balance);
                }

                if (UserAssetBitMap.isBorrowing(userConfig, i)) {
                    address underlying = asset.dToken.underlying();
                    uint256 balance = asset.dToken.scaledDebtOf(_account);

                    borrowingValue += underlying == _quote
                        ? balance
                        : priceOracle.valueOfAsset(underlying, _quote, balance);
                }
            }
        }
    }

    function getUnderlyings() public view override returns (address[] memory) {
        return underlyings;
    }

    function getAssets()
        public
        view
        override
        returns (Types.Asset[] memory _assets)
    {
        _assets = new Types.Asset[](underlyings.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            _assets[i] = assets[underlyings[i]];
        }
    }

    function totalSupplied(address _underlying)
        public
        view
        override
        returns (uint256)
    {
        IProtocolsHandler protocolsCache = protocols;
        (, uint256 protocolsSupplies) = protocolsCache.totalSupplied(
            _underlying
        );
        uint256 totalLending = protocolsCache.simulateLendings(
            _underlying,
            totalLendings[_underlying]
        );

        return protocolsSupplies + totalLending;
    }

    function totalBorrowed(address _underlying)
        public
        view
        override
        returns (uint256)
    {
        IProtocolsHandler protocolsCache = protocols;
        (, uint256 protocolsBorrows) = protocolsCache.totalBorrowed(
            _underlying
        );
        uint256 totalLending = protocolsCache.simulateLendings(
            _underlying,
            totalLendings[_underlying]
        );

        return protocolsBorrows + totalLending;
    }

    //  admin functions
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
