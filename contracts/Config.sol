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
        router = _router;
    }

    function setBorrowConfig(address _token, Types.BorrowConfig memory _config)
        external
        override
    {
        require(
            msg.sender == router || msg.sender == owner(),
            "Config: Only Router/Owner"
        );
        _borrowConfigs[_token] = _config;
    }

    function setUserColletral(address _user, uint256 _config)
        external
        onlyRouter
    {
        userDebtAndCollateral[_user] = _config;
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
        if (_usingAsCollateral) {
            userDebtAndCollateral[_account] |= bit;
        } else {
            userDebtAndCollateral[_account] &= ~bit;
        }
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
        if (_borrowing) {
            userDebtAndCollateral[_account] |= bit;
        } else {
            userDebtAndCollateral[_account] &= ~bit;
        }
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
