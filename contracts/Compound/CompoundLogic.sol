// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProtocol.sol";
import "./CERC20Interface.sol";
import "./CETHInterface.sol";
import "./ComptrollerInterface.sol";

import "../libraries/Utils.sol";
import "../libraries/Math.sol";
import "../libraries/TransferHelper.sol";

contract CompoundLogic is IProtocol {
    using Math for uint256;

    struct SimulateData {
        uint256 amount;
        uint256 index;
    }

    uint256 public immutable BASE = 1e12;
    uint256 public immutable BLOCK_PER_YEAR = 2102400;

    ComptrollerInterface public comptroller;
    address public compTokenAddress;

    mapping(address => address) public cTokens;
    mapping(address => uint256) public underlyingUnit;

    mapping(address => address) public initialized;
    mapping(address => mapping(address => SimulateData))
        public lastSimulatedSupply;
    mapping(address => mapping(address => SimulateData))
        public lastSimulatedBorrow;

    constructor(
        address _comptroller,
        address _cETH,
        address _compTokenAddress
    ) {
        comptroller = ComptrollerInterface(_comptroller);
        (bool isListed, , ) = comptroller.markets(_cETH);
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[TransferHelper.ETH] = _cETH;
        underlyingUnit[_cETH] = 1e18;

        compTokenAddress = _compTokenAddress;
    }

    receive() external payable {}

    function setInitialized(address _underlying) external override {}

    function updateSupplyShare(address _underlying, uint256 _amount)
        external
        override
    {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);

        lastSimulatedSupply[_underlying][msg.sender] = SimulateData(
            _amount,
            getSupplyIndex(_underlying, cToken)
        );
    }

    function updateBorrowShare(address _underlying, uint256 _amount)
        external
        override
    {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);

        (, , , uint256 borrowIndex) = accrueInterest(_underlying, cToken);
        lastSimulatedBorrow[_underlying][msg.sender] = SimulateData(
            _amount,
            borrowIndex
        );
    }

    function lastSupplyInterest(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        SimulateData memory data = lastSimulatedSupply[_underlying][_account];
        uint256 deltaIndex = getSupplyIndex(_underlying, cToken) - data.index;

        return (deltaIndex * data.amount) / data.index;
    }

    function lastBorrowInterest(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        SimulateData memory data = lastSimulatedBorrow[_underlying][_account];

        (, , , uint256 borrowIndex) = accrueInterest(_underlying, cToken);
        uint256 deltaIndex = borrowIndex - data.index;
        return (deltaIndex * data.amount) / data.index;
        // return deltaIndex;
    }

    function getAddAssetData(address _underlying)
        external
        view
        returns (Types.ProtocolData memory data)
    {
        address[] memory underlyings = new address[](1);
        underlyings[0] = cTokens[_underlying];
        data.target = address(comptroller);
        data.encodedData = abi.encodeWithSelector(
            comptroller.enterMarkets.selector,
            underlyings
        );
    }

    // call by delegates public functions
    function getSupplyData(address _underlying, uint256 _amount)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = cTokens[_underlying];
        if (_underlying == TransferHelper.ETH) {
            data.encodedData = abi.encodeWithSelector(
                CETHInterface.mint.selector
            );
        } else {
            data.approveTo = data.target;
            data.encodedData = abi.encodeWithSelector(
                CERC20Interface.mint.selector,
                _amount
            );
        }
        data.initialized = initialized[_underlying] == msg.sender;
    }

    function getRedeemData(address _underlying, uint256 _amount)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = cTokens[_underlying];
        uint256 cTokenSupply = CTokenInterface(data.target).totalSupply();
        (
            uint256 totalCash,
            uint256 totalBorrows,
            uint256 totalReserves,

        ) = accrueInterest(_underlying, CTokenInterface(data.target));
        uint256 underlyingValue = totalCash + totalBorrows - totalReserves;

        data.encodedData = abi.encodeWithSelector(
            CERC20Interface.redeem.selector,
            underlyingValue > 0 ? (_amount * cTokenSupply) / underlyingValue : 0
        );
    }

    function getRedeemAllData(address _underlying)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = cTokens[_underlying];
        data.encodedData = abi.encodeWithSelector(
            CERC20Interface.redeem.selector,
            CERC20Interface(data.target).balanceOf(address(this))
        );
    }

    function getBorrowData(address _underlying, uint256 _amount)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = cTokens[_underlying];
        data.encodedData = abi.encodeWithSelector(
            CERC20Interface.borrow.selector,
            _amount
        );
    }

    function getRepayData(address _underlying, uint256 _amount)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = cTokens[_underlying];
        if (_underlying == TransferHelper.ETH) {
            data.encodedData = abi.encodeWithSelector(
                CETHInterface.repayBorrow.selector
            );
        } else {
            data.approveTo = data.target;
            data.encodedData = abi.encodeWithSelector(
                CERC20Interface.repayBorrow.selector,
                _amount
            );
        }
    }

    function getClaimRewardData(address _rewardToken)
        external
        view
        override
        returns (Types.ProtocolData memory data)
    {
        data.target = address(comptroller);
        data.encodedData = abi.encodeWithSelector(
            ComptrollerInterface.claimComp.selector,
            msg.sender
        );
    }

    function getClaimUserRewardData(
        address _underlying,
        Types.UserShare memory _share,
        bytes memory _user,
        bytes memory _router
    )
        external
        view
        override
        returns (
            bytes memory,
            bytes memory,
            address,
            uint256
        )
    {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        Types.UserCompRewardData memory userRewardData = abi.decode(
            _user,
            (Types.UserCompRewardData)
        );
        Types.RouterCompRewardData memory routerRewardData = abi.decode(
            _router,
            (Types.RouterCompRewardData)
        );

        routerRewardData = newSupplyReward(
            cToken,
            routerRewardData,
            _share.total
        );
        routerRewardData = newBorrowReward(
            cToken,
            routerRewardData,
            _share.total
        );

        userRewardData.supply.rewardAccured +=
            (routerRewardData.supply.rewardPerShare -
                userRewardData.supply.rewardPerShare) *
            _share.amount;
        userRewardData.supply.rewardPerShare = routerRewardData
            .supply
            .rewardPerShare;
        userRewardData.borrow.rewardAccured +=
            (routerRewardData.borrow.rewardPerShare -
                userRewardData.borrow.rewardPerShare) *
            _share.amount;
        userRewardData.borrow.rewardPerShare = routerRewardData
            .borrow
            .rewardPerShare;

        uint256 amount = userRewardData.supply.rewardAccured -
            userRewardData.supply.rewardCollected +
            userRewardData.borrow.rewardAccured -
            userRewardData.borrow.rewardCollected;
        userRewardData.supply.rewardCollected = userRewardData
            .supply
            .rewardAccured;
        userRewardData.borrow.rewardCollected = userRewardData
            .borrow
            .rewardAccured;
        return (
            abi.encode(userRewardData),
            abi.encode(routerRewardData),
            compTokenAddress,
            amount
        );
    }

    // return underlying Token
    // return data for caller
    function supplyOf(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (
            uint256 totalCash,
            uint256 totalBorrows,
            uint256 totalReserves,

        ) = accrueInterest(_underlying, cToken);
        uint256 cTokentotalSupply = cToken.totalSupply();
        return
            cTokentotalSupply > 0
                ? ((totalCash + totalBorrows - totalReserves) *
                    cToken.balanceOf(_account)) / cTokentotalSupply
                : 0;
    }

    function debtOf(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (, , , uint256 borrowIndex) = accrueInterest(_underlying, cToken);
        return
            (cToken.borrowBalanceStored(_account) * borrowIndex) /
            cToken.borrowIndex();
    }

    function totalColletralAndBorrow(address _account, address _quote)
        external
        view
        returns (uint256 collateralValue, uint256 borrowValue)
    {
        // For each asset the account is in
        CTokenInterface[] memory userCTokens = comptroller.getAssetsIn(
            _account
        );
        IOracle oracle = comptroller.oracle();
        for (uint256 i = 0; i < userCTokens.length; i++) {
            CTokenInterface cToken = userCTokens[i];
            // Read the balances and exchange rate from the cToken
            (
                ,
                uint256 cTokenBalance,
                uint256 borrowBalance,
                uint256 exchangeRate
            ) = cToken.getAccountSnapshot(_account);

            uint256 oraclePrice = oracle.getUnderlyingPrice(cToken);
            require(oraclePrice > 0, "Compound Logic: Price Not found");

            uint256 underlyingAmount = (cTokenBalance * exchangeRate) /
                Utils.QUINTILLION;
            collateralValue += underlyingAmount * oraclePrice;

            borrowValue += borrowBalance * oraclePrice;
        }

        address cQuote = cTokens[_quote];
        uint256 oraclePriceQuote = oracle.getUnderlyingPrice(
            CTokenInterface(cQuote)
        );
        require(oraclePriceQuote > 0, "Compound Logic: Price Not found");

        collateralValue = collateralValue / oraclePriceQuote;
        borrowValue = borrowValue / oraclePriceQuote;
    }

    function supplyToTargetSupplyRate(uint256 _targetRate, bytes memory _params)
        external
        pure
        override
        returns (int256)
    {
        Types.CompoundUsageParams memory params = abi.decode(
            _params,
            (Types.CompoundUsageParams)
        );

        _targetRate = (_targetRate * Utils.MILLION) / params.reserveFactor;

        uint256 delta = params.base *
            params.base +
            4 *
            params.slope1 *
            _targetRate;
        uint256 supply = (params.totalBorrowed * (params.base + delta.sqrt())) /
            (_targetRate + _targetRate);

        if (params.totalBorrowed * Utils.MILLION > supply * params.optimalLTV) {
            params.base += (params.optimalLTV * params.slope1) / Utils.MILLION;

            uint256 a = params.slope2 *
                params.optimalLTV -
                params.base *
                Utils.MILLION;
            delta = (a / Utils.MILLION)**2 + 4 * params.slope2 * _targetRate;
            supply =
                (params.totalBorrowed * (Utils.MILLION * delta.sqrt() - a)) /
                ((_targetRate + _targetRate) * Utils.MILLION);
        }

        return int256(supply) - int256(params.totalSupplied);
    }

    function borrowToTargetBorrowRate(uint256 _targetRate, bytes memory _params)
        external
        pure
        returns (int256)
    {
        Types.CompoundUsageParams memory params = abi.decode(
            _params,
            (Types.CompoundUsageParams)
        );

        if (_targetRate < params.base) {
            _targetRate = params.base;
        }

        uint256 borrow = ((_targetRate - params.base) * params.totalSupplied) /
            (params.slope1);

        if (borrow * Utils.MILLION > params.totalSupplied * params.optimalLTV) {
            params.base += (params.optimalLTV * params.slope1) / Utils.MILLION;
            borrow =
                (((_targetRate - params.base) *
                    Utils.MILLION +
                    params.optimalLTV *
                    params.slope2) * params.totalSupplied) /
                (params.slope2 * Utils.MILLION);
        }

        return int256(borrow) - int256(params.totalBorrowed);
    }

    function getUsageParams(address _underlying, uint256 _suppliesToRedeem)
        external
        view
        override
        returns (bytes memory)
    {
        CTokenInterface cToken = CTokenInterface(cTokens[_underlying]);
        (
            uint256 totalCash,
            uint256 totalBorrows,
            uint256 totalReserves,

        ) = accrueInterest(_underlying, cToken);

        InterestRateModel interestRateModel = cToken.interestRateModel();

        Types.CompoundUsageParams memory params = Types.CompoundUsageParams(
            totalCash + totalBorrows - totalReserves - _suppliesToRedeem,
            totalBorrows,
            (interestRateModel.multiplierPerBlock() * BLOCK_PER_YEAR) / BASE,
            (interestRateModel.jumpMultiplierPerBlock() * BLOCK_PER_YEAR) /
                BASE,
            (interestRateModel.baseRatePerBlock() * BLOCK_PER_YEAR) / BASE,
            interestRateModel.kink() / BASE,
            Utils.MILLION - cToken.reserveFactorMantissa() / BASE
        );

        return abi.encode(params);
    }

    function updateCTokenList(address _cToken, uint256 _decimals) external {
        (bool isListed, , ) = comptroller.markets(address(_cToken));
        require(isListed, "CompoundLogic: cToken Not Listed");
        cTokens[CTokenInterface(_cToken).underlying()] = _cToken;
        underlyingUnit[_cToken] = 10**_decimals;
    }

    function getAccountSnapshot(CTokenInterface cToken, address account)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        address underlying;
        if (address(cToken) == cTokens[TransferHelper.ETH]) {
            underlying == TransferHelper.ETH;
        } else {
            underlying == cToken.underlying();
        }

        (
            uint256 totalCash,
            uint256 totalBorrows,
            uint256 totalReserves,
            uint256 _borrowIndexCurrent
        ) = accrueInterest(underlying, cToken);
        uint256 totalSupply = cToken.totalSupply();

        return (
            cToken.balanceOf(account),
            (cToken.borrowBalanceStored(account) * _borrowIndexCurrent) /
                cToken.borrowIndex(),
            totalSupply > 0
                ? ((totalCash + totalBorrows - totalReserves) *
                    Utils.QUINTILLION) / totalSupply
                : 0
        );
    }

    function accrueInterest(address _underlying, CTokenInterface _cToken)
        internal
        view
        returns (
            uint256 totalCash,
            uint256 totalBorrows,
            uint256 totalReserves,
            uint256 borrowIndex
        )
    {
        totalCash = TransferHelper.balanceOf(_underlying, address(_cToken));
        totalBorrows = _cToken.totalBorrows();
        totalReserves = _cToken.totalReserves();
        borrowIndex = _cToken.borrowIndex();

        uint256 blockDelta = block.number - _cToken.accrualBlockNumber();

        if (blockDelta > 0) {
            uint256 borrowRateMantissa = _cToken
                .interestRateModel()
                .getBorrowRate(totalCash, totalBorrows, totalReserves);
            uint256 simpleInterestFactor = borrowRateMantissa * blockDelta;
            uint256 interestAccumulated = (simpleInterestFactor *
                totalBorrows) / Utils.QUINTILLION;
            totalBorrows = interestAccumulated + totalBorrows;
            totalReserves =
                (_cToken.reserveFactorMantissa() * interestAccumulated) /
                Utils.QUINTILLION +
                totalReserves;
            borrowIndex =
                (simpleInterestFactor * borrowIndex) /
                Utils.QUINTILLION +
                borrowIndex;
        }
    }

    function getCurrentSupplyRate(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        return
            (CTokenInterface(cTokens[_underlying]).supplyRatePerBlock() *
                BLOCK_PER_YEAR) / BASE;
    }

    function getCurrentBorrowRate(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        return
            (CTokenInterface(cTokens[_underlying]).borrowRatePerBlock() *
                BLOCK_PER_YEAR) / BASE;
    }

    function getRewardSupplyData(
        address _underlying,
        Types.UserShare memory _share,
        bytes memory _user,
        bytes memory _router
    ) external view override returns (bytes memory, bytes memory) {
        Types.RouterCompRewardData memory routerRewardData = newSupplyReward(
            CTokenInterface(cTokens[_underlying]),
            abi.decode(_router, (Types.RouterCompRewardData)),
            _share.total
        );

        Types.UserCompRewardData memory userRewardData;
        if (_share.amount > 0) {
            userRewardData = abi.decode(_user, (Types.UserCompRewardData));
        }

        userRewardData.supply.rewardAccured +=
            (routerRewardData.supply.rewardPerShare -
                userRewardData.supply.rewardPerShare) *
            _share.amount;
        userRewardData.supply.rewardPerShare = routerRewardData
            .supply
            .rewardPerShare;

        return (abi.encode(userRewardData), abi.encode(routerRewardData));
    }

    function getRouterRewardSupplyData(
        address _underlying,
        uint256 _totalShare,
        bytes memory _router
    ) external view override returns (bytes memory) {
        return
            abi.encode(
                newSupplyReward(
                    CTokenInterface(cTokens[_underlying]),
                    abi.decode(_router, (Types.RouterCompRewardData)),
                    _totalShare
                )
            );
    }

    function getRewardBorrowData(
        address _underlying,
        Types.UserShare memory _share,
        bytes memory _user,
        bytes memory _router
    ) external view override returns (bytes memory, bytes memory) {
        Types.RouterCompRewardData memory routerRewardData = newBorrowReward(
            CTokenInterface(cTokens[_underlying]),
            abi.decode(_router, (Types.RouterCompRewardData)),
            _share.total
        );

        Types.UserCompRewardData memory userRewardData;
        if (_share.amount > 0) {
            userRewardData = abi.decode(_user, (Types.UserCompRewardData));
        }

        userRewardData.borrow.rewardAccured +=
            (routerRewardData.borrow.rewardPerShare -
                userRewardData.borrow.rewardPerShare) *
            _share.amount;
        userRewardData.borrow.rewardPerShare = routerRewardData
            .borrow
            .rewardPerShare;

        return (abi.encode(userRewardData), abi.encode(routerRewardData));
    }

    function newSupplyReward(
        CTokenInterface cToken,
        Types.RouterCompRewardData memory _params,
        uint256 _totalShare
    ) internal view returns (Types.RouterCompRewardData memory) {
        (uint256 supplyIndex, ) = comptroller.compSupplyState(address(cToken));
        uint256 amount = (cToken.balanceOf(msg.sender) *
            (supplyIndex - _params.supply.index)) / Utils.UNDECILLION;
        _params.supply.index = supplyIndex;
        _params.supply.rewardPerShare += amount / _totalShare;
        return _params;
    }

    function newBorrowReward(
        CTokenInterface cToken,
        Types.RouterCompRewardData memory _params,
        uint256 _totalShare
    ) internal view returns (Types.RouterCompRewardData memory) {
        (uint256 borrowIndex, ) = comptroller.compBorrowState(address(cToken));
        uint256 amount = (cToken.borrowBalanceStored(msg.sender) *
            Utils.QUINTILLION) / cToken.borrowIndex();
        amount = ((amount * (borrowIndex - _params.borrow.index)) /
            Utils.UNDECILLION);

        _params.borrow.index = borrowIndex;
        _params.borrow.rewardPerShare += amount / _totalShare;
        return _params;
    }

    function getSupplyIndex(address _underlying, CTokenInterface cToken)
        public
        view
        returns (uint256 supplyIndex)
    {
        uint256 supplyTokens = cToken.totalSupply();

        (
            uint256 totalCash,
            uint256 totalBorrows,
            uint256 totalReserves,

        ) = accrueInterest(_underlying, cToken);

        supplyIndex = supplyTokens > 0
            ? ((totalCash + totalBorrows - totalReserves) * Utils.QUINTILLION) /
                supplyTokens
            : Utils.QUINTILLION;
    }
}
