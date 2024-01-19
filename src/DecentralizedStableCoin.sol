//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustbeGreaterThanZero();
    error DecentralizedStableCoin__BalanceMustBeGreater();

    constructor() ERC20("DecentralisedRupee", "RPE") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustbeGreaterThanZero();
        }
        if (balanceOf(msg.sender) < _amount) {
            revert DecentralizedStableCoin__BalanceMustBeGreater();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 amount) external onlyOwner returns (bool) {
        if (amount <= 0) {
            revert DecentralizedStableCoin__MustbeGreaterThanZero();
        }
        _mint(_to, amount);
        return true;
    }
}
