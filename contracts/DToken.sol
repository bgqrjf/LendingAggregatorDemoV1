// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IDToken.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./libraries/internals/Utils.sol";

// DebtToken
contract DToken is IDToken, OwnableUpgradeable {
    using Math for uint256;

    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    address public override underlying;
    uint256 public feeRate;
    uint256 public accFee;
    uint256 public override collectedFee;
    uint256 public feeIndex;

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public feeIndexOf;

    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __Ownable_init();

        underlying = _underlying;
        name = _name;
        symbol = _symbol;
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
                : 0;
    }

    function totalDebt() public view override returns (uint256 amount) {
        return IRouter(owner()).totalBorrowed(underlying);
    }

    function calculateFee(
        uint256 _newInterest
    ) public view override returns (uint newAccFee, uint256 newFeeIndex) {
        uint newFee = (_newInterest * feeRate) / Utils.MILLION;
        newAccFee = accFee + newFee;
        newFeeIndex = feeIndex + (newFee * Utils.QUINTILLION) / totalSupply;
    }

    function _mint(
        address _account,
        uint256 _amount,
        uint256 _newInterest
    ) internal {
        require(_account != address(0), "ERC20: mint to the zero address");
        totalSupply += _amount;
        balanceOf[_account] += _amount;

        _updateNewFee(_newInterest);
        feeIndexOf[_account] =
            (feeIndexOf[_account] * balanceOf[_account] + feeIndex * _amount) /
            (balanceOf[_account] + _amount);
        // emit UpdateUserFeeIndexOf

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(
        address _account,
        uint256 _amount,
        uint256 _newInterest
    ) internal returns (uint256 newCollectedFee) {
        require(_account != address(0), "ERC20: burn from the zero address");
        balanceOf[_account] -= _amount;
        totalSupply -= _amount;
        emit Transfer(_account, address(0), _amount);

        _updateNewFee(_newInterest);
        newCollectedFee =
            ((feeIndex - feeIndexOf[_account]) * _amount) /
            Utils.QUINTILLION;
        collectedFee += newCollectedFee;
    }

    function _updateNewFee(uint256 _newInterest) internal {
        if (_newInterest > 0) {
            (accFee, feeIndex) = calculateFee(_newInterest);
            emit AccFeeUpdated(accFee, feeIndex);
        }
    }
}
