// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IReservePool.sol";

import "./libraries/internals/TransferHelper.sol";
import "./libraries/internals/Utils.sol";

// all mutative function is owned by router
contract ReservePool is IReservePool {
    using TransferHelper for address;

    struct PendingRequest {
        address nextAccount;
        uint256 amount;
        bool collateralable;
    }

    IRouter public router;
    uint256 public maxPendingRatio;

    mapping(address => mapping(address => PendingRequest))
        public pendingSupplies;
    mapping(address => mapping(address => address)) public deletedPointer;
    mapping(address => address) public nextAccountsToSupply;
    mapping(address => address) public lastAccountsToSupply;

    mapping(address => uint256) public reserves;
    mapping(address => uint256) public maxReserves;
    mapping(address => uint256) public executeSupplyThresholds;
    mapping(address => uint256) public override lentAmounts;

    constructor(uint256 _maxPendingRatio) {
        maxPendingRatio = _maxPendingRatio;
    }

    function supply(
        Types.UserAssetParams memory _params,
        bool _collateralable,
        bool _executeNow
    ) external override {
        uint256 newReserve = _params.asset.balanceOf(address(this));
        uint256 supplyAmount = newReserve - reserves[_params.asset];

        addToPendingSupplyList(
            _params.asset,
            _params.to,
            supplyAmount,
            _collateralable
        );

        if (_executeNow) {
            _executeSupply(_params.asset, newReserve, Utils.MAX_UINT);
        } else {
            require(
                supplyAmount < executeSupplyThresholds[_params.asset] ||
                    newReserve <= maxReserves[_params.asset],
                "IReservePool: pendingList not allowed"
            );
        }

        reserves[_params.asset] = _params.asset.balanceOf(address(this));
    }

    function redeem(
        Types.UserAssetParams memory _params,
        address _redeemFrom,
        bool _collateralable,
        bool _executeNow
    ) external override {
        PendingRequest memory pendingSupply = pendingSupplies[_params.asset][
            msg.sender
        ];

        uint256 canceledAmount;
        uint256 executionAmount;
        if (pendingSupply.amount > 0) {
            canceledAmount = Utils.minOf(_params.amount, pendingSupply.amount);

            pendingSupplies[_params.asset][msg.sender].amount =
                pendingSupply.amount -
                canceledAmount;

            executionAmount = _params.amount - canceledAmount;
        }

        (
            uint256[] memory supplies,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 newInterest
        ) = router.getSupplyStatus(_params.asset);

        uint256 uncollectedFee;
        (executionAmount, uncollectedFee) = router.recordRedeem(
            Types.UserAssetParams(_params.asset, executionAmount, _params.to),
            protocolsSupplies + totalLending,
            newInterest,
            _redeemFrom,
            _collateralable
        );

        if (_executeNow) {
            canceledAmount = Utils.minOf(
                canceledAmount,
                _params.asset.balanceOf(address(this))
            );

            _params.asset.safeTransfer(_params.to, canceledAmount, 0);
            _params.amount = executionAmount;

            router.executeRedeem(
                _params,
                supplies,
                protocolsSupplies,
                totalLending,
                uncollectedFee
            );
        } else {
            require(
                _params.amount < _params.asset.balanceOf(address(this)),
                "IReservePool: insufficient balance"
            );

            _params.asset.safeTransfer(_params.to, _params.amount, 0);
        }

        reserves[_params.asset] = _params.asset.balanceOf(address(this));
    }

    function borrow(
        Types.UserAssetParams memory _params,
        address _borrowedBy,
        bool _executeNow
    ) external override {
        (
            ,
            uint256 protocolsBorrows,
            uint256 totalLending,
            uint256 lentAmount,
            uint256 newInterest
        ) = router.getBorrowStatus(_params.asset);

        router.recordBorrow(
            _params,
            newInterest,
            protocolsBorrows + totalLending,
            _borrowedBy
        );

        if (_executeNow) {
            router.executeBorrow(_params, totalLending);
        } else {
            require(
                _params.amount < _params.asset.balanceOf(address(this)),
                "IReservePool: insufficient balance"
            );

            lentAmounts[_params.asset] = lentAmount + _params.amount;
            _params.asset.safeTransfer(_params.to, _params.amount, 0);
        }

        reserves[_params.asset] = _params.asset.balanceOf(address(this));
    }

    function repay(
        Types.UserAssetParams memory _params,
        uint256 _totalBorrowed,
        bool _executeNow
    ) external override {
        uint256 newReserve = _params.asset.balanceOf(address(this));
        uint256 repayAmount = newReserve - reserves[_params.asset];

        if (_executeNow) {
            _executeRepay(_params.asset, repayAmount);
        } else {
            require(
                repayAmount < _totalBorrowed * maxPendingRatio,
                "IReservePool: excceed maxPendingRatio"
            );

            require(
                repayAmount < executeSupplyThresholds[_params.asset] ||
                    newReserve <= maxReserves[_params.asset],
                "IReservePool: repayment not allowed"
            );

            uint256 lentAmount = lentAmounts[_params.asset];
            if (lentAmount > _params.amount) {
                lentAmounts[_params.asset] = lentAmount - _params.amount;
            } else {
                lentAmounts[_params.asset] = 0;
            }
        }

        reserves[_params.asset] = _params.asset.balanceOf(address(this));
    }

    function executeSupply(address _asset, uint256 _recordLoops)
        external
        override
    {
        uint256 reserve = reserves[_asset];
        _executeSupply(_asset, reserve, _recordLoops);
        reserves[_asset] = _asset.balanceOf(address(this));
    }

    function _executeRepay(address _asset, uint256 _amount) internal {
        (, uint256 totalLending, , , ) = router.getBorrowStatus(_asset);
        router.executeRepay(_asset, _amount, totalLending);
    }

    function addToPendingSupplyList(
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
                pendingSupplies[_asset][lastAccountToSupply].nextAccount = _to;
            } else {
                nextAccountsToSupply[_asset] = _to;
            }

            lastAccountsToSupply[_asset] = _to;
        }

        pendingSupply.amount += _amount;
        pendingSupply.collateralable = _collateralable;
    }

    function _executeSupply(
        address _asset,
        uint256 _reserve,
        uint256 _recordLoops
    ) internal {
        // record
        (
            uint256[] memory supplies,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 newInterest
        ) = router.getSupplyStatus(_asset);

        (address nextAccount, uint256 totalAmountToSupply) = _recordSupply(
            _asset,
            nextAccountsToSupply[_asset],
            protocolsSupplies + totalLending,
            newInterest,
            _recordLoops
        );

        if (nextAccount == address(0)) {
            lastAccountsToSupply[_asset] = nextAccount;
        }

        nextAccountsToSupply[_asset] = nextAccount;

        // supply
        router.executeSupply(
            _asset,
            Utils.minOf(totalAmountToSupply, _reserve),
            totalLending,
            supplies,
            protocolsSupplies
        );
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

        router.recordSupply(
            _params,
            _totalSupplies,
            _newInterest,
            pendingSupply.collateralable
        );

        (nextAccount, totalRecordedAmount) = _recordSupply(
            _asset,
            pendingSupply.nextAccount,
            _totalSupplies,
            0,
            _loops - 1
        );

        totalRecordedAmount += pendingSupply.amount;
    }
}
