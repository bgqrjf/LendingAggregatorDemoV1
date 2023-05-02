// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./storages/DTokenStorage.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IRewards.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./libraries/internals/Utils.sol";

// DebtToken
contract DToken is DTokenSotrage, OwnableUpgradeable {
    using Math for uint256;
    IRewards public rewards;

    function initialize(
        address _underlying,
        address _rewards,
        string memory _name,
        string memory _symbol,
        uint256 _feeRate
    ) external initializer {
        __Ownable_init();

        underlying = _underlying;
        name = _name;
        symbol = _symbol;
        feeRate = _feeRate;
        rewards = IRewards(_rewards);
    }

    function mint(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying,
        uint256 _newInterest
    ) external override onlyOwner returns (uint256 amount) {
        amount = unscaledAmount(_amountOfUnderlying, _totalUnderlying);
        _mint(_account, amount, _newInterest);
    }

    function burn(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying,
        uint256 _newInterest
    )
        external
        override
        onlyOwner
        returns (uint256 amountOfUnderlying, uint256 newCollectedFee)
    {
        amountOfUnderlying = Math.min(
            _amountOfUnderlying,
            scaledAmount(balanceOf[_account], _totalUnderlying)
        );
        uint256 amount = unscaledAmount(amountOfUnderlying, _totalUnderlying);

        return (
            scaledAmount(amount, _totalUnderlying),
            _burn(_account, amount, _newInterest)
        );
    }

    function claimRewards(
        address _account
    ) external override onlyOwner returns (uint256) {
        return
            rewards.claimRewards(
                underlying,
                true,
                _account,
                balanceOf[_account],
                totalSupply
            );
    }

    function updateNewFee(
        uint256 _newInterest
    ) external override onlyOwner returns (uint256 uncollectedFee) {
        _updateNewFee(_newInterest);
        return accFee - collectedFee;
    }

    function scaledDebtOf(
        address _account
    ) public view override returns (uint256) {
        return
            scaledAmount(
                balanceOf[_account],
                IRouter(owner()).totalBorrowed(underlying)
            );
    }

    function scaledAmount(
        uint256 _amount,
        uint256 _totalBorrowed
    ) public view override returns (uint256) {
        return
            totalSupply > 0
                ? (_amount * _totalBorrowed) / (totalSupply)
                : _amount;
    }

    function unscaledAmount(
        uint256 _amount,
        uint256 _totalBorrowed
    ) internal view returns (uint256) {
        return
            _totalBorrowed > 0
                ? (_amount * totalSupply).ceilDiv(_totalBorrowed)
                : _amount;
    }

    function totalDebt() public view override returns (uint256 amount) {
        return IRouter(owner()).totalBorrowed(underlying);
    }

    function calculateFee(
        uint256 _newInterest
    ) public view override returns (uint256 newAccFee, uint256 newFeeIndex) {
        uint256 newFee = (_newInterest * feeRate) / Utils.MILLION;
        newAccFee = accFee + newFee;
        newFeeIndex = totalSupply > 0
            ? feeIndex + (newFee * Utils.QUINTILLION) / totalSupply
            : 0;
    }

    function _mint(
        address _account,
        uint256 _amount,
        uint256 _newInterest
    ) internal {
        require(_account != address(0), "ERC20: mint to the zero address");

        _updateNewFee(_newInterest);

        uint256 balance = balanceOf[_account];
        uint256 newBalance = balance + _amount;

        uint256 userFeeIndex = (feeIndexOf[_account] *
            balance +
            feeIndex *
            _amount) / (balance + _amount);
        feeIndexOf[_account] = userFeeIndex;
        emit UserFeeIndexUpdated(_account, userFeeIndex);

        rewards.updateRewardShare(
            underlying,
            true,
            _account,
            balance,
            newBalance,
            totalSupply
        );
        balanceOf[_account] = newBalance;
        totalSupply += _amount;

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(
        address _account,
        uint256 _amount,
        uint256 _newInterest
    ) internal returns (uint256 newCollectedFee) {
        require(_account != address(0), "ERC20: burn from the zero address");
        _updateNewFee(_newInterest);

        uint256 balance = balanceOf[_account];
        uint256 newBalance = balance - _amount;
        rewards.updateRewardShare(
            underlying,
            true,
            _account,
            balance,
            newBalance,
            totalSupply
        );

        balanceOf[_account] = newBalance;
        totalSupply -= _amount;
        emit Transfer(_account, address(0), _amount);

        newCollectedFee =
            ((feeIndex - feeIndexOf[_account]) * _amount) /
            Utils.QUINTILLION;
        collectedFee += newCollectedFee;
        emit CollectedFeeUpdated(collectedFee);
    }

    function _updateNewFee(uint256 _newInterest) internal {
        if (_newInterest > 0) {
            (accFee, feeIndex) = calculateFee(_newInterest);
            emit AccFeeUpdated(accFee, feeIndex);
        }
    }
}
