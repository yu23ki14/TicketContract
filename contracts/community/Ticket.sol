// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./Administration.sol";
import "./InteractHenkakuToken.sol";
import "./MintManager.sol";

contract Ticket is ERC1155, ERC1155Supply, Administration, MintManager, InteractHenakuToken {
    //@dev count up tokenId from 0
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    string public name;
    string public symbol;

    mapping(address => uint256[]) private ownerOfRegisteredIds;
    mapping(address => uint256[]) private ownerOfMintedIds;

    //@dev Declare Event to emit
    event RegisterTicket(
        address indexed creator,
        uint64 open_blockTimestamp,
        uint64 close_blockTimestamp,
        uint64 maxSupply,
        uint256 tokenId,
        uint256 price,
        string metaDataURL,
        uint256[] sharesAmounts,
        address[] shareholdersAddresses
    );
    event Mint(address indexed minter, uint256 indexed tokenId);

    error InvalidParams(string);

    /**
     * @param uri: metadata uri
     * @param creator: creator's wallet address
     * @param maxSupply: max supply number of token
     */
    struct TicketInfo {
        address creator;
        uint64 open_blockTimestamp;
        uint64 close_blockTimestamp;
        uint64 maxSupply;
        uint256 id;
        uint256 price;
        string uri;
        uint256[] sharesAmounts;
        address[] shareholdersAddresses;
    }

    TicketInfo[] private registeredTickets;

    constructor(
        string memory _name,
        string memory _symbol,
        address _communityToken
    ) ERC1155("") MintManager() InteractHenakuToken(_communityToken) {
        name = _name;
        symbol = _symbol;

        registeredTickets.push(TicketInfo(address(0), 0, 0, 0, 0, 0, "", new uint256[](0), new address[](0)));
        _tokenIds.increment();
    }

    modifier onlyHenkakuHolders() {
        _checkHenkakuV2Balance(1);
        _;
    }

    function _getTotalSharesAmounts(uint256[] memory _sharesAmounts) internal pure returns (uint256) {
        uint256[] memory sharedAmounts = _sharesAmounts;
        uint256 sharesAmountsLength = sharedAmounts.length;
        uint256 totalSharesAmounts = 0;
        for (uint256 i = 0; i < sharesAmountsLength; ) {
            totalSharesAmounts = totalSharesAmounts + sharedAmounts[i];
            unchecked {
                ++i;
            }
        }
        return totalSharesAmounts;
    }

    function registerTicket(
        uint64 _maxSupply,
        string calldata _metaDataURL,
        uint256 _price,
        uint64 _open_blockTimestamp,
        uint64 _close_blockTimestamp,
        address[] memory _shareholdersAddresses,
        uint256[] memory _sharesAmounts
    ) external onlyHenkakuHolders {
        if (
            _maxSupply == 0 ||
            keccak256(bytes(_metaDataURL)) == keccak256(bytes("")) ||
            _getTotalSharesAmounts(_sharesAmounts) != _price
        ) revert InvalidParams("Ticket: invalid params");

        uint256 tokenId = _tokenIds.current();
        ownerOfRegisteredIds[msg.sender].push(tokenId);
        registeredTickets.push(
            TicketInfo(
                msg.sender,
                _open_blockTimestamp,
                _close_blockTimestamp,
                _maxSupply,
                tokenId,
                _price,
                _metaDataURL,
                _sharesAmounts,
                _shareholdersAddresses
            )
        );
        _tokenIds.increment();

        // @dev Emit registeredTicket
        // @param address, tokenId, URL of meta data, max supply
        emit RegisterTicket(
            msg.sender,
            _open_blockTimestamp,
            _close_blockTimestamp,
            _maxSupply,
            tokenId,
            _price,
            _metaDataURL,
            _sharesAmounts,
            _shareholdersAddresses
        );
    }

    // @return all registered TicketInfo
    function retrieveAllTickets() public view returns (TicketInfo[] memory) {
        return registeredTickets;
    }

    // @return registered TicketInfo by tokenId
    function retrieveRegisteredTicket(uint256 _tokenId) public view returns (TicketInfo memory) {
        require(registeredTickets.length > _tokenId, "Ticket: not available");
        return registeredTickets[_tokenId];
    }

    // @return registered TicketInfo by address
    function retrieveRegisteredTickets(address _address) public view returns (TicketInfo[] memory) {
        uint256[] memory _ownerOfRegisteredIds = ownerOfRegisteredIds[_address];
        uint256 _ownerOfRegisteredIdsLength = _ownerOfRegisteredIds.length;
        TicketInfo[] memory _ownerOfRegisteredTickets = new TicketInfo[](_ownerOfRegisteredIdsLength);

        for (uint256 i = 0; i < _ownerOfRegisteredIdsLength; ) {
            TicketInfo memory _registeredTicket = registeredTickets[_ownerOfRegisteredIds[i]];
            _ownerOfRegisteredTickets[i] = _registeredTicket;
            unchecked {
                ++i;
            }
        }
        return _ownerOfRegisteredTickets;
    }

    // @dev mint function
    function mint(uint256 _tokenId) external onlyHenkakuHolders {
        require(mintable, "Ticket: Not mintable");
        require(balanceOf(msg.sender, _tokenId) == 0, "Ticket: You already have this ticket");

        TicketInfo memory ticket = retrieveRegisteredTicket(_tokenId);
        require(ticket.open_blockTimestamp <= block.timestamp, "Ticket: Not open yet");
        require(ticket.close_blockTimestamp >= block.timestamp, "Ticket: Already closed");
        require(ticket.maxSupply > totalSupply(_tokenId), "Ticket: Mint limit reached");

        ownerOfMintedIds[msg.sender].push(_tokenId);

        batchTransferHenkakuV2(ticket.price, ticket.sharesAmounts, ticket.shareholdersAddresses);

        _mint(msg.sender, _tokenId, 1, "");

        // @dev Emit mint event
        // @param address, tokenId
        emit Mint(msg.sender, _tokenId);
    }

    // @return holding tokenIds with address
    function retrieveMintedTickets(address _address) public view returns (TicketInfo[] memory) {
        uint256[] memory _ownerOfMintedIds = ownerOfMintedIds[_address];
        uint256 _ownerOfMintedIdsLength = _ownerOfMintedIds.length;
        TicketInfo[] memory _ownerOfMintedTickets = new TicketInfo[](_ownerOfMintedIdsLength);

        for (uint256 i = 0; i < _ownerOfMintedIdsLength; ) {
            _ownerOfMintedTickets[i] = registeredTickets[_ownerOfMintedIds[i]];
            unchecked {
                ++i;
            }
        }

        return _ownerOfMintedTickets;
    }

    // @return token metadata uri
    function uri(uint256 _tokenId) public view override(ERC1155) returns (string memory) {
        return retrieveRegisteredTicket(_tokenId).uri;
    }

    // @return token metadata uri
    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        return retrieveRegisteredTicket(_tokenId).uri;
    }

    function _beforeTokenTransfer(
        address _operator,
        address _from,
        address _to,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes memory _data
    ) internal virtual override(ERC1155, ERC1155Supply) {
        ERC1155Supply._beforeTokenTransfer(_operator, _from, _to, _ids, _amounts, _data);
    }
}
