// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./IConfig.sol";
import "./IPriceOracle.sol";
import "./IProtocolsHandler.sol";
import "./IReservePool.sol";
import "./IRewards.sol";
import "./IStrategy.sol";

import "../libraries/internals/Types.sol";

interface IRouter {
    enum Action {
        supply,
        redeem,
        borrow,
        repay,
        liquidate,
        claimRewards
    }

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

    event Repaid(
        address indexed borrower,
        address indexed asset,
        uint256 amount
    );

    event Liquidate(Types.UserAssetParams redeemParams,address liquidator);

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

    event BlockActionsSet(address asset, uint256 actions);

    event TokenPausedSet(address asset,bool isPaused);

    event ProtocolAdded(IProtocol protocol);

    event ProtocolUpdated(IProtocol old,IProtocol _new);

    event AssetAdded(address underlying,Types.Asset asset);

    event ReservePoolConfigUpdated(address asset,uint256 maxReserve,uint256 executeSupplyThreshold);

    event STokenUpdated(address sToken);

    event DTokenUpdated(address dToken);

    event ConfigUpdated(IConfig config);

    event ProtocolsHandlerUpdated(IProtocolsHandler protocolsHandler);

    event PriceOracleUpdated(IPriceOracle priceOracle);

    function supply(
        Types.UserAssetParams memory _params,
        bool _collateralable,
        bool _executeNow
    ) external payable;

    function redeem(
        Types.UserAssetParams memory _params,
        bool _collateralable,
        bool _executeNow
    ) external;

    function borrow(Types.UserAssetParams memory, bool _executeNow) external;

    function repay(Types.UserAssetParams memory _params, bool _executeNow)
        external
        payable;

    function recordSupply(
        Types.UserAssetParams memory _params,
        uint256 totalSupplies,
        uint256 newInterest,
        bool _collateralable
    ) external;

    function recordRedeem(
        Types.UserAssetParams memory _params,
        uint256 totalSupplies,
        uint256 newInterest,
        address _redeemFrom,
        bool _collateralable
    ) external returns (uint256 underlyingAmount, uint256 fee);

    function recordBorrow(
        Types.UserAssetParams memory _params,
        uint256 _newInterest,
        uint256 _totalBorrows,
        address _borrowBy
    ) external;

    function executeSupply(
        address _asset,
        uint256 _amount,
        uint256 _totalLending,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies
    ) external payable;

    function executeRedeem(
        Types.UserAssetParams memory _params,
        uint256[] memory _supplies,
        uint256 _protocolsSupplies,
        uint256 _totalLending
    ) external;

    function executeBorrow(Types.UserAssetParams memory _params) external;

    function executeRepay(address _asset, uint256 _amount) external;

    function liquidate(
        Types.UserAssetParams memory,
        Types.UserAssetParams memory
    ) external payable;

    function sync(address _asset) external;

    function claimRewards(address _account) external;

    function userStatus(address, address)
        external
        view
        returns (
            uint256,
            uint256,
            bool
        );

    function protocols() external view returns (IProtocolsHandler);

    function getUnderlyings() external view returns (address[] memory);

    function getAssets() external view returns (Types.Asset[] memory assets);

    function getSupplyStatus(address _underlying)
        external
        view
        returns (
            uint256[] memory supplies,
            uint256 protocolsSupplies,
            uint256 totalLending,
            uint256 totalSuppliedAmountWithFee,
            uint256 newInterest
        );

    function getBorrowStatus(address _underlying)
        external
        view
        returns (
            uint256[] memory borrows,
            uint256 totalBorrowedAmount,
            uint256 totalLending,
            uint256 newInterest
        );

    function getSupplyRate(address _underlying) external view returns (uint256);

    function getBorrowRate(address _underlying) external view returns (uint256);

    function getLendingRate(address _underlying)
        external
        view
        returns (uint256);

    function totalSupplied(address _underlying) external view returns (uint256);

    function totalBorrowed(address _underlying) external view returns (uint256);

    function isPoisitionHealthy(address _underlying, address _account)
        external
        view
        returns (bool);

    function isUsingAsCollateral(address _underlying, address _account)
        external
        view
        returns (bool);

    function isBorrowing(address _underlying, address _account)
        external
        view
        returns (bool);

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

    function updateProtocol(IProtocol _old, IProtocol _new) external;

    function updatePriceOracle(IPriceOracle _priceOracle) external;

    // --- getters
    function getAsset(address _underlying)
        external
        view
        returns (Types.Asset memory asset);
}
