/*
This file is part of the TheWall project.

The TheWall Contract is free software: you can redistribute it and/or
modify it under the terms of the GNU lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

The TheWall Contract is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU lesser General Public License for more details.

You should have received a copy of the GNU lesser General Public License
along with the TheWall Contract. If not, see <http://www.gnu.org/licenses/>.

@author Ilya Svirin <is.svirin@gmail.com>
*/

pragma solidity ^0.5.5;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/ERC721Full.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/ERC721Metadata.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/roles/WhitelistAdminRole.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/GSN/Context.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/drafts/Strings.sol";
import "./thewallcore.sol";


contract TheWall is ERC721, ERC721Metadata, WhitelistAdminRole
{
    using Strings for uint256;

    event Payment(address indexed sender, uint256 amountWei);

    event AreaCreated(uint256 indexed tokenId, address indexed owner, int256 x, int256 y, uint256 nonce, bytes32 hashOfSecret);
    event ClusterCreated(uint256 indexed tokenId, address indexed owner, string title);
    event ClusterRemoved(uint256 indexed tokenId);

    event AreaAddedToCluster(uint256 indexed areaTokenId, uint256 indexed clusterTokenId, uint256 revision);
    event AreaRemovedFromCluster(uint256 indexed areaTokenId, uint256 indexed clusterTokenId, uint256 revision);

    event AreaImageChanged(uint256 indexed tokenId, bytes image);
    event ItemLinkChanged(uint256 indexed tokenId, string link);
    event ItemTagsChanged(uint256 indexed tokenId, string tags);
    event ItemTitleChanged(uint256 indexed tokenId, string title);
    event ItemContentChanged(uint256 indexed tokenId, bytes content);

    event ItemTransferred(uint256 indexed tokenId, address indexed from, address indexed to);
    event ItemForRent(uint256 indexed tokenId, uint256 priceWei, uint256 durationSeconds);
    event ItemForSale(uint256 indexed tokenId, uint256 priceWei);
    event ItemRented(uint256 indexed tokenId, address indexed tenant, uint256 finishTime);
    event ItemReset(uint256 indexed tokenId);
    event ItemRentFinished(uint256 indexed tokenId);

    TheWallCore private _core;
    uint256     private _minterCounter;
    string      private _baseURI;

    constructor(address core) public ERC721Metadata("TheWall", "TWG")
    {
        _core = TheWallCore(core);
        _core.setTheWall(address(this));
        _baseURI = "https://thewall.global/erc721/";
    }

    function setBaseURI(string memory baseURI) public onlyWhitelistAdmin
    {
        _baseURI = baseURI;
    }
    
    function tokenURI(uint256 tokenId) external view returns (string memory)
    {
        require(_exists(tokenId));
        return string(abi.encodePacked(_baseURI, tokenId.fromUint256()));
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public
    {
        safeTransferFrom(from, to, tokenId, "");
    }

    function transferFrom(address from, address to, uint256 tokenId) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId));
        _core._canBeTransferred(tokenId);
        uint256[] memory tokens = _core._areasInCluster(tokenId);
        for(uint i = 0; i < tokens.length; ++i)
        {
            _transferFrom(from, to, tokens[i]);
        }
        _transferFrom(from, to, tokenId);
        emit ItemTransferred(tokenId, from, to);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId));
        _core._canBeTransferred(tokenId);
        uint256[] memory tokens = _core._areasInCluster(tokenId);
        for(uint i = 0; i < tokens.length; ++i)
        {
            _safeTransferFrom(from, to, tokens[i], data);
        }
        _safeTransferFrom(from, to, tokenId, data);
        emit ItemTransferred(tokenId, from, to);
    }

    function forSale(uint256 tokenId, uint256 priceWei) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId));
        _core._forSale(tokenId, priceWei);
        emit ItemForSale(tokenId, priceWei);
    }

    function forRent(uint256 tokenId, uint256 priceWei, uint256 durationSeconds) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId));
        _core._forRent(tokenId, priceWei, durationSeconds);
        emit ItemForRent(tokenId, priceWei, durationSeconds);
    }

    function createCluster(string memory title) public returns (uint256)
    {
        address me = _msgSender();

        _minterCounter = _minterCounter.add(1);
        uint256 tokenId = _minterCounter;
        _safeMint(me, tokenId);
        _core._createCluster(tokenId, title);

        emit ClusterCreated(tokenId, me, title);
        return tokenId;
    }

    function removeCluster(uint256 tokenId) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId));
        _core._removeCluster(tokenId);
        _burn(tokenId);
        emit ClusterRemoved(tokenId);
    }
    
    function _create(address owner, int256 x, int256 y, uint256 clusterId, uint256 nonce) internal returns (uint256)
    {
        _minterCounter = _minterCounter.add(1);
        uint256 tokenId = _minterCounter;
        _safeMint(owner, tokenId);
        
        uint256 revision;
        bytes32 hashOfSecret;
        (revision, hashOfSecret) = _core._create(tokenId, x, y, clusterId, nonce);
        
        emit AreaCreated(tokenId, owner, x, y, nonce, hashOfSecret);
        if (clusterId != 0)
        {
            emit AreaAddedToCluster(tokenId, clusterId, revision);
        }
        
        return tokenId;
    }

    function create(int256 x, int256 y, address payable referrerCandidate, uint256 nonce) public payable returns (uint256)
    {
        address me = _msgSender();
        _core._canBeCreated(x, y);
        uint256 area = _create(me, x, y, 0, nonce);
        
        uint256 payValue = _core._processPaymentCreate.value(msg.value)(me, msg.value, 1, referrerCandidate);
        if (payValue > 0)
        {
            emit Payment(me, payValue);
        }

        return area;
    }

    function createMulti(int256 x, int256 y, int256 width, int256 height, address payable referrerCandidate, uint256 nonce) public payable returns (uint256)
    {
        address me = _msgSender();
        _core._canBeCreatedMulti(x, y, width, height);

        uint256 cluster = createCluster("");
        uint256 areasNum = 0;
        int256 i;
        int256 j;
        for(i = 0; i < width; ++i)
        {
            for(j = 0; j < height; ++j)
            {
                if (_core._areaOnTheWall(x + i, y + j) == uint256(0))
                {
                    areasNum = areasNum.add(1);
                    _create(me, x + i, y + j, cluster, nonce);
                }
            }
        }

        uint256 payValue = _core._processPaymentCreate.value(msg.value)(me, msg.value, areasNum, referrerCandidate);
        if (payValue > 0)
        {
            emit Payment(me, payValue);
        }

        return cluster;
    }

    function buy(uint256 tokenId, uint256 revision, address payable referrerCandidate) payable public
    {
        address me = _msgSender();
        address payable tokenOwner = ownerOf(tokenId).toPayable();
        _core._buy.value(msg.value)(tokenOwner, tokenId, me, msg.value, revision, referrerCandidate);
        emit Payment(me, msg.value);
        uint256[] memory tokens = _core._areasInCluster(tokenId);
        for(uint i = 0; i < tokens.length; ++i)
        {
            _safeTransferFrom(tokenOwner, me, tokens[i], "");
        }
        _safeTransferFrom(tokenOwner, me, tokenId, "");
        emit ItemTransferred(tokenId, tokenOwner, me);
    }

    function rent(uint256 tokenId, uint256 revision, address payable referrerCandidate) payable public
    {
        address me = _msgSender();
        address payable tokenOwner = ownerOf(tokenId).toPayable();
        uint256 rentDuration;
        rentDuration = _core._rent.value(msg.value)(tokenOwner, tokenId, me, msg.value, revision, referrerCandidate);
        emit Payment(me, msg.value);
        emit ItemRented(tokenId, me, rentDuration);
    }
    
    function rentTo(uint256 tokenId, address tenant, uint256 durationSeconds) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId));
        uint256 rentDuration;
        rentDuration = _core._rentTo(tokenId, tenant, durationSeconds);
        emit ItemRented(tokenId, tenant, rentDuration);
    }
    
    function cancel(uint256 tokenId) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId));
        _core._cancel(tokenId);
        emit ItemReset(tokenId);
    }
    
    function finishRent(uint256 tokenId) public
    {
        _core._finishRent(_msgSender(), tokenId);
        emit ItemRentFinished(tokenId);
    }
    
    function addToCluster(uint256 areaId, uint256 clusterId) public
    {
        uint256 revision = _core._addToCluster(_msgSender(), ownerOf(areaId), ownerOf(clusterId), areaId, clusterId);
        emit AreaAddedToCluster(areaId, clusterId, revision);
    }

    function removeFromCluster(uint256 areaId, uint256 clusterId) public
    {
        uint256 revision = _core._removeFromCluster(_msgSender(), ownerOf(areaId), ownerOf(clusterId), areaId, clusterId);
        emit AreaRemovedFromCluster(areaId, clusterId, revision);
    }

    function setImage(uint256 tokenId, bytes memory image) public
    {
        _core._setImage(_msgSender(), ownerOf(tokenId), tokenId, image);
        emit AreaImageChanged(tokenId, image);
    }

    function setLink(uint256 tokenId, string memory link) public
    {
        _core._setLink(_msgSender(), ownerOf(tokenId), tokenId, link);
        emit ItemLinkChanged(tokenId, link);
    }

    function setTags(uint256 tokenId, string memory tags) public
    {
        _core._setTags(_msgSender(), ownerOf(tokenId), tokenId, tags);
        emit ItemTagsChanged(tokenId, tags);
    }

    function setTitle(uint256 tokenId, string memory title) public
    {
        _core._setTitle(_msgSender(), ownerOf(tokenId), tokenId, title);
        emit ItemTitleChanged(tokenId, title);
    }

    function setContent(uint256 tokenId, bytes memory content) public
    {
        _core._setContent(_msgSender(), ownerOf(tokenId), tokenId, content);
        emit ItemContentChanged(tokenId, content);
    }
    
    function buyCoupons(address payable referrerCandidate) payable public
    {
        address me = _msgSender();
        uint256 payValue = _core._buyCoupons.value(msg.value)(me, msg.value, referrerCandidate);
        if (payValue > 0)
        {
            emit Payment(me, payValue);
        }
    }
    
    function () payable external
    {
        buyCoupons(address(0));
    }
}