// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../interfaces/IProtocol.sol";
import "./CERC20Interface.sol";
import "./CETHInterface.sol";

import "../libraries/internals/Utils.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./CompoundLogicStorage.sol";

contract CompoundLogic is IProtocol {
    using Math for uint256;

    CompoundLogicStorage public immutable LOGIC_STORAGE;
    uint256 public immutable BASE = 1e12;
    uint256 public immutable BLOCK_PER_YEAR = 2102400;

    constructor(
        address _protocolsHandler,
        address _comptroller,
        address _cETH,
        address _compTokenAddress
    ) {
        // for testing purpose
        if (_protocolsHandler == address(0)) {
            _protocolsHandler = address(this);
        }
        LOGIC_STORAGE = new CompoundLogicStorage(
            _protocolsHandler,
            _comptroller,
            _cETH,
            _compTokenAddress
        );
    }

    receive() external payable {}

    function updateSupplyShare(address _underlying, uint256 _amount)
        external
        override
    {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );

        CompoundLogicStorage.SimulateData memory data = CompoundLogicStorage
            .SimulateData(_amount, getSupplyIndex(_underlying, cToken));

        LOGIC_STORAGE.setLastSimulatedSupply(_underlying, data);

        emit SupplyShareUpdated(_underlying, _amount, abi.encode(data));
    }

    function updateBorrowShare(address _underlying, uint256 _amount)
        external
        override
    {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );

        (, , , uint256 borrowIndex) = accrueInterest(_underlying, cToken);

        CompoundLogicStorage.SimulateData memory data = CompoundLogicStorage
            .SimulateData(_amount, borrowIndex);

        LOGIC_STORAGE.setLastSimulatedBorrow(_underlying, data);

        emit BorrowShareUpdated(_underlying, _amount, abi.encode(data));
    }

    function lastSupplyInterest(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );
        CompoundLogicStorage.SimulateData memory data = LOGIC_STORAGE
            .getLastSimulatedSupply(_underlying);
        if (data.index == 0) {
            return 0;
        }

        uint256 deltaIndex = getSupplyIndex(_underlying, cToken) - data.index;

        return (deltaIndex * data.amount) / data.index;
    }

    function lastBorrowInterest(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );
        CompoundLogicStorage.SimulateData memory data = LOGIC_STORAGE
            .getLastSimulatedBorrow(_underlying);
        if (data.index == 0) {
            return 0;
        }

        (, , , uint256 borrowIndex) = accrueInterest(_underlying, cToken);
        uint256 deltaIndex = borrowIndex - data.index;
        return (deltaIndex * data.amount) / data.index;
    }

    function supply(address _underlying, uint256 _amount) external override {
        address cToken = LOGIC_STORAGE.cTokens(_underlying);

        if (_underlying == TransferHelper.ETH) {
            CETHInterface(cToken).mint{value: _amount}();
        } else {
            TransferHelper.approve(_underlying, cToken, _amount);
            CERC20Interface(cToken).mint(_amount);
        }

        addAsset(_underlying);
    }

    function redeem(address _underlying, uint256 _amount) external {
        CERC20Interface(LOGIC_STORAGE.cTokens(_underlying)).redeemUnderlying(
            _amount
        );
    }

    function borrow(address _underlying, uint256 _amount) external {
        CERC20Interface(LOGIC_STORAGE.cTokens(_underlying)).borrow(_amount);
    }

    function repay(address _underlying, uint256 _amount) external {
        address cToken = LOGIC_STORAGE.cTokens(_underlying);
        if (_underlying == TransferHelper.ETH) {
            CETHInterface(cToken).repayBorrow{value: _amount}();
        } else {
            TransferHelper.approve(_underlying, cToken, _amount);
            CERC20Interface(cToken).repayBorrow(_amount);
        }
    }

    function claimRewards(address _account) external override {
        LOGIC_STORAGE.comptroller().claimComp(_account);
    }

    // return underlying Token
    // return data for caller
    function supplyOf(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );
        (
            uint256 totalCash,
            uint256 totalBorrows,
            uint256 totalReserves,

        ) = accrueInterest(_underlying, cToken);
        uint256 cTokentotalSupply = cToken.totalSupply();
        uint256 cTokenBalance = cToken.balanceOf(_account);

        // Compound reverts redeemUnderlying(_underlyingAmount) calls when user cToken
        // balance is 1. Floor division has been applied to calculate cToken when
        // redeeming, which should be replaced by ceil division.This rounding error
        // may cause users to "redeem" underlying tokens without their cToken burnt.
        // This error can be applied by repeatedly redeeming small amounts of underlyings,
        // an extra decent amount of tokens can be stolen by the attacker.
        if (cTokenBalance == 1) {
            cTokenBalance = 0;
        }

        return
            cTokentotalSupply > 0
                ? ((totalCash + totalBorrows - totalReserves) * cTokenBalance) /
                    (cTokentotalSupply)
                : 0;
    }

    function debtOf(address _underlying, address _account)
        external
        view
        override
        returns (uint256)
    {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );
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
        CTokenInterface[] memory userCTokens = LOGIC_STORAGE
            .comptroller()
            .getAssetsIn(_account);
        IOracle oracle = LOGIC_STORAGE.comptroller().oracle();

        for (uint256 i = 0; i < userCTokens.length; ++i) {
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

        address cQuote = LOGIC_STORAGE.cTokens(_quote);
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
        uint256 supplyAmount = (params.totalBorrowed *
            (params.base + delta.sqrt())) / (_targetRate + _targetRate);

        if (
            params.totalBorrowed * Utils.MILLION >
            supplyAmount * params.optimalLTV
        ) {
            params.base += (params.optimalLTV * params.slope1) / Utils.MILLION;

            uint256 a = params.slope2 *
                params.optimalLTV -
                params.base *
                Utils.MILLION;
            delta =
                ((a * a) / Utils.TRILLION) +
                4 *
                params.slope2 *
                _targetRate;
            supplyAmount =
                (params.totalBorrowed * (Utils.MILLION * delta.sqrt() - a)) /
                ((_targetRate + _targetRate) * Utils.MILLION);
        }

        return int256(supplyAmount) - int256(params.totalSupplied);
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

        uint256 borrowAmount = ((_targetRate - params.base) *
            params.totalSupplied) / (params.slope1);

        if (
            borrowAmount * Utils.MILLION >
            params.totalSupplied * params.optimalLTV
        ) {
            params.base += (params.optimalLTV * params.slope1) / Utils.MILLION;
            borrowAmount =
                (((_targetRate - params.base) *
                    Utils.MILLION +
                    params.optimalLTV *
                    params.slope2) * params.totalSupplied) /
                (params.slope2 * Utils.MILLION);
        }

        return int256(borrowAmount) - int256(params.totalBorrowed);
    }

    function lastSimulatedSupply(address _asset)
        external
        view
        returns (CompoundLogicStorage.SimulateData memory)
    {
        return LOGIC_STORAGE.getLastSimulatedSupply(_asset);
    }

    function lastSimulatedBorrow(address _asset)
        external
        view
        returns (CompoundLogicStorage.SimulateData memory)
    {
        return LOGIC_STORAGE.getLastSimulatedBorrow(_asset);
    }

    function getUsageParams(address _underlying, uint256 _suppliesToRedeem)
        external
        view
        override
        returns (bytes memory)
    {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );
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

    function updateCTokenList(address _cToken) external {
        LOGIC_STORAGE.updateCTokenList(_cToken);
    }

    function totalRewards(
        address _underlying,
        address _account,
        bool _isSupply
    ) external view override returns (uint256 rewards) {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );

        return
            _isSupply
                ? getSupplyReward(cToken, _account)
                : getBorrowReward(cToken, _account);
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
            totalBorrows = totalBorrows + interestAccumulated;
            totalReserves =
                totalReserves +
                (_cToken.reserveFactorMantissa() * interestAccumulated) /
                Utils.QUINTILLION;
            borrowIndex =
                borrowIndex +
                (simpleInterestFactor * borrowIndex) /
                Utils.QUINTILLION;
        }
    }

    function getCurrentSupplyRate(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        return
            (CTokenInterface(LOGIC_STORAGE.cTokens(_underlying))
                .supplyRatePerBlock() * BLOCK_PER_YEAR) / BASE;
    }

    function getCurrentBorrowRate(address _underlying)
        external
        view
        override
        returns (uint256)
    {
        return
            (CTokenInterface(LOGIC_STORAGE.cTokens(_underlying))
                .borrowRatePerBlock() * BLOCK_PER_YEAR) / BASE;
    }

    function addAsset(address _underlying) internal {
        address[] memory underlyings = new address[](1);
        underlyings[0] = LOGIC_STORAGE.cTokens(_underlying);
        LOGIC_STORAGE.comptroller().enterMarkets(underlyings);
    }

    function getSupplyReward(CTokenInterface _cToken, address _account)
        internal
        view
        returns (uint256 rewards)
    {
        (uint256 supplyIndex, uint256 blockNumber) = LOGIC_STORAGE
            .comptroller()
            .compSupplyState(address(_cToken));

        uint256 deltaBlocks = block.number - blockNumber;

        uint256 supplySpeed = LOGIC_STORAGE.comptroller().compSupplySpeeds(
            address(_cToken)
        );
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint256 totalSupply = _cToken.totalSupply();
            uint256 compAccrued = deltaBlocks * supplySpeed;
            uint256 ratio = totalSupply > 0
                ? (compAccrued * 1e36) / totalSupply
                : 0;
            supplyIndex += ratio;
        }

        uint256 supplierIndex = 1e36;

        uint256 deltaIndex = supplyIndex - supplierIndex;

        uint256 supplierTokens = _cToken.balanceOf(_account);
        rewards = (supplierTokens * deltaIndex) / 1e36;
    }

    function getBorrowReward(CTokenInterface _cToken, address _account)
        internal
        view
        returns (uint256 rewards)
    {
        (uint256 borrowIndex, uint256 blockNumber) = LOGIC_STORAGE
            .comptroller()
            .compBorrowState(address(_cToken));

        uint256 deltaBlocks = block.number - blockNumber;
        uint256 borrowSpeed = LOGIC_STORAGE.comptroller().compBorrowSpeeds(
            address(_cToken)
        );
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint256 totalBorrow = (_cToken.totalBorrows() * 1e36) /
                _cToken.borrowIndex();
            uint256 compAccrued = (deltaBlocks * borrowSpeed) / 1e36;
            uint256 ratio = totalBorrow > 0
                ? (compAccrued * 1e36) / totalBorrow
                : 0;
            borrowIndex += ratio;
        }

        uint256 borrowerIndex = 1e36;

        uint256 deltaIndex = borrowIndex - borrowerIndex;

        (, , uint256 borrowBalance, ) = _cToken.getAccountSnapshot(_account);
        uint256 borrowAmount = (borrowBalance * 1e36) / _cToken.borrowIndex();

        rewards = (borrowAmount * deltaIndex) / 1e36;
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

    function comptroller() external view returns (address) {
        return address(LOGIC_STORAGE.comptroller());
    }

    function rewardToken() external view override returns (address) {
        return LOGIC_STORAGE.rewardToken();
    }
}
