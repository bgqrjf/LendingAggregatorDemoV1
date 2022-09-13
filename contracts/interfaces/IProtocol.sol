// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "../libraries/Types.sol";

interface IProtocol {
    function setInitialized(address _underlying) external;

    function updateSupplyShare(address _underlying, uint256 _amount) external;

    function updateBorrowShare(address _underlying, uint256 _amount) external;

    function getAddAssetData(address _underlying)
        external
        view
        returns (Types.ProtocolData memory data);

    function getSupplyData(address _underlying, uint256 _amount)
        external
        view
        returns (Types.ProtocolData memory data);

    function getRedeemData(address _underlying, uint256 _amount)
        external
        view
        returns (Types.ProtocolData memory data);

    function getRedeemAllData(address _underlying)
        external
        view
        returns (Types.ProtocolData memory data);

    function getBorrowData(address _underlying, uint256 _amount)
        external
        view
        returns (Types.ProtocolData memory data);

    function getRepayData(address _underlying, uint256 _amount)
        external
        view
        returns (Types.ProtocolData memory data);

    function getClaimRewardData(address _rewardToken)
        external
        view
        returns (Types.ProtocolData memory data);

    function getClaimUserRewardData(
        address _underlying,
        Types.UserShare memory _share,
        bytes memory _user,
        bytes memory _router
    )
        external
        view
        returns (
            bytes memory,
            bytes memory,
            address,
            uint256
        );

    function getCurrentSupplyRate(address _underlying)
        external
        view
        returns (uint256);

    function getCurrentBorrowRate(address _underlying)
        external
        view
        returns (uint256);

    function getUsageParams(address _underlying, uint256 _suppliesToRedeem)
        external
        view
        returns (bytes memory);

    function getRewardSupplyData(
        address _underlying,
        Types.UserShare memory _share,
        bytes memory _user,
        bytes memory _router
    ) external view returns (bytes memory, bytes memory);

    function getRouterRewardSupplyData(
        address _underlying,
        uint256 totalShare,
        bytes memory _router
    ) external view returns (bytes memory);

    function getRewardBorrowData(
        address _underlying,
        Types.UserShare memory _share,
        bytes memory _user,
        bytes memory _router
    ) external view returns (bytes memory, bytes memory);

    function supplyOf(address _underlying, address _account)
        external
        view
        returns (uint256);

    function debtOf(address _underlying, address _account)
        external
        view
        returns (uint256);

    function totalColletralAndBorrow(address _account, address _quote)
        external
        view
        returns (uint256 totalCollateral, uint256 totalBorrowed);

    function supplyToTargetSupplyRate(uint256 _targetRate, bytes memory _params)
        external
        pure
        returns (int256);

    function borrowToTargetBorrowRate(uint256 _targetRate, bytes memory _params)
        external
        pure
        returns (int256);

    function lastSupplyInterest(address _underlying)
        external
        view
        returns (uint256);

    function lastBorrowInterest(address _underlying)
        external
        view
        returns (uint256);
}
