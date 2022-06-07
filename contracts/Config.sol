// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Types.sol";

contract Config is Ownable{
    uint public immutable MAX_RESERVES_COUNT = 128;

    address public router;

    // mapping underlyingToken to borrowConfig
    mapping(address => Types.BorrowConfig) public borrowConfigs;

    // mapping (user address => collateral/debt assets)
    // using asset ID as bit map key of the value
    mapping(address => uint) public userDebtAndCollateral;

    modifier onlyRouterOrOwner{
        require(msg.sender == router || msg.sender == owner(), "Config: Only Router/Owner");
        _;
    }

    modifier onlyRouter{
        require(msg.sender == router, "Config: Only Router");
        _;
    }

    modifier onyRouterAndUser(address _account){
        _;
    }

    constructor(address _owner){
        transferOwnership(_owner);
        router = msg.sender;
    }

    function setBorrowConfig(address _token, Types.BorrowConfig memory _config) external onlyRouterOrOwner{
        borrowConfigs[_token] = _config;
    }

    function setUserColletral(address _user, uint _config) external onlyRouter{
        userDebtAndCollateral[_user] = _config;
    }

    function setUsingAsCollateral(address _account, uint256 _reserveIndex, bool _usingAsCollateral) external {
        require(msg.sender == router || msg.sender == _account, "Config: Only Router/User");
        require(_reserveIndex < MAX_RESERVES_COUNT, "Config: ID out of range");
        uint256 bit = 1 << ((_reserveIndex << 1) + 1);
        if (_usingAsCollateral) {
            userDebtAndCollateral[_account] |= bit;
        } else {
            userDebtAndCollateral[_account] &= ~bit;
        }
    }

    function setBorrowing(address _account, uint256 _reserveIndex, bool _borrowing) external onlyRouter {
        require(_reserveIndex < MAX_RESERVES_COUNT, "Config: ID out of range");
        uint256 bit = 1 << (_reserveIndex << 1);
        if (_borrowing) {
            userDebtAndCollateral[_account] |= bit;
        } else {
            userDebtAndCollateral[_account] &= ~bit;
        }
    }

}