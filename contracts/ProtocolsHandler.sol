// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProtocolsHandler.sol";

import "./libraries/internals/TransferHelper.sol";
import "./libraries/internals/Utils.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract ProtocolsHandler is IProtocolsHandler, OwnableUpgradeable {
    using TransferHelper for address;

    IStrategy public strategy;
    IProtocol[] public protocols;
    bool public autoRebalance;

    receive() external payable {}

    function initialize(
        address[] memory _protocols,
        address _strategy,
        bool _autoRebalance
    ) external initializer {
        __Ownable_init();

        protocols = new IProtocol[](_protocols.length);
        for (uint256 i = 0; i < _protocols.length; ++i) {
            protocols[i] = IProtocol(_protocols[i]);
        }
        strategy = IStrategy(_strategy);
        autoRebalance = _autoRebalance;
    }

    function rebalanceAllProtocols(address _asset) public override {
        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;

        (
            uint256[] memory redeemAmounts,
            uint256[] memory supplyAmounts
        ) = strategy.getRebalanceStrategy(protocolsCache, _asset);

        for (uint256 i = 0; i < length; ) {
            if (redeemAmounts[i] > 0) {
                Utils.delegateCall(
                    address(protocolsCache[i]),
                    abi.encodeWithSelector(
                        protocolsCache[i].redeem.selector,
                        _asset,
                        redeemAmounts[i]
                    )
                );
            }
            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < length; ) {
            if (supplyAmounts[i] > 0) {
                Utils.delegateCall(
                    address(protocolsCache[i]),
                    abi.encodeWithSelector(
                        protocolsCache[i].supply.selector,
                        _asset,
                        supplyAmounts[i]
                    )
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    function repayAndSupply(
        address _asset,
        uint256 _amount,
        uint256 _totalSupplied
    )
        external
        override
        onlyOwner
        returns (uint256 repayAmount, uint256 supplyAmount)
    {
        repayAmount = repay(_asset, _amount);

        if (repayAmount < _amount) {
            supplyAmount = _amount - repayAmount;
            supply(_asset, supplyAmount, _totalSupplied);
        }

        if (autoRebalance) {
            rebalanceAllProtocols(_asset);
        }
    }

    function redeemAndBorrow(
        address _asset,
        uint256 _amount,
        uint256 _totalSupplied,
        address _to
    )
        external
        override
        onlyOwner
        returns (uint256 redeemAmount, uint256 borrowAmount)
    {
        redeemAmount = redeem(_asset, _amount, _totalSupplied, _to);

        if (redeemAmount < _amount) {
            borrowAmount = _amount - redeemAmount;
            borrow(_asset, borrowAmount, _to);
        }

        if (autoRebalance) {
            rebalanceAllProtocols(_asset);
        }
    }

    function getProtocols() public view override returns (IProtocol[] memory) {
        return protocols;
    }

    function totalSupplied(
        address asset
    )
        public
        view
        override
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;
        amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ) {
            amounts[i] = protocolsCache[i].supplyOf(asset, address(this));
            totalAmount = totalAmount + amounts[i];

            unchecked {
                ++i;
            }
        }
    }

    function totalBorrowed(
        address asset
    )
        public
        view
        override
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;
        amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ) {
            amounts[i] = protocolsCache[i].debtOf(asset, address(this));
            totalAmount = totalAmount + amounts[i];

            unchecked {
                ++i;
            }
        }
    }

    function simulateLendings(
        address _asset,
        uint256 _totalLending
    ) public view override returns (uint256 totalLending, uint256 newInterest) {
        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;
        uint256 supplyInterest;
        uint256 borrowInterest;

        for (uint256 i = 0; i < length; ) {
            supplyInterest += protocolsCache[i].lastSupplyInterest(_asset);
            borrowInterest += protocolsCache[i].lastBorrowInterest(_asset);
            unchecked {
                ++i;
            }
        }

        uint256 interestDelta = borrowInterest > supplyInterest
            ? borrowInterest - supplyInterest
            : 0;

        (, uint256 borrowed) = totalBorrowed(_asset);
        (, uint256 supplied) = totalSupplied(_asset);

        // solve equation for totalLending
        // totalLending =
        //     _totalLending +
        //     supplyInterest +
        //     (interestDelta * (borrowed + totalLending)) /
        //     (supplied + totalLending);

        uint256 c = supplied *
            (_totalLending + supplyInterest) +
            interestDelta *
            borrowed;

        uint256 b = _totalLending + supplyInterest + interestDelta;
        if (b > supplied) {
            b = b - supplied;
            totalLending = (Math.sqrt(4 * c + b * b) + b) / 2;
        } else {
            b = supplied - b;
            totalLending = (Math.sqrt(4 * c + b * b) - b) / 2;
        }

        newInterest = totalLending - _totalLending;
    }

    function getRates(
        address _underlying
    ) external view override returns (uint256 supplyRate, uint256 borrowRate) {
        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;

        uint256 supplyWeight;
        uint256 borrowWeight;
        for (uint256 i = 0; i < length; ) {
            uint256 protocolSupplyRate = protocolsCache[i].getCurrentSupplyRate(
                _underlying
            );

            uint256 protocolSupplyAmount = protocolsCache[i].supplyOf(
                _underlying,
                address(this)
            );

            uint256 newSupplyWeight = supplyWeight + protocolSupplyAmount;

            if (newSupplyWeight > 0) {
                supplyRate =
                    (supplyRate *
                        supplyWeight +
                        protocolSupplyRate *
                        protocolSupplyAmount) /
                    newSupplyWeight;
                supplyWeight = newSupplyWeight;
            } else {
                supplyRate = Math.max(supplyRate, protocolSupplyRate);
            }

            uint256 protocolBorrowRate = protocolsCache[i].getCurrentBorrowRate(
                _underlying
            );

            uint256 protocolBorrowAmount = protocolsCache[i].debtOf(
                _underlying,
                address(this)
            );

            uint256 newBorrowWeight = borrowWeight + protocolBorrowAmount;
            if (newBorrowWeight > 0) {
                borrowRate =
                    (borrowRate *
                        borrowWeight +
                        protocolBorrowRate *
                        protocolBorrowAmount) /
                    newBorrowWeight;

                borrowWeight = newBorrowWeight;
            } else {
                borrowRate = borrowRate > 0
                    ? Math.min(borrowRate, protocolBorrowRate)
                    : protocolBorrowRate;
            }

            unchecked {
                ++i;
            }
        }
    }

    function updateSimulates(
        address _asset,
        uint256 _totalLending
    ) external override onlyOwner {
        IProtocol[] memory protocolsCache = protocols;
        uint256[] memory supplyAmounts = strategy.getSimulateSupplyStrategy(
            protocolsCache,
            _asset,
            _totalLending
        );

        uint256[] memory borrowAmounts = strategy.getSimulateBorrowStrategy(
            protocolsCache,
            _asset,
            _totalLending
        );

        uint256 length = protocolsCache.length;
        for (uint256 i = 0; i < length; ) {
            Utils.delegateCall(
                address(protocolsCache[i]),
                abi.encodeWithSelector(
                    protocolsCache[i].updateSupplyShare.selector,
                    _asset,
                    supplyAmounts[i]
                )
            );

            Utils.delegateCall(
                address(protocolsCache[i]),
                abi.encodeWithSelector(
                    protocolsCache[i].updateBorrowShare.selector,
                    _asset,
                    borrowAmounts[i]
                )
            );

            unchecked {
                ++i;
            }
        }
    }

    function supply(address _asset, uint256 _amount, uint256) internal {
        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;

        uint256[] memory supplyAmounts = strategy.getSupplyStrategy(
            protocolsCache,
            _asset,
            _amount
        );

        for (uint256 i = 0; i < length; ) {
            if (supplyAmounts[i] > 0) {
                Utils.delegateCall(
                    address(protocolsCache[i]),
                    abi.encodeWithSelector(
                        protocolsCache[i].supply.selector,
                        _asset,
                        supplyAmounts[i]
                    )
                );
            }

            unchecked {
                ++i;
            }
        }
        emit Supplied(_asset, _amount);
    }

    function redeem(
        address _asset,
        uint256 _amount,
        uint256 _totalSupplied,
        address _to
    ) internal returns (uint256 amount) {
        amount = Math.min(_amount, _totalSupplied);

        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;

        uint256[] memory redeemAmounts = strategy.getRedeemStrategy(
            protocolsCache,
            _asset,
            amount
        );

        for (uint256 i = 0; i < length; ) {
            if (redeemAmounts[i] > 0) {
                Utils.delegateCall(
                    address(protocolsCache[i]),
                    abi.encodeWithSelector(
                        protocolsCache[i].redeem.selector,
                        _asset,
                        redeemAmounts[i]
                    )
                );
            }
            unchecked {
                ++i;
            }
        }

        _asset.safeTransfer(_to, amount, 0);
        emit Redeemed(_asset, amount);

        return amount;
    }

    function borrow(
        address _asset,
        uint256 _amount,
        address _to
    ) internal returns (uint256 amount) {
        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;

        uint256[] memory amounts = strategy.getBorrowStrategy(
            protocolsCache,
            _asset,
            _amount
        );

        for (uint256 i = 0; i < length; ) {
            if (amounts[i] > 0) {
                Utils.delegateCall(
                    address(protocolsCache[i]),
                    abi.encodeWithSelector(
                        protocolsCache[i].borrow.selector,
                        _asset,
                        amounts[i]
                    )
                );
            }
            unchecked {
                ++i;
            }
        }

        _asset.safeTransfer(_to, _amount, 0);
        emit Borrowed(_asset, _amount);

        return _amount;
    }

    function repay(address _asset, uint256 _amount) internal returns (uint256) {
        (, uint256 total) = totalBorrowed(_asset);
        uint256 amount = Math.min(_amount, total);
        if (amount == 0) {
            return amount;
        }

        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;

        uint256[] memory amounts = strategy.getRepayStrategy(
            protocolsCache,
            _asset,
            _amount
        );

        for (uint256 i = 0; i < length; ) {
            if (amounts[i] > 0) {
                Utils.delegateCall(
                    address(protocolsCache[i]),
                    abi.encodeWithSelector(
                        protocolsCache[i].repay.selector,
                        _asset,
                        amounts[i]
                    )
                );
            }
            unchecked {
                ++i;
            }
        }

        emit Repaid(_asset, _amount);
        return _amount;
    }

    function addProtocol(IProtocol _protocol) external override onlyOwner {
        protocols.push(_protocol);
    }

    function updateProtocol(
        IProtocol _old,
        IProtocol _new
    ) external override onlyOwner {
        IProtocol[] memory protocolsCache = protocols;
        uint256 length = protocolsCache.length;

        for (uint256 i = 0; i < length; ) {
            if (_old == protocolsCache[i]) {
                protocols[i] = _new;
                break;
            }

            unchecked {
                ++i;
            }
        }
    }

    function toggleAutoRebalance() external override onlyOwner {
        autoRebalance = !autoRebalance;
        emit AutoRebalanceToggled(autoRebalance);
    }

    function distributeRewards(
        address _rewardToken,
        address _account,
        uint256 _amount
    ) external override onlyOwner {
        _rewardToken.safeTransfer(_account, _amount, 0);
    }
}
