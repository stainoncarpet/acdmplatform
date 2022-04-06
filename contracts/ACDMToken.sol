//SPDX-License-Identifier: MIT

pragma solidity >=0.8.12 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

contract ACDMToken is ERC20, Ownable {
    address public PLATFORM;

    constructor() ERC20("ACDMToken", "ACDMT") {  }

    modifier onlyPlatform() {
        require(PLATFORM == msg.sender);
        _;
    }

    function setPlatform(address platform) external onlyOwner {
        PLATFORM = platform;
    }

    function mint(uint256 amount) external onlyPlatform {
        _mint(PLATFORM, amount);
    }

    function burn(uint256 amount) external onlyPlatform {
        _burn(PLATFORM, amount);
    }
}
