// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IConfig.sol";
import "./IPriceOracle.sol";
import "./IProtocolsHandler.sol";
import "./IRewards.sol";
import "./IStrategy.sol";

import "../libraries/Types.sol";

interface IRouter {
    event Supplied(
        address indexed supplier,
        address indexed asset,
        uint256 amount
    );
    event Redeemed(
        address indexed supplier,
        address indexed asset,
        uint256 amount
    );
    event Borrowed(
        address indexed borrower,
        address indexed asset,
        uint256 amount
    );
    event Repayed(
        address indexed borrower,
        address indexed asset,
        uint256 amount
    );

    event FeeCollected(
        address indexed asset,
        address indexed collector,
        uint256 amount
    );

    event TotalLendingsUpdated(address indexed asset, uint256 newLending);

    event AccFeeUpdated(address indexed asset, uint256 newAccFee);

    event FeeIndexUpdated(address indexed asset, uint256 newIndex);

    event UserFeeIndexUpdated(
        address indexed account,
        address indexed asset,
        uint256 newIndex
    );

    event AccFeeOffsetUpdated(address indexed asset, uint256 newIndex);

    function supply(Types.UserAssetParams memory, bool) external payable;

    function redeem(Types.UserAssetParams memory, bool) external;

    function borrow(Types.UserAssetParams memory) external;

    function repay(Types.UserAssetParams memory) external payable;

    function liquidate(
        Types.UserAssetParams memory,
        Types.UserAssetParams memory
    ) external payable;

    function sync(address _asset) external;

    function userStatus(address, address)
        external
        view
        returns (uint256, uint256);

    function protocols() external view returns (IProtocolsHandler);

    function getUnderlyings() external view returns (address[] memory);

    function getAssets() external view returns (Types.Asset[] memory assets);

    function totalSupplied(address _underlying) external view returns (uint256);

    function totalBorrowed(address _underlying) external view returns (uint256);

    // --- admin functions
    function addProtocol(IProtocol _protocol) external;

    function addAsset(Types.NewAssetParams memory _newAsset)
        external
        returns (Types.Asset memory asset);

    function updateSToken(address _sToken) external;

    function updateDToken(address _dToken) external;

    function updateConfig(IConfig _config) external;

    function updateProtocolsHandler(IProtocolsHandler _protocolsHandler)
        external;

    function updatePriceOracle(IPriceOracle _priceOracle) external;
}
