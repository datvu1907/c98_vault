//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFT721 is ERC721, Ownable {
    constructor() ERC721("", "") {}

    function mint(address account, uint256 id) public onlyOwner {
        _mint(account, id);
    }
}
