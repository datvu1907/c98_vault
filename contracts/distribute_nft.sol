// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "hardhat/console.sol";

contract DistributedNFT is Ownable, ERC721Holder, ERC1155Holder {
    mapping(address => uint256) listNFT721;
    address private admin;
    address private _factory;
    address[] private _admins;
    mapping(address => bool) private _adminStatuses;

    mapping(uint256 => mapping(uint256 => bool)) private _eventRedemptions;

    constructor() {}

    /// @dev Access Control, only owner and admins are able to access the specified function
    modifier onlyAdmin() {
        require(
            owner() == _msgSender() || _adminStatuses[_msgSender()],
            "Ownable: caller is not an admin"
        );
        _;
    }

    function claimNFT721(address _tokenAddress, uint256 _tokenId)
        external
        onlyOwner
    {
        require(admin != address(0), "Admin address is not exist");
        require(
            IERC721(_tokenAddress).ownerOf(_tokenId) == admin,
            "Admin doesn't own NFT"
        );

        IERC721(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId
        );
    }

    function sendNFT1155(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _amount
    ) external onlyOwner {
        require(
            IERC1155(_tokenAddress).balanceOf(msg.sender, _tokenId) >= _amount,
            "Sender doesn't have enough NFT"
        );

        IERC1155(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId,
            _amount,
            ""
        );
    }

    function setAddminAddress(address _admin) external onlyOwner {
        require(_admin != address(0), "Invalid input");
        admin = _admin;
    }
}
