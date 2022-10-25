// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IProtocolsHandler.sol";

import "./libraries/TransferHelper.sol";
import "./libraries/Utils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolsHandler is IProtocolsHandler, Ownable {
    address public immutable router;
    IStrategy public strategy;
    IProtocol[] public protocols;

    modifier onlyRouter() {
        require(msg.sender == router, "ProtocolsHandler: OnlyRouter");
        _;
    }

    constructor(
        address[] memory _protocols,
        address _strategy,
        address _router
    ) {
        protocols = new IProtocol[](_protocols.length);
        for (uint256 i = 0; i < _protocols.length; i++) {
            protocols[i] = IProtocol(_protocols[i]);
        }
        strategy = IStrategy(_strategy);
        router = _router;
    }

    function redeemAndSupply(
        address _asset,
        uint256[] memory supplies,
        uint256 _totalSupplied
    ) internal {
        IProtocol[] memory protocolsCache = protocols;
        (
            uint256[] memory supplyAmounts,
            uint256[] memory redeemAmounts
        ) = strategy.getSupplyStrategy(
                protocolsCache,
                _asset,
                supplies,
                _totalSupplied
            );
        for (uint256 i = 0; i < protocolsCache.length; i++) {
            if (redeemAmounts[i] > 0) {
                _redeem(protocolsCache[i], _asset, redeemAmounts[i]);
            }

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
    ) public onlyRouter returns (uint256 amount) {
        redeemAndSupply(_asset, supplies, _totalSupplied + _amount);
        return _amount;
    }

    function redeem(
        address _asset,
        uint256 _amount,
        uint256[] memory supplies,
        uint256 _totalSupplied,
        address _to
    ) public onlyRouter returns (uint256 amount) {
        // expect revert if _amount > _totalSupplied
        redeemAndSupply(_asset, supplies, _totalSupplied - _amount);
        TransferHelper.transfer(_asset, _to, _amount);

        return _amount;
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

        TransferHelper.transfer(_params.asset, _params.to, _params.amount);

        return _params.amount;
    }

    function repay(Types.UserAssetParams memory _params)
        public
        onlyRouter
        returns (uint256 amount)
    {
        (, uint256 total) = totalBorrowed(_params.asset);
        _params.amount = Utils.minOf(_params.amount, total);

        IProtocol[] memory protocolsCache = protocols;
        uint256[] memory amounts = strategy.getRepayStrategy(
            protocolsCache,
            _params.asset,
            _params.amount
        );

        for (uint256 i = 0; i < protocolsCache.length; i++) {
            if (amounts[i] > 0) {
                Types.ProtocolData memory data = protocolsCache[i].getRepayData(
                    _params.asset,
                    amounts[i]
                );

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

        return _params.amount;
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
        returns (uint256 totalLending)
    {
        IProtocol[] memory protocolsCache = protocols;
        uint256 supplyInterest;
        uint256 borrowInterest;

        for (uint256 i = 0; i < protocolsCache.length; i++) {
            supplyInterest = protocolsCache[i].lastSupplyInterest(
                _asset,
                address(this)
            );

            borrowInterest = protocolsCache[i].lastBorrowInterest(
                _asset,
                address(this)
            );
        }

        uint256 interestDelta = borrowInterest > supplyInterest
            ? borrowInterest - supplyInterest
            : 0;

        (, uint256 borrowed) = totalBorrowed(_asset);
        (, uint256 supplied) = totalSupplied(_asset);

        totalLending = _totalLending + (interestDelta * borrowed) / supplied;
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

    function getProtocols() public view override returns (IProtocol[] memory) {
        return protocols;
    }

    // admin functions
    function addProtocol(IProtocol _protocol) external override onlyOwner {
        protocols.push(_protocol);
    }
}
