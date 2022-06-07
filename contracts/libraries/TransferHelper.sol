// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library TransferHelper{
    function transferETH(address _to, uint _amount) internal {
        (bool success, ) = _to.call{value: _amount}('');
        require(success, 'TransferHelper:ETH Failed');
    }

    function transferERC20(address _token, address _to, uint _amount) internal{
        (bool success, bytes memory returndata) = _token.call(abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount));
        require(success && abi.decode(returndata, (bool)), 'TransferHelper:Transfer Failed');
    }

    function transferFrom(address _token, address _from, address _to, uint _amount) internal{
        (bool success, bytes memory returndata) = _token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, _from, _to, _amount));
        require(success && abi.decode(returndata, (bool)), 'TransferHelper:Transfer Failed');
    }

    // to restrict balanceOf to view
    function balanceOf(address _token, address _account) internal view returns (uint balance){
        return IERC20(_token).balanceOf(_account);

    }
}