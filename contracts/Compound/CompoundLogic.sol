// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

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

    struct UsageParams {
        uint256 totalSupplied; // not balance
        uint256 totalBorrowed;
        uint256 slope1;
        uint256 slope2;
        uint256 base;
        uint256 optimalLTV;
        uint256 reserveFactor;
    }

    constructor(
        address _protocolsHandler,
        address _comptroller,
        address _cETH,
        address _compTokenAddress,
        address _rewards
    ) {
        // for testing purpose
        if (_protocolsHandler == address(0)) {
            _protocolsHandler = address(this);
        }
        LOGIC_STORAGE = new CompoundLogicStorage(
            _protocolsHandler,
            _comptroller,
            _cETH,
            _compTokenAddress,
            _rewards
        );
    }

    receive() external payable {}

    function updateSupplyShare(
        address _underlying,
        uint256 _amount
    ) external override {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );

        CompoundLogicStorage.SimulateData memory data = CompoundLogicStorage
            .SimulateData(_amount, getSupplyIndex(_underlying, cToken));

        LOGIC_STORAGE.setLastSimulatedSupply(_underlying, data);

        emit SupplyShareUpdated(_underlying, _amount, abi.encode(data));
    }

    function updateBorrowShare(
        address _underlying,
        uint256 _amount
    ) external override {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );

        (, , , uint256 borrowIndex) = accrueInterest(_underlying, cToken);

        CompoundLogicStorage.SimulateData memory data = CompoundLogicStorage
            .SimulateData(_amount, borrowIndex);

        LOGIC_STORAGE.setLastSimulatedBorrow(_underlying, data);

        emit BorrowShareUpdated(_underlying, _amount, abi.encode(data));
    }

    function lastSupplyInterest(
        address _underlying
    ) external view override returns (uint256) {
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

    function lastBorrowInterest(
        address _underlying
    ) external view override returns (uint256) {
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
            require(
                CERC20Interface(cToken).mint(_amount) == 0,
                "CompoundLogic: compound mint revert"
            );
        }

        addAsset(_underlying);
    }

    function redeem(address _underlying, uint256 _amount) external {
        require(
            CERC20Interface(LOGIC_STORAGE.cTokens(_underlying))
                .redeemUnderlying(_amount) == 0,
            "CompoundLogic: compound redeem underlying revert"
        );
    }

    function borrow(address _underlying, uint256 _amount) external {
        require(
            CERC20Interface(LOGIC_STORAGE.cTokens(_underlying)).borrow(
                _amount
            ) == 0,
            "CompoundLogic: compound borrow reverts"
        );
    }

    function repay(address _underlying, uint256 _amount) external {
        address cToken = LOGIC_STORAGE.cTokens(_underlying);
        if (_underlying == TransferHelper.ETH) {
            CETHInterface(cToken).repayBorrow{value: _amount}();
        } else {
            TransferHelper.approve(_underlying, cToken, _amount);

            require(
                CERC20Interface(cToken).repayBorrow(_amount) == 0,
                "CompoundLogic: compound repay revert"
            );
        }
    }

    // return underlying Token
    // return data for caller
    function supplyOf(
        address _underlying,
        address _account
    ) external view override returns (uint256) {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );
        (
            uint256 totalCash,
            uint256 totalBorrows,
            uint256 totalReserves,

        ) = accrueInterest(_underlying, cToken);

        return
            _supplyOf(
                cToken,
                _account,
                totalCash + totalBorrows - totalReserves
            );
    }

    function _supplyOf(
        CTokenInterface _cToken,
        address _account,
        uint256 _totalSupplies
    ) internal view returns (uint256) {
        uint256 cTokentotalSupply = _cToken.totalSupply();
        uint256 cTokenBalance = _cToken.balanceOf(_account);

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
                ? (_totalSupplies * cTokenBalance) / (cTokentotalSupply)
                : 0;
    }

    function debtOf(
        address _underlying,
        address _account
    ) external view override returns (uint256) {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );
        (, , , uint256 borrowIndex) = accrueInterest(_underlying, cToken);
        return _debtOf(cToken, _account, borrowIndex);
    }

    function _debtOf(
        CTokenInterface _cToken,
        address _account,
        uint256 _borrowIndex
    ) internal view returns (uint256) {
        return
            (_cToken.borrowBalanceStored(_account) * _borrowIndex) /
            _cToken.borrowIndex();
    }

    function totalColletralAndBorrow(
        address _account,
        address _quote
    ) external view returns (uint256 collateralValue, uint256 borrowValue) {
        // For each asset the account is in
        CTokenInterface[] memory userCTokens = LOGIC_STORAGE
            .comptroller()
            .getAssetsIn(_account);
        uint256 length = userCTokens.length;
        IOracle oracle = LOGIC_STORAGE.comptroller().oracle();

        for (uint256 i = 0; i < length; ) {
            CTokenInterface cToken = userCTokens[i];
            uint256 oraclePrice = oracle.getUnderlyingPrice(cToken);
            require(oraclePrice > 0, "Compound Logic: Price Not Found");

            uint256 totalSupplies;
            uint256 borrowIndex;
            {
                uint256 totalCash;
                uint256 totalBorrows;
                uint256 totalReserves;
                (
                    totalCash,
                    totalBorrows,
                    totalReserves,
                    borrowIndex
                ) = accrueInterest(
                    address(cToken) == LOGIC_STORAGE.cTokens(TransferHelper.ETH)
                        ? TransferHelper.ETH
                        : cToken.underlying(),
                    cToken
                );

                totalSupplies = totalCash + totalBorrows - totalReserves;
            }

            collateralValue +=
                _supplyOf(cToken, _account, totalSupplies) *
                oraclePrice;
            borrowValue += _debtOf(cToken, _account, borrowIndex) * oraclePrice;

            unchecked {
                ++i;
            }
        }

        address cQuote = LOGIC_STORAGE.cTokens(_quote);
        uint256 oraclePriceQuote = oracle.getUnderlyingPrice(
            CTokenInterface(cQuote)
        );
        require(oraclePriceQuote > 0, "Compound Logic: Price Not found");

        collateralValue = collateralValue / oraclePriceQuote;
        borrowValue = borrowValue / oraclePriceQuote;
    }

    function supplyToTargetSupplyRate(
        uint256 _targetRate,
        bytes memory _params
    ) external pure override returns (int256) {
        UsageParams memory params = abi.decode(_params, (UsageParams));

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

    function borrowToTargetBorrowRate(
        uint256 _targetRate,
        bytes memory _params
    ) external pure returns (int256) {
        UsageParams memory params = abi.decode(_params, (UsageParams));

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

    function lastSimulatedSupply(
        address _asset
    ) external view returns (CompoundLogicStorage.SimulateData memory) {
        return LOGIC_STORAGE.getLastSimulatedSupply(_asset);
    }

    function lastSimulatedBorrow(
        address _asset
    ) external view returns (CompoundLogicStorage.SimulateData memory) {
        return LOGIC_STORAGE.getLastSimulatedBorrow(_asset);
    }

    function getUsageParams(
        address _underlying,
        uint256 _suppliesToRedeem
    ) external view override returns (bytes memory) {
        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );
        (
            uint256 totalCash,
            uint256 totalBorrows,
            uint256 totalReserves,

        ) = accrueInterest(_underlying, cToken);

        InterestRateModel interestRateModel = cToken.interestRateModel();

        UsageParams memory params = UsageParams(
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

    function claimRewards(
        address _underlying,
        address _account,
        bool _isSupply
    ) external override returns (uint256 newRewards) {
        require(
            msg.sender == LOGIC_STORAGE.rewards(),
            "CompoundLogic: OnlyRewards"
        );

        CTokenInterface cToken = CTokenInterface(
            LOGIC_STORAGE.cTokens(_underlying)
        );

        address[] memory holders = new address[](1);
        holders[0] = _account;
        CTokenInterface[] memory cTokens = new CTokenInterface[](1);
        cTokens[0] = cToken;

        LOGIC_STORAGE.comptroller().claimComp(
            holders,
            cTokens,
            !_isSupply,
            _isSupply
        );

        if (_isSupply) {
            uint256 supplyIndex;
            (newRewards, supplyIndex) = getSupplyReward(
                cToken,
                _account,
                LOGIC_STORAGE.lastSupplyIndexes(address(cToken), _account)
            );

            LOGIC_STORAGE.updateLastSupplyRewards(
                address(cToken),
                _account,
                supplyIndex
            );
        } else {
            uint256 borrowIndex;
            (newRewards, borrowIndex) = getBorrowReward(
                cToken,
                _account,
                LOGIC_STORAGE.lastBorrowIndexes(address(cToken), _account)
            );

            LOGIC_STORAGE.updateLastBorrowRewards(
                address(cToken),
                _account,
                borrowIndex
            );
        }
    }

    function accrueInterest(
        address _underlying,
        CTokenInterface _cToken
    )
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

    function getCurrentSupplyRate(
        address _underlying
    ) external view override returns (uint256) {
        return
            (CTokenInterface(LOGIC_STORAGE.cTokens(_underlying))
                .supplyRatePerBlock() * BLOCK_PER_YEAR) / BASE;
    }

    function getCurrentBorrowRate(
        address _underlying
    ) external view override returns (uint256) {
        return
            (CTokenInterface(LOGIC_STORAGE.cTokens(_underlying))
                .borrowRatePerBlock() * BLOCK_PER_YEAR) / BASE;
    }

    function addAsset(address _underlying) internal {
        address[] memory underlyings = new address[](1);
        underlyings[0] = LOGIC_STORAGE.cTokens(_underlying);
        LOGIC_STORAGE.comptroller().enterMarkets(underlyings);
    }

    function getSupplyReward(
        CTokenInterface _cToken,
        address _account,
        uint256 lastSupplierIndex
    ) internal view returns (uint256 rewards, uint256 supplyIndex) {
        (supplyIndex, ) = LOGIC_STORAGE.comptroller().compSupplyState(
            address(_cToken)
        );

        uint256 deltaIndex = supplyIndex - lastSupplierIndex;
        uint256 supplierTokens = _cToken.balanceOf(_account);
        rewards = (supplierTokens * deltaIndex) / 1e36;
    }

    function getBorrowReward(
        CTokenInterface _cToken,
        address _account,
        uint256 lastBorrowIndex
    ) internal view returns (uint256 rewards, uint256 borrowIndex) {
        (borrowIndex, ) = LOGIC_STORAGE.comptroller().compBorrowState(
            address(_cToken)
        );

        uint256 deltaIndex = borrowIndex - lastBorrowIndex;

        (, , uint256 borrowBalance, ) = _cToken.getAccountSnapshot(_account);
        uint256 borrowAmount = (borrowBalance * 1e18) / _cToken.borrowIndex();

        rewards = (borrowAmount * deltaIndex) / 1e36;
    }

    function getSupplyIndex(
        address _underlying,
        CTokenInterface cToken
    ) public view returns (uint256 supplyIndex) {
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
