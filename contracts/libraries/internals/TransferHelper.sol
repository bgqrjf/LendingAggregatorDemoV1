// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library TransferHelper {
    using SafeERC20 for IERC20;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function transferETH(
        address _to,
        uint256 _amount,
        uint256 _gasLimit
    ) internal {
        bool success;
        if (_gasLimit > 0) {
            (success, ) = _to.call{value: _amount, gas: _gasLimit}("");
        } else {
            (success, ) = _to.call{value: _amount}("");
        }

        require(success, "TransferHelper:ETH Failed");
    }

    function safeTransfer(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _gasLimit
    ) internal {
        _token == ETH
            ? transferETH(_to, _amount, _gasLimit)
            : IERC20(_token).safeTransfer(_to, _amount);
    }

    function safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        IERC20(_token).safeTransferFrom(_from, _to, _amount);
    }

    function collect(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        uint256 _gasLimit
    ) internal {
        if (_token != ETH) {
            IERC20(_token).safeTransferFrom(_from, _to, _amount);
        } else {
            require(
                msg.value >= _amount,
                "TransferHelper: insufficient eth value received"
            );
            if (_to != address(this)) {
                transferETH(_to, _amount, _gasLimit);
            }
        }
    }

    // approve twice for USDT
    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20(_token).safeApprove(_spender, _amount);
    }

    function balanceOf(
        address _token,
        address _account
    ) internal view returns (uint256 balance) {
        return
            _token == ETH
                ? _account.balance
                : IERC20(_token).balanceOf(_account);
    }
}
