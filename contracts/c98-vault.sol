// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;
// import "./abstract/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./c98-vault-factory.sol";

interface ICoin98Vault {
    function init() external virtual;
}

contract Coin98Vault is Ownable, ERC721Holder, ERC1155Holder {
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
        uint256 receivingTokenAmount,
        uint256 receivingTokenId,
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

    function redeemERC1155(
        uint256 eventId_,
        uint256 index_,
        address recipient_,
        uint256 receivingAmount_,
        uint256 tokenId_,
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
            abi.encodePacked(
                index_,
                recipient_,
                receivingAmount_,
                sendingAmount_
            )
        );
        require(
            MerkleProof.verify(proofs, eventData.merkleRoot, node),
            "C98Vault: Invalid proof"
        );
        require(!isRedeemed(eventId_, index_), "C98Vault: Redeemed");

        uint256 availableAmount = IERC1155(eventData.receivingToken).balanceOf(
            address(this),
            tokenId_
        );

        require(
            receivingAmount_ <= availableAmount,
            "C98Vault: Insufficient token"
        );

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
        IERC1155(eventData.receivingToken).safeTransferFrom(
            address(this),
            recipient_,
            tokenId_,
            receivingAmount_,
            ""
        );

        emit Redeemed(
            eventId_,
            index_,
            recipient_,
            eventData.receivingToken,
            receivingAmount_,
            tokenId_,
            eventData.sendingToken,
            sendingAmount_
        );
    }

    function redeemERC721(
        uint256 eventId_,
        uint256 index_,
        address recipient_,
        uint256 tokenId_,
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
            abi.encodePacked(index_, recipient_, 1, sendingAmount_)
        );
        require(
            MerkleProof.verify(proofs, eventData.merkleRoot, node),
            "C98Vault: Invalid proof"
        );
        require(!isRedeemed(eventId_, index_), "C98Vault: Redeemed");

        address tokenOwner = IERC1155(eventData.receivingToken).ownerOf(
            tokenId_
        );

        require(tokenOwner == address(this), "C98Vault: Invalid token owner");

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

        IERC721(eventData.receivingToken).safeTransferFrom(
            address(this),
            recipient_,
            tokenId_,
            ""
        );

        emit Redeemed(
            eventId_,
            index_,
            recipient_,
            eventData.receivingToken,
            tokenId_,
            eventData.sendingToken,
            sendingAmount_
        );
    }
}
