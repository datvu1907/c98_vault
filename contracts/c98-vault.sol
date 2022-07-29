// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./c98-vault-factory.sol";
import "./abstract/OwnableUpgradeable.sol";
import "hardhat/console.sol";

interface ICoin98Vault {
    function init() external virtual;
}

contract Coin98Vault is
    ICoin98Vault,
    OwnableUpgradeable,
    ERC721Holder,
    ERC1155Holder
{
    using SafeERC20 for IERC20;
    address private _factory;
    address[] private _admins;
    mapping(address => bool) private _adminStatuses;
    mapping(uint256 => EventData) private _eventDatas;
    mapping(uint256 => mapping(uint256 => bool)) private _eventRedemptions;

    struct EventData {
        uint256 timestamp;
        bytes32 merkleRoot;
        address receivingToken;
        address sendingToken;
        uint8 isActive;
        NftType nftType;      
    }
    enum NftType{
        Nft721,
        Nft1155
    }
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event EventCreated(uint256 eventId, EventData eventData);
    event EventUpdated(uint256 eventId, uint8 isActive);
    event Redeemed(
        uint256 eventId,
        uint256 index,
        address indexed recipient,
        address indexed receivingToken,
        uint256 receivingTokenId,
        uint256 receivingTokenAmount,
        address indexed sendingToken,
        uint256 sendingTokenAmount
    
    );
    event Withdrawn(
        address indexed owner,
        address indexed recipient,
        address indexed token,
        uint256 value
    );

    function _setRedemption(uint256 eventId_, uint256 index_) private {
        _eventRedemptions[eventId_][index_] = true;
    }

    modifier onlyAdmin() {
        require(
            owner() == _msgSender() || _adminStatuses[_msgSender()],
            "Ownable: caller is not an admin"
        );
        _;
    }

    /// @dev returns current admins who can manage the vault
    function admins() public view returns (address[] memory) {
        return _admins;
    }

    /// @dev returns info of an event
    /// @param eventId_ ID of the event
    function eventInfo(uint256 eventId_)
        public
        view
        returns (EventData memory)
    {
        return _eventDatas[eventId_];
    }

    /// @dev address of the factory
    function factory() public view returns (address) {
        return _factory;
    }

    /// @dev check an index whether it's redeemed
    /// @param eventId_ event ID
    /// @param index_ index of redemption pre-assigned to user
    function isRedeemed(uint256 eventId_, uint256 index_)
        public
        view
        returns (bool)
    {
        return _eventRedemptions[eventId_][index_];
    }

    /// @dev Initial vault
    function init() external override initializer {
        __Ownable_init();
        _factory = msg.sender;
    }
    
    /// @dev claim the token which user is eligible from schedule
    /// @param eventId_ event ID
    /// @param index_ index of redemption pre-assigned to user
    /// @param recipient_ index of redemption pre-assigned to user
    /// @param tokenId_ tokenId of nft
    /// @param receivingAmount_ amount of *receivingToken* user is eligible to redeem
    /// @param sendingAmount_ amount of *sendingToken* user must send the contract to get *receivingToken*
    /// @param proofs additional data to validate that the inputted information is valid
    function redeem(
        uint256 eventId_,
        uint256 index_,          
        address recipient_,
        uint256 tokenId_,
        uint256 receivingAmount_,
        uint256 sendingAmount_,
        bytes32[] calldata proofs
    ) public payable {
        uint256 fee = IVaultConfig(_factory).fee();
        uint256 gasLimit = IVaultConfig(_factory).gasLimit();
        if (fee > 0) {
            require(msg.value == fee, "C98Vault: Invalid fee");
        }

        EventData storage eventData = _eventDatas[eventId_];
        require(eventData.isActive > 0, "C98Vault: Invalid event");
        require(
            eventData.timestamp <= block.timestamp,
            "C98Vault: Schedule locked"
        );
        require(recipient_ != address(0), "C98Vault: Invalid schedule");

        bytes32 node = keccak256(
            abi.encodePacked(index_, recipient_, tokenId_, receivingAmount_, sendingAmount_)
        );
        require(
            MerkleProof.verify(proofs, eventData.merkleRoot, node),
            "C98Vault: Invalid proof"
        );
        require(!isRedeemed(eventId_, index_), "C98Vault: Redeemed");
        if(eventData.nftType == NftType.Nft1155){
            uint256 availableAmount = IERC1155(eventData.receivingToken).balanceOf(address(this),tokenId_);
            require(availableAmount > 0, "C98Vault: Insufficient token");
        }else{
            address tokenOwner = IERC721(eventData.receivingToken).ownerOf(tokenId_);
            require(tokenOwner == address(this), "C98Vault: Invalid token owner");
        }
        _setRedemption(eventId_, index_);
        if (fee > 0) {
            uint256 reward = IVaultConfig(_factory).ownerReward();
            uint256 finalFee = fee - reward;
            (bool success, bytes memory data) = _factory.call{
                value: finalFee,
                gas: gasLimit
            }("");
            require(success, "C98Vault: Unable to charge fee");
        }
        if (sendingAmount_ > 0) {
            IERC20(eventData.sendingToken).safeTransferFrom(
                _msgSender(),
                address(this),
                sendingAmount_
            );
        }
        if(eventData.nftType == NftType.Nft1155){
            IERC1155(eventData.receivingToken).safeTransferFrom(address(this), recipient_, tokenId_,receivingAmount_,"");
        }else{
            IERC721(eventData.receivingToken).safeTransferFrom(address(this), recipient_, tokenId_, "");
        }
      

        emit Redeemed(
            eventId_,
            index_,
            recipient_,
            eventData.receivingToken,
            tokenId_,
            receivingAmount_,
            eventData.sendingToken,
            sendingAmount_
        );
    }

    /// @dev create an event to specify how user can claim their token
    /// @param eventId_ event ID
    /// @param timestamp_ when the token will be available for redemption
    /// @param receivingToken_ token user will be receiving, mandatory
    /// @param sendingToken_ token user need to send in order to receive *receivingToken_*
    function createEvent(
        uint256 eventId_,
        uint256 timestamp_,
        bytes32 merkleRoot_,
        address receivingToken_,
        address sendingToken_,
        NftType nftType_
    ) public onlyAdmin {
        require(
            _eventDatas[eventId_].timestamp == 0,
            "C98Vault: Event existed"
        );
        require(timestamp_ != 0, "C98Vault: Invalid timestamp");
        _eventDatas[eventId_].timestamp = timestamp_;
        _eventDatas[eventId_].merkleRoot = merkleRoot_;
        _eventDatas[eventId_].receivingToken = receivingToken_;
        _eventDatas[eventId_].sendingToken = sendingToken_;
        _eventDatas[eventId_].isActive = 1;
        _eventDatas[eventId_].nftType = nftType_;

        emit EventCreated(eventId_, _eventDatas[eventId_]);
    }

    /// @dev enable/disable a particular event
    /// @param eventId_ event ID
    /// @param isActive_ zero to inactive, any number to active
    function setEventStatus(uint256 eventId_, uint8 isActive_)
        public
        onlyAdmin
    {
        require(
            _eventDatas[eventId_].timestamp != 0,
            "C98Vault: Invalid event"
        );
        _eventDatas[eventId_].isActive = isActive_;

        emit EventUpdated(eventId_, isActive_);
    }

    /// @dev add/remove admin of the vault.
    /// @param nAdmins_ list to address to update
    /// @param nStatuses_ address with same index will be added if true, or remove if false
    /// admins will have access to all tokens in the vault, and can define vesting schedule
    function setAdmins(address[] memory nAdmins_, bool[] memory nStatuses_)
        public
        onlyOwner
    {
        require(nAdmins_.length != 0, "C98Vault: Empty arguments");
        require(nStatuses_.length != 0, "C98Vault: Empty arguments");
        require(
            nAdmins_.length == nStatuses_.length,
            "C98Vault: Invalid arguments"
        );

        uint256 i;
        for (i = 0; i < nAdmins_.length; i++) {
            address nAdmin = nAdmins_[i];
            if (nStatuses_[i]) {
                if (!_adminStatuses[nAdmin]) {
                    _admins.push(nAdmin);
                    _adminStatuses[nAdmin] = nStatuses_[i];
                    emit AdminAdded(nAdmin);
                }
            } else {
                uint256 j;
                for (j = 0; j < _admins.length; j++) {
                    if (_admins[j] == nAdmin) {
                        _admins[j] = _admins[_admins.length - 1];
                        _admins.pop();
                        delete _adminStatuses[nAdmin];
                        emit AdminRemoved(nAdmin);
                        break;
                    }
                }
            }
        }
    }
}
