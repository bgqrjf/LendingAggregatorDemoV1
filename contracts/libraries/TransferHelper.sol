// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library TransferHelper{
    address constant public ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function transferETH(address _to, uint _amount) internal {
        (bool success, ) = _to.call{value: _amount}('');
        require(success, 'TransferHelper:ETH Failed');
    }

    function transferERC20(address _token, address _to, uint _amount) internal{
        (bool success, bytes memory returndata) = _token.call(abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount));
        require(success && abi.decode(returndata, (bool)), 'TransferHelper:Transfer Failed');
    }

    function transfer(address _token, address _to, uint _amount) internal{
        _token == ETH ? transferETH(_to, _amount) : transferERC20(_token, _to, _amount);
    }

    function transferFrom(address _token, address _from, address _to, uint _amount) internal{
        (bool success, bytes memory returndata) = _token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, _from, _to, _amount));
        require(success && abi.decode(returndata, (bool)), 'TransferHelper:Transfer From Failed');
    }

    function approve(address _token, address _spender, uint _amount) internal{
        (bool success, bytes memory returndata) = _token.call(abi.encodeWithSelector(IERC20.approve.selector, _spender, _amount));
        require(success && abi.decode(returndata, (bool)), 'TransferHelper:Approve Failed');
    }

    function balanceOf(address _token, address _account) internal view returns (uint balance){
        return _token == ETH ? _account.balance : IERC20(_token).balanceOf(_account);
    }
    
}