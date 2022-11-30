// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/IConfig.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/UserAssetBitMap.sol";

// proxy
contract Config is IConfig, Ownable {
    address public router;

    // mapping underlying token to borrowConfig
    mapping(address => Types.BorrowConfig) private _borrowConfigs;

    // mapping (user address => collateral/debt assets)
    // using asset ID as bit map key of the value
    mapping(address => uint256) public userDebtAndCollateral;

    modifier onlyRouter() {
        require(msg.sender == router, "Config: Only Router");
        _;
    }

    function setRouter(address _router) external override onlyOwner {
        address oldRouter = router;
        router = _router;
        emit RouterSet(oldRouter, _router);
    }

    function setBorrowConfig(address _token, Types.BorrowConfig memory _config)
        external
        override
    {
        require(
            msg.sender == router || msg.sender == owner(),
            "Config: Only Router/Owner"
        );
        Types.BorrowConfig memory oldConfig = _borrowConfigs[_token];
        _borrowConfigs[_token] = _config;
        emit BorrowConfigSet(_token, oldConfig, _config);
    }

    function setUsingAsCollateral(
        address _account,
        uint256 _reserveIndex,
        bool _usingAsCollateral
    ) external override {
        require(
            msg.sender == router || msg.sender == _account,
            "Config: Only Router/User"
        );
        require(
            _reserveIndex < UserAssetBitMap.MAX_RESERVES_COUNT,
            "Config: ID out of range"
        );
        uint256 bit = 1 << ((_reserveIndex << 1) + 1);
        uint256 oldUserConfig = userDebtAndCollateral[_account];
        uint256 newUserConfig;
        if (_usingAsCollateral) {
            newUserConfig = oldUserConfig | bit;
        } else {
            newUserConfig = oldUserConfig & ~bit;
        }

        userDebtAndCollateral[_account] = newUserConfig;

        emit UserDebtAndCollateralSet(_account, oldUserConfig, newUserConfig);
    }

    function setBorrowing(
        address _account,
        uint256 _reserveIndex,
        bool _borrowing
    ) external override onlyRouter {
        require(
            _reserveIndex < UserAssetBitMap.MAX_RESERVES_COUNT,
            "Config: ID out of range"
        );
        uint256 bit = 1 << (_reserveIndex << 1);
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

    function borrowConfigs(address _token)
        public
        view
        override
        returns (Types.BorrowConfig memory)
    {
        return _borrowConfigs[_token];
    }
}
