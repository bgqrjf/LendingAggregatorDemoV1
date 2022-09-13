// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "./interfaces/ISToken.sol";
// import "./interfaces/IRouter.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/TransferHelper.sol";

import "./Router.sol";

// Supply Token
contract SToken is ISToken, ERC20 {
    Router public immutable router;
    address public override underlying;

    modifier onlyRouter() {
        require(msg.sender == address(router), "SToken: OnlyRouter");
        _;
    }

    constructor(
        address _router,
        address _underlying,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        router = Router(payable(_router));
        underlying = _underlying;
    }

    function mint(
        address _account,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyRouter returns (uint256 amount) {
        amount = totalSupply() > 0
            ? (_amountOfUnderlying * totalSupply()) / _totalUnderlying
            : _amountOfUnderlying;
        _mint(_account, amount);
    }

    function burn(
        address _from,
        uint256 _amountOfUnderlying,
        uint256 _totalUnderlying
    ) external override onlyRouter returns (uint256 amount) {
        amount = totalSupply() > 0
            ? (_amountOfUnderlying * totalSupply()) / _totalUnderlying
            : _amountOfUnderlying;
        _burn(_from, amount);
    }

    function scaledBalanceOf(address _account)
        public
        view
        override
        returns (uint256)
    {
        return scaledAmount(balanceOf(_account));
    }

    function scaledAmount(uint256 _amount)
        public
        view
        override
        returns (uint256)
    {
        uint256 totalSupply = totalSupply();
        (, uint256 totalSupplied) = router.protocols().totalSupplied(
            underlying
        );
        return totalSupply > 0 ? (_amount * totalSupplied) / totalSupply : 0;
    }

    function scaledTotalSupply() public view override returns (uint256 amount) {
        (, amount) = router.protocols().totalSupplied(underlying);
    }

    function userShare(address _account)
        public
        view
        override
        returns (Types.UserShare memory share)
    {
        share = Types.UserShare(balanceOf(_account), totalSupply());
    }
}
