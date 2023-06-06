// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./libraries/internals/TransferHelper.sol";
import "./libraries/internals/Utils.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./storages/ReservePoolStorage.sol";

contract ReservePool is ReservePoolStorage, OwnableUpgradeable {
    using TransferHelper for address;

    receive() external payable {}

    function initialize(uint256 _maxPendingRatio) external initializer {
        __Ownable_init();
        maxPendingRatio = _maxPendingRatio;
    }

    function supply(
        Types.UserAssetParams memory _params,
        bool _collateralable,
        bool _executeNow
    ) external override onlyOwner {
        uint256 newReserve = _params.asset.balanceOf(address(this));
        uint256 supplyAmount = newReserve - reserves[_params.asset];

        _addToPendingSupplyList(
            _params.asset,
            _params.to,
            supplyAmount,
            _collateralable
        );

        if (_executeNow) {
            uint256 pendingRepayAmount = Math.min(
                pendingRepayAmounts[_params.asset],
                newReserve
            );
            uint256 pendingSupplyAmount = newReserve - pendingRepayAmount;

            _executeRepayAndSupply(
                _params.asset,
                Utils.MAX_UINT,
                pendingRepayAmount,
                pendingSupplyAmount
            );
        } else {
            require(
                pendingSupplies[_params.asset][_params.to].amount <=
                    executeSupplyThresholds[_params.asset] ||
                    newReserve <= maxReserves[_params.asset],
                "ReservePool: pending list not allowed"
            );
        }

        reserves[_params.asset] = _params.asset.balanceOf(address(this));
    }

    function redeem(
        Types.UserAssetParams memory _params,
        address _redeemFrom,
        bool _collateralable,
        bool _executeNow
    ) external override onlyOwner {
        PendingRequest memory pendingSupply = pendingSupplies[_params.asset][
            _redeemFrom
        ];

        uint256 canceledAmount;
        if (pendingSupply.amount > 0) {
            canceledAmount = Math.min(_params.amount, pendingSupply.amount);

            pendingSupplies[_params.asset][_redeemFrom].amount =
                pendingSupply.amount -
                canceledAmount;
            _params.amount -= canceledAmount;

            emit PendingListUpdated(
                _params.asset,
                _redeemFrom,
                pendingSupplies[_params.asset][_redeemFrom].amount,
                _collateralable
            );
        }

        uint256 totalSuppliedAmountWithFee;
        uint256 newInterest;
        Types.ExecuteRedeemParams memory executeParams;
        (
            ,
            executeParams.protocolsSupplies,
            executeParams.totalLending,
            totalSuppliedAmountWithFee,
            newInterest
        ) = IRouter(owner()).getSupplyStatus(_params.asset);

        _params.amount = IRouter(owner()).recordRedeem(
            Types.UserAssetParams(_params.asset, _params.amount, _params.to),
            totalSuppliedAmountWithFee,
            newInterest,
            _redeemFrom,
            _collateralable
        );

        if (_executeNow) {
            canceledAmount = Math.min(
                canceledAmount,
                _params.asset.balanceOf(address(this))
            );

            _params.asset.safeTransfer(_params.to, canceledAmount, 0);
            executeParams.userParams = _params;
            IRouter(owner()).executeRedeem(executeParams);
        } else {
            require(
                _params.amount + canceledAmount <=
                    _params.asset.balanceOf(address(this)),
                "ReservePool: insufficient balance"
            );

            _params.asset.safeTransfer(
                _params.to,
                _params.amount + canceledAmount,
                0
            );

            redeemedAmounts[_params.asset] += _params.amount;
        }

        reserves[_params.asset] = _params.asset.balanceOf(address(this));
    }

    function borrow(
        Types.UserAssetParams memory _params,
        bool _executeNow
    ) external override onlyOwner {
        if (_executeNow) {
            IRouter(owner()).executeBorrow(_params);
        } else {
            require(
                _params.amount <= _params.asset.balanceOf(address(this)),
                "ReservePool: insufficient balance"
            );

            lentAmounts[_params.asset] += _params.amount;
            _params.asset.safeTransfer(_params.to, _params.amount, 0);
        }

        reserves[_params.asset] = _params.asset.balanceOf(address(this));
    }

    function repay(
        Types.UserAssetParams memory _params,
        uint256 _totalBorrowed,
        bool _executeNow
    ) external override onlyOwner {
        uint256 newReserve = _params.asset.balanceOf(address(this));
        uint256 repayAmount = newReserve - reserves[_params.asset];

        pendingRepayAmounts[_params.asset] += _params.amount;
        if (_executeNow) {
            uint256 pendingRepayAmount = Math.min(
                pendingRepayAmounts[_params.asset],
                newReserve
            );
            uint256 pendingSupplyAmount = newReserve - pendingRepayAmount;

            _executeRepayAndSupply(
                _params.asset,
                Utils.MAX_UINT,
                pendingRepayAmount,
                pendingSupplyAmount
            );
        } else {
            require(
                repayAmount <
                    (_totalBorrowed * maxPendingRatio) / Utils.MILLION,
                "ReservePool: excceed max pending ratio"
            );

            require(
                repayAmount <= executeSupplyThresholds[_params.asset] ||
                    newReserve <= maxReserves[_params.asset],
                "ReservePool: max reserve excceeded"
            );
        }

        reserves[_params.asset] = _params.asset.balanceOf(address(this));
    }

    function executeRepayAndSupply(
        address _asset,
        uint256 _recordLoops
    ) external override {
        uint256 reserve = reserves[_asset];
        uint256 pendingRepayAmount = Math.min(
            pendingRepayAmounts[_asset],
            reserve
        );
        uint256 pendingSupplyAmount = reserve - pendingRepayAmount;

        _executeRepayAndSupply(
            _asset,
            _recordLoops,
            pendingRepayAmount,
            pendingSupplyAmount
        );

        reserves[_asset] = _asset.balanceOf(address(this));
    }

    function _executeRepayAndSupply(
        address _asset,
        uint256 _recordLoops,
        uint256 pendingRepayAmount,
        uint256 pendingSupplyAmount
    ) internal {
        if (pendingRepayAmount > 0) {
            _executeRepay(_asset, pendingRepayAmount);
        }

        if (pendingSupplyAmount > 0) {
            _executeSupply(_asset, pendingSupplyAmount, _recordLoops);
        }
    }

    function _addToPendingSupplyList(
        address _asset,
        address _to,
        uint256 _amount,
        bool _collateralable
    ) internal {
        PendingRequest memory pendingSupply = pendingSupplies[_asset][_to];
        address lastAccountToSupply = lastAccountsToSupply[_asset];

        // account not requested yet
        if (
            pendingSupply.nextAccount == address(0) &&
            lastAccountToSupply != _to
        ) {
            if (lastAccountToSupply == address(0)) {
                nextAccountsToSupply[_asset] = _to;
            } else {
                pendingSupplies[_asset][lastAccountToSupply].nextAccount = _to;
            }

            lastAccountsToSupply[_asset] = _to;
        }

        pendingSupplies[_asset][_to].amount += _amount;
        pendingSupplyAmounts[_asset] += _amount;

        emit PendingListUpdated(
            _asset,
            _to,
            pendingSupplies[_asset][_to].amount,
            _collateralable
        );
    }

    // Requests on pending list are not exepcted to be reverted.
    function _executeSupply(
        address _asset,
        uint256 _pendingSupplyAmount,
        uint256 _recordLoops
    ) internal {
        IRouter router = IRouter(owner());
        // record
        (
            ,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 totalSuppliedAmountWithFee,
            uint256 newInterest
        ) = router.getSupplyStatus(_asset);

        (address nextAccount, uint256 totalAmountToSupply) = _recordSupply(
            _asset,
            nextAccountsToSupply[_asset],
            totalSuppliedAmountWithFee,
            newInterest,
            _recordLoops
        );

        if (nextAccount == address(0)) {
            lastAccountsToSupply[_asset] = nextAccount;
        }

        nextAccountsToSupply[_asset] = nextAccount;

        uint256 redeemedAmount = redeemedAmounts[_asset];
        redeemedAmounts[_asset] = redeemedAmount > totalAmountToSupply
            ? redeemedAmount - totalAmountToSupply
            : 0;

        // supply
        totalAmountToSupply = Math.min(
            totalAmountToSupply,
            _pendingSupplyAmount
        );
        pendingSupplyAmounts[_asset] -= totalAmountToSupply;

        _asset.safeTransfer(
            address(router.protocols()),
            totalAmountToSupply,
            0
        );

        router.executeSupply(
            Types.ExecuteSupplyParams(
                _asset,
                totalAmountToSupply,
                totalLending,
                protocolsSupplies
            )
        );
    }

    function _executeRepay(address _asset, uint256 _amount) internal {
        IRouter router = IRouter(owner());

        uint256 lentAmount = lentAmounts[_asset];
        lentAmounts[_asset] = lentAmount > _amount ? lentAmount - _amount : 0;
        pendingRepayAmounts[_asset] -= _amount;

        if (_asset != TransferHelper.ETH) {
            IERC20(_asset).approve(address(router), _amount);
        } else {
            TransferHelper.transferETH(address(router), _amount, 0);
        }
        router.executeRepay(_asset, _amount);
    }

    function _recordSupply(
        address _asset,
        address _account,
        uint256 _totalSupplies,
        uint256 _newInterest,
        uint256 _loops
    ) internal returns (address nextAccount, uint256 totalRecordedAmount) {
        if (_loops == 0 || _account == address(0)) {
            nextAccount = _account;
            return (nextAccount, totalRecordedAmount);
        }

        PendingRequest memory pendingSupply = pendingSupplies[_asset][_account];
        delete pendingSupplies[_asset][_account];

        Types.UserAssetParams memory _params = Types.UserAssetParams(
            _asset,
            pendingSupply.amount,
            _account
        );

        IRouter(owner()).recordSupply(_params, _totalSupplies, _newInterest);

        (nextAccount, totalRecordedAmount) = _recordSupply(
            _asset,
            pendingSupply.nextAccount,
            _totalSupplies + pendingSupply.amount,
            0,
            _loops - 1
        );

        totalRecordedAmount += pendingSupply.amount;

        emit SupplyExecuted(_account);
    }

    function setConfig(
        address _asset,
        uint256 _maxReserve,
        uint256 _executeSupplyThreshold
    ) external override onlyOwner {
        maxReserves[_asset] = _maxReserve;
        executeSupplyThresholds[_asset] = _executeSupplyThreshold;
    }

    function setMaxPendingRatio(
        uint256 _maxPendingRatio
    ) external override onlyOwner {
        maxPendingRatio = _maxPendingRatio;
    }
}
