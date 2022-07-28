//SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC20Token is ERC20, Ownable {
    mapping(address => bool) public isMinter;

    constructor() ERC20("TestTokenMintable", "TTM") {}

    function addMinter(address minter) external onlyOwner {
        isMinter[minter] = true;
    }

    function removeMinter(address minter) external onlyOwner {
        isMinter[minter] = false;
    }

    function mint(address to, uint256 amount) external {
        // require(isMinter[msg.sender], "DOES_NOT_HAVE_MINTER_ROLE");
        _mint(to, amount);
    }
}
