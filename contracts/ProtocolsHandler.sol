// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProtocolsHandler.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/Utils.sol";
import "./libraries/Math.sol";

contract ProtocolsHandler is IProtocolsHandler, OwnableUpgradeable {
    address public router;
    IStrategy public strategy;
    IProtocol[] public protocols;

    modifier onlyRouter() {
        require(msg.sender == router, "ProtocolsHandler: OnlyRouter");
        _;
    }

    function initialize(address[] memory _protocols, address _strategy)
        external
        initializer
    {
        __Ownable_init();

        protocols = new IProtocol[](_protocols.length);
        for (uint256 i = 0; i < _protocols.length; i++) {
            protocols[i] = IProtocol(_protocols[i]);
        }
        strategy = IStrategy(_strategy);
    }

    receive() external payable {}

    function redeemAndSupply(
        address _asset,
        uint256[] memory supplies,
        uint256 _totalSupplied
    )
        internal
        returns (uint256[] memory supplyAmounts, uint256[] memory redeemAmounts)
    {
        IProtocol[] memory protocolsCache = protocols;
        (supplyAmounts, redeemAmounts) = strategy.getSupplyStrategy(
            protocolsCache,
            _asset,
            supplies,
            _totalSupplied
        );

        for (uint256 i = 0; i < protocolsCache.length; i++) {
            if (redeemAmounts[i] > 0) {
                _redeem(protocolsCache[i], _asset, redeemAmounts[i]);
            }
        }

        for (uint256 i = 0; i < protocolsCache.length; i++) {
            if (supplyAmounts[i] > 0) {
                _supply(protocolsCache[i], _asset, supplyAmounts[i]);
            }
        }
    }

    function supply(
        address _asset,
        uint256 _amount,
        uint256[] memory supplies,
        uint256 _totalSupplied
    ) public onlyRouter returns (uint256) {
        uint256 balanceBefore = TransferHelper.balanceOf(_asset, address(this));
        redeemAndSupply(_asset, supplies, _totalSupplied + _amount);
        uint256 balanceAfter = TransferHelper.balanceOf(_asset, address(this));

        emit Supplied(_asset, balanceBefore - balanceAfter);
        return _amount;
    }

    function redeem(
        address _asset,
        uint256 _amount,
        uint256[] memory supplies,
        uint256 _totalSupplied,
        address _to
    ) public onlyRouter returns (uint256) {
        if (_amount > _totalSupplied) {
            _amount = _totalSupplied;
        }

        if (_amount > 0) {
            redeemAndSupply(_asset, supplies, _totalSupplied - _amount);

            TransferHelper.safeTransfer(_asset, _to, _amount, 0);
            emit Redeemed(_asset, _amount);
            return _amount;
        }

        return 0;
    }

    function borrow(Types.UserAssetParams memory _params)
        public
        onlyRouter
        returns (uint256 amount)
    {
        IProtocol[] memory protocolsCache = protocols;
        uint256[] memory amounts = strategy.getBorrowStrategy(
            protocolsCache,
            _params.asset,
            _params.amount
        );

        for (uint256 i = 0; i < protocolsCache.length; i++) {
            if (amounts[i] > 0) {
                Types.ProtocolData memory data = protocolsCache[i]
                    .getBorrowData(_params.asset, amounts[i]);
                Utils.lowLevelCall(data.target, data.encodedData, 0);
                if (data.weth != address(0)) {
                    IWETH(data.weth).withdraw(amounts[i]);
                }
            }
        }

        TransferHelper.safeTransfer(
            _params.asset,
            _params.to,
            _params.amount,
            0
        );

        emit Borrowed(_params.asset, _params.amount);

        return _params.amount;
    }

    function repay(Types.UserAssetParams memory _params)
        public
        onlyRouter
        returns (uint256 amount)
    {
        (, uint256 total) = totalBorrowed(_params.asset);
        _params.amount = Utils.minOf(_params.amount, total);

        if (_params.amount > 0) {
            IProtocol[] memory protocolsCache = protocols;
            uint256[] memory amounts = strategy.getRepayStrategy(
                protocolsCache,
                _params.asset,
                _params.amount
            );

            for (uint256 i = 0; i < protocolsCache.length; i++) {
                if (amounts[i] > 0) {
                    Types.ProtocolData memory data = protocolsCache[i]
                        .getRepayData(_params.asset, amounts[i]);

                    if (data.approveTo == address(0)) {
                        Utils.lowLevelCall(
                            data.target,
                            data.encodedData,
                            amounts[i]
                        );
                    } else {
                        if (data.weth != address(0)) {
                            IWETH(data.weth).deposit{value: amounts[i]}();
                            TransferHelper.approve(
                                data.weth,
                                data.approveTo,
                                amounts[i]
                            );
                        } else {
                            TransferHelper.approve(
                                _params.asset,
                                data.approveTo,
                                amounts[i]
                            );
                        }

                        Utils.lowLevelCall(data.target, data.encodedData, 0);
                    }
                }
            }

            emit Repayed(_params.asset, _params.amount);
        }

        return _params.amount;
    }

    function getProtocols() public view override returns (IProtocol[] memory) {
        return protocols;
    }

    function totalSupplied(address asset)
        public
        view
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        IProtocol[] memory protocolsCache = protocols;
        amounts = new uint256[](protocolsCache.length);
        for (uint256 i = 0; i < protocolsCache.length; i++) {
            amounts[i] = protocolsCache[i].supplyOf(asset, address(this));
            totalAmount += amounts[i];
        }
    }

    function totalBorrowed(address asset)
        public
        view
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        IProtocol[] memory protocolsCache = protocols;
        amounts = new uint256[](protocolsCache.length);
        for (uint256 i = 0; i < protocolsCache.length; i++) {
            amounts[i] = protocolsCache[i].debtOf(asset, address(this));
            totalAmount += amounts[i];
        }
    }

    function simulateLendings(address _asset, uint256 _totalLending)
        public
        view
        override
        returns (uint256 totalLending, uint256 newInterest)
    {
        IProtocol[] memory protocolsCache = protocols;
        uint256 supplyInterest;
        uint256 borrowInterest;

        for (uint256 i = 0; i < protocolsCache.length; i++) {
            supplyInterest += protocolsCache[i].lastSupplyInterest(
                _asset,
                address(this)
            );

            borrowInterest += protocolsCache[i].lastBorrowInterest(
                _asset,
                address(this)
            );
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
            b -= supplied;
            totalLending = (Math.sqrt(4 * c + b * b) + b) / 2;
        } else {
            b = supplied - b;
            totalLending = (Math.sqrt(4 * c + b * b) - b) / 2;
        }

        newInterest = totalLending - _totalLending;
    }

    function simulateSupply(address _asset, uint256 _totalLending)
        external
        onlyRouter
    {
        IProtocol[] memory protocolsCache = protocols;
        uint256[] memory supplyAmounts = strategy.getSimulateSupplyStrategy(
            protocolsCache,
            _asset,
            _totalLending
        );
        for (uint256 i = 0; i < protocolsCache.length; i++) {
            protocolsCache[i].updateSupplyShare(_asset, supplyAmounts[i]);
        }
    }

    function simulateBorrow(address _asset, uint256 _totalLending)
        external
        onlyRouter
    {
        IProtocol[] memory protocolsCache = protocols;
        uint256[] memory borrowAmounts = strategy.getSimulateBorrowStrategy(
            protocolsCache,
            _asset,
            _totalLending
        );
        for (uint256 i = 0; i < protocolsCache.length; i++) {
            protocolsCache[i].updateBorrowShare(_asset, borrowAmounts[i]);
        }
    }

    function _supply(
        IProtocol _protocol,
        address _asset,
        uint256 _amount
    ) internal {
        Types.ProtocolData memory data = _protocol.getSupplyData(
            _asset,
            _amount
        );

        // if supply with ETH
        if (data.approveTo == address(0)) {
            Utils.lowLevelCall(data.target, data.encodedData, _amount);
        } else {
            if (data.weth != address(0)) {
                IWETH(data.weth).deposit{value: _amount}();
                TransferHelper.approve(data.weth, data.approveTo, _amount);
            } else {
                TransferHelper.approve(_asset, data.approveTo, _amount);
            }

            Utils.lowLevelCall(data.target, data.encodedData, 0);
        }

        if (!data.initialized) {
            Types.ProtocolData memory initData = _protocol.getAddAssetData(
                _asset
            );
            if (initData.target != address(0)) {
                Utils.lowLevelCall(initData.target, initData.encodedData, 0);
            }
            _protocol.setInitialized(_asset);
        }
    }

    function _redeem(
        IProtocol _protocol,
        address _asset,
        uint256 _amount
    ) internal {
        Types.ProtocolData memory data = _protocol.getRedeemData(
            _asset,
            _amount
        );
        Utils.lowLevelCall(data.target, data.encodedData, 0);
        if (data.weth != address(0)) {
            IWETH(data.weth).withdraw(_amount);
        }
    }

    function addProtocol(IProtocol _protocol) external override onlyRouter {
        protocols.push(_protocol);
    }

    function claimRewards(address _account, uint256[] memory _amounts)
        external
        override
        onlyRouter
    {
        for (uint256 i = 0; i < protocols.length; i++) {
            address token = protocols[i].rewardToken();
            TransferHelper.safeTransfer(token, _account, _amounts[i], 0);
        }
    }

    // admin functions
    function setRouter(address _router) external override onlyOwner {
        router = _router;
    }
}
