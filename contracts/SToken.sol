// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./interfaces/IRewards.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/ISToken.sol";
import "./interfaces/IConfig.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

// Supply Token
// owner is router
contract SToken is ISToken, OwnableUpgradeable, ERC20Upgradeable {
    using Math for uint256;
    address public override underlying;
    IRewards public rewards;

    function initialize(
        address _underlying,
        address _rewards,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __Ownable_init();
        __ERC20_init(_name, _symbol);

        underlying = _underlying;
        rewards = IRewards(_rewards);
    }

    function mint(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyOwner returns (uint256 amount) {
        amount = unscaledAmount(_amountOfUnderlying, _totalUnderlying);
        _mint(_account, amount);
    }

    function burn(
        address _from,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyOwner returns (uint256 amountOfUnderlying) {
        amountOfUnderlying = Math.min(
            _amountOfUnderlying,
            scaledAmount(balanceOf(_from), _totalUnderlying)
        );
        uint256 amount = unscaledAmount(amountOfUnderlying, _totalUnderlying);
        amountOfUnderlying = scaledAmount(amount, _totalUnderlying);

        _burn(_from, amount);
    }

    function claimRewards(
        address _account
    ) external override onlyOwner returns (uint256) {
        return
            rewards.claimRewards(
                underlying,
                false,
                _account,
                balanceOf(_account),
                totalSupply()
            );
    }

    function decimals() public view override returns (uint8) {
        IConfig config = IRouter(owner()).config();
        uint8 decimal = config.assetConfigs(underlying).decimals;
        return decimal;
    }

    function scaledAmount(
        uint256 _amount,
        uint256 _totalSupplied
    ) public view override returns (uint256) {
        uint256 totalSupply = totalSupply();
        return
            totalSupply > 0
                ? (_amount * _totalSupplied) / totalSupply
                : _amount;
    }

    function unscaledAmount(
        uint256 _amount,
        uint256 _totalSupplied
    ) public view override returns (uint256) {
        uint256 totalSupply = totalSupply();
        return
            _totalSupplied > 0
                ? (_amount * totalSupply).ceilDiv(_totalSupplied)
                : _amount;
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override {
        if (_from != address(0)) {
            rewards.updateRewardShare(
                underlying,
                false,
                _from,
                balanceOf(_from),
                balanceOf(_from) - _amount,
                totalSupply()
            );
        }

        if (_to != address(0)) {
            rewards.updateRewardShare(
                underlying,
                false,
                _to,
                balanceOf(_to),
                balanceOf(_to) + _amount,
                totalSupply()
            );
        }
    }

    function _afterTokenTransfer(
        address _from,
        address,
        uint256
    ) internal view override {
        if (msg.sender != owner()) {
            _validatePosition(_from);
        }
    }

    function _validatePosition(address _from) internal view {
        if (IRouter(owner()).isUsingAsCollateral(underlying, _from)) {
            (bool isHealthy, , ) = IRouter(owner()).isPoisitionHealthy(
                underlying,
                _from
            );
            require(isHealthy, "SToken: insufficient collateral");
        }
    }

    // helpers
    function scaledAmountCurrent(
        uint256 _amount
    ) external view override returns (uint256) {
        return scaledAmount(_amount, scaledTotalSupply());
    }

    function unscaledAmountCurrent(
        uint256 _amount
    ) external view override returns (uint256) {
        return unscaledAmount(_amount, scaledTotalSupply());
    }

    function scaledBalanceOf(
        address _account
    ) external view override returns (uint256) {
        return scaledAmount(balanceOf(_account), scaledTotalSupply());
    }

    function scaledTotalSupply() public view override returns (uint256 amount) {
        return IRouter(owner()).totalSupplied(underlying);
    }

    function exchangeRate()
        external
        view
        override
        returns (uint256 numerator, uint256 denominator)
    {
        return (totalSupply(), scaledTotalSupply());
    }
}
