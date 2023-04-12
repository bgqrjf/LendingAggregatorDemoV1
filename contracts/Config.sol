// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IConfig.sol";
import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./libraries/internals/UserAssetBitMap.sol";
import "./libraries/internals/Utils.sol";

contract Config is IConfig, OwnableUpgradeable {
    address public router;

    // mapping underlying token to assetConfig
    mapping(address => Types.AssetConfig) private _assetConfigs;

    // mapping (user address => collateral/debt assets)
    // using asset ID as bit map key of the value
    mapping(address => uint256) public userDebtAndCollateral;

    modifier onlyRouter() {
        require(msg.sender == router, "Config: Only Router");
        _;
    }

    function initialize() external initializer {
        __Ownable_init();
    }

    function setRouter(address _router) external override onlyOwner {
        address oldRouter = router;
        router = _router;
        emit RouterSet(oldRouter, _router);
    }

    function setAssetConfig(
        address _token,
        Types.AssetConfig memory _config
    ) external override {
        require(
            msg.sender == router || msg.sender == owner(),
            "Config: Only Router/Owner"
        );
        Types.AssetConfig memory oldConfig = _assetConfigs[_token];
        _assetConfigs[_token] = _config;
        emit AssetConfigSet(_token, oldConfig, _config);
    }

    function setUsingAsCollateral(
        address _account,
        address _underlying,
        bool _usingAsCollateral
    ) external override {
        require(
            msg.sender == router || msg.sender == _account,
            "Config: Only Router/User"
        );

        Types.Asset memory asset = IRouter(router).getAsset(_underlying);
        uint256 oldUserConfig = userDebtAndCollateral[_account];

        uint256 newUserConfig = oldUserConfig;
        if (
            UserAssetBitMap.isUsingAsCollateral(oldUserConfig, asset.index) !=
            _usingAsCollateral
        ) {
            uint256 bit = 1 << ((asset.index << 1) + 1);
            if (_usingAsCollateral) {
                newUserConfig = oldUserConfig | bit;
            } else {
                newUserConfig = oldUserConfig & ~bit;
            }

            userDebtAndCollateral[_account] = newUserConfig;

            (bool isHealthy, , ) = IRouter(router).isPoisitionHealthy(
                _underlying,
                _account
            );

            if (!_usingAsCollateral && !isHealthy) {
                require(
                    msg.sender == address(router),
                    "Config: Insufficinet Collateral"
                );

                newUserConfig = oldUserConfig;
                userDebtAndCollateral[_account] = oldUserConfig;
            }
        }

        emit UserDebtAndCollateralSet(_account, oldUserConfig, newUserConfig);
    }

    function setBorrowing(
        address _account,
        address _underlying,
        bool _borrowing
    ) external override onlyRouter {
        Types.Asset memory asset = IRouter(router).getAsset(_underlying);

        uint256 bit = 1 << (asset.index << 1);
        uint256 oldUserConfig = userDebtAndCollateral[_account];
        uint256 newUserConfig;
        if (_borrowing) {
            newUserConfig = oldUserConfig | bit;
        } else {
            newUserConfig = oldUserConfig & ~bit;
        }

        userDebtAndCollateral[_account] = newUserConfig;

        emit UserDebtAndCollateralSet(_account, oldUserConfig, newUserConfig);
    }

    function assetConfigs(
        address _token
    ) public view override returns (Types.AssetConfig memory) {
        return _assetConfigs[_token];
    }
}
