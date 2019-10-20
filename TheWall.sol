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

pragma solidity ^0.5.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/ERC721Full.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/roles/WhitelistAdminRole.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/GSN/Context.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/math/SafeMath.sol";


contract Users is Context
{
    struct User
    {
        string nickname;
        bytes  avatar;
    }
    
    mapping (address => User) public _users;
    
    event NicknameChanged(address indexed user, string nickname);
    event AvatarChanged(address indexed user, bytes avatar);
    
    function setNickname(string memory nickname) public
    {
        _users[_msgSender()].nickname = nickname;
        emit NicknameChanged(_msgSender(), nickname);
    }

    function setAvatar(bytes memory avatar) public
    {
        _users[_msgSender()].avatar = avatar;
        emit AvatarChanged(_msgSender(), avatar);
    }
    
    function setNicknameAvatar(string memory nickname, bytes memory avatar) public
    {
        setNickname(nickname);
        setAvatar(avatar);
    }
}

contract Marketing is WhitelistAdminRole
{
    using SafeMath for uint256;
    mapping (address => uint256) public _coupons;
    
    function _useCoupons(address owner, uint256 count) internal returns(bool)
    {
        if (_coupons[owner] >= count)
        {
            _coupons[owner] -= count;
            return true;
        }
        return false;
    }
    
    function giveCoupons(address[] memory owners, uint256 count) public onlyWhitelistAdmin
    {
        for(uint i = 0; i < owners.length; ++i)
        {
            _coupons[owners[i]] = _coupons[owners[i]].add(count);
        }
    }
}

contract RefModel
{
    using SafeMath for uint256;

    event ReferrerChanged(address indexed me, address indexed referrer);

    mapping (address => address payable) private _referrers;

    function processRef(address me, address payable referrerCandidate, uint256 amountWei) internal returns(uint256)
    {
        if (referrerCandidate != address(0) && _referrers[me] == address(0))
        {
            _referrers[me] = referrerCandidate;
            emit ReferrerChanged(me, referrerCandidate);
        }
        
        uint256 alreadyPayed = 0;
        uint256 refPayment = amountWei.mul(6).div(100);

        address payable ref = _referrers[me];
        if (ref != address(0))
        {
            ref.transfer(refPayment);
            alreadyPayed = refPayment;
            
            ref = _referrers[ref];
            if (ref != address(0))
            {
                ref.transfer(refPayment);
                alreadyPayed = refPayment.mul(2);
            }
        }
        
        return alreadyPayed;
    }
}


contract TheWall is ERC721Full, WhitelistAdminRole, RefModel, Users, Marketing
{
    using Address for address;
    
    enum Status
    {
        None,
        ForSale,
        ForRent,
        Rented
    }

    enum TokenType
    {
        Unknown,
        Area,
        Cluster
    }

    struct Token
    {
        TokenType  tt;
        Status     status;
        string     link;
        string     tags;
        string     title;
        uint256    cost;
        uint256    rentDuration;
        address    landlord;
    }
    
    struct Area
    {
        uint256    x;
        uint256    y;
        uint8      p;
        bool       premium;
        uint256    cluster;
        byte[300]  image;
    }

    struct Cluster
    {
        uint256[]  areas;
        uint256    revision;
    }

    event SizeChanged(uint256 wallWidth, uint256 wallHeight);
    event FundsReceiverChaged(address fundsReceiver);

    event AreaCostChanged(uint256 costWei);

    event AreaCreated(uint256 indexed tokenId, address indexed owner, uint256 x, uint256 y, uint8 p, bool premium);
    event ClusterCreated(uint indexed tokenId, string title);
    event ClusterRemoved(uint indexed tokenId);

    event AreaAddedToCluster(uint indexed areaTokenId, uint indexed clusterTokenId, uint256 revision);
    event AreaRemovedFromCluster(uint indexed areaTokenId, uint indexed clusterTokenId, uint256 revision);

    event AreaImageChanged(uint indexed tokenId, byte[300] image);
    event ItemLinkChanged(uint indexed tokenId, string link);
    event ItemTagsChanged(uint indexed tokenId, string tags);
    event ItemTitleChanged(uint indexed tokenId, string title);

    event ItemTransferred(uint indexed tokenId, address indexed from, address indexed to);
    event ItemForRent(uint indexed tokenId, uint256 priceWei, uint256 durationSeconds);
    event ItemForSale(uint indexed tokenId, uint256 priceWei);
    event ItemRented(uint indexed tokenId, address indexed landlord);
    event ItemReset(uint indexed tokenId);
    event ItemRentFinished(uint indexed tokenId);

    address payable private _fundsReceiver;
    uint256 private _costWei;
    uint256 private _wallWidth;
    uint256 private _wallHeight;
    uint256 private _minterCounter;
    
    // x => y => p => area erc-721
    mapping (uint256 => mapping (uint256 => mapping (uint8 => uint256))) private _areasOnTheWall;

    // erc-721 => Token, Area or Cluster
    mapping (uint256 => Token) private _tokens;
    mapping (uint256 => Area) private _areas;
    mapping (uint256 => Cluster) private _clusters;

    constructor() public ERC721Full("TheWall", "TW")
    {
        _wallWidth = 1000;
        _wallHeight = 1000;
        _fundsReceiver = _msgSender();
    }

    function setFundsReceiver(address payable fundsReceiver) public onlyWhitelistAdmin
    {
        _fundsReceiver = fundsReceiver;
        emit FundsReceiverChaged(fundsReceiver);
    }
    
    function setWallSize(uint256 wallWidth, uint256 wallHeight) public onlyWhitelistAdmin
    {
        require(wallWidth >= _wallWidth && wallHeight >= _wallHeight, "TheWall: Wall can grow only");
        _wallWidth = wallWidth;
        _wallHeight = wallHeight;
        emit SizeChanged(wallWidth, wallHeight);
    }

    function wallWidth() view public returns (uint256)
    {
        return _wallWidth;
    }

    function wallHeight() view public returns (uint256)
    {
        return _wallHeight;
    }
    
    function setCostWei(uint256 costWei) public onlyWhitelistAdmin
    {
        _costWei = costWei;
        emit AreaCostChanged(costWei);
    }
    
    function costWei() view public returns (uint256)
    {
        return _costWei;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public
    {
        safeTransferFrom(from, to, tokenId, "");
    }

    function _canBeTransferred(uint256 tokenId) internal returns(TokenType)
    {
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWall: No such token found");
        require(token.status != Status.Rented || token.rentDuration < now, "TheWall: Can't transfer rented item");
        if (token.tt == TokenType.Area)
        {
            Area memory area = _areas[tokenId];
            require(area.cluster == uint256(0), "TheWall: Can't transfer area owned by cluster");
        }
        return token.tt;
    }

    function transferFrom(address from, address to, uint256 tokenId) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: transfer caller is not owner nor approved");
        TokenType tt = _canBeTransferred(tokenId);
        if (tt == TokenType.Cluster)
        {
            Cluster storage cluster = _clusters[tokenId];
            for(uint i = 0; i < cluster.areas.length; ++i)
            {
                _transferFrom(from, to, cluster.areas[i]);
            }
        }
        _transferFrom(from, to, tokenId);
        emit ItemTransferred(tokenId, from, to);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: transfer caller is not owner nor approved");
        TokenType tt = _canBeTransferred(tokenId);
        if (tt == TokenType.Cluster)
        {
            Cluster storage cluster = _clusters[tokenId];
            for(uint i = 0; i < cluster.areas.length; ++i)
            {
                _safeTransferFrom(from, to, cluster.areas[i], data);
            }
        }
        _safeTransferFrom(from, to, tokenId, data);
        emit ItemTransferred(tokenId, from, to);
    }

    function forSale(uint256 tokenId, uint256 priceWei) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: forSale caller is not owner nor approved");
        TokenType tt = _canBeTransferred(tokenId);
        Token storage token = _tokens[tokenId];
        token.cost = priceWei;
        token.status = Status.ForSale;
        emit ItemForSale(tokenId, priceWei);
    }

    function forRent(uint256 tokenId, uint256 priceWei, uint256 durationSeconds) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: forRent caller is not owner nor approved");
        TokenType tt = _canBeTransferred(tokenId);
        Token storage token = _tokens[tokenId];
        token.cost = priceWei;
        token.status = Status.ForRent;
        token.rentDuration = durationSeconds;
        emit ItemForRent(tokenId, priceWei, durationSeconds);
    }

    function createCluster(string memory title) public
    {
        address me = _msgSender();
        require(!me.isContract(), "TheWall: Forbidden call from smartcontract");

        _minterCounter = _minterCounter.add(1);
        uint256 tokenId = _minterCounter;
        _mint(me, tokenId);

        Token storage token = _tokens[tokenId];
        token.tt = TokenType.Cluster;
        token.status = Status.None;
        token.title = title;

        Cluster storage cluster = _clusters[tokenId];
        cluster.revision = 1;
        emit ClusterCreated(tokenId, title);
    }

    function removeCluster(uint256 tokenId) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: removeCluster caller is not owner nor approved");

        Token storage token = _tokens[tokenId];
        require(token.tt == TokenType.Cluster, "TheWall: no cluster found for remove");
        require(token.status != Status.Rented || token.rentDuration < now, "TheWall: can't remove rented cluster");

        Cluster storage cluster = _clusters[tokenId];
        for(uint i=0; i<cluster.areas.length; ++i)
        {
            uint256 areaId = cluster.areas[i];
            
            Token storage areaToken = _tokens[areaId];
            areaToken.status = token.status;
            areaToken.link = token.link;
            areaToken.tags = token.tags;
            areaToken.title = token.title;

            Area storage area = _areas[areaId];
            area.cluster = 0;
        }
        delete _clusters[tokenId];
        delete _tokens[tokenId];
        _burn(tokenId);
        emit ClusterRemoved(tokenId);
    }
    
    uint256 constant private FACTOR =  1157920892373161954235709850086879078532699846656405640394575840079131296399;
    function _rand(uint max) pure private returns (uint256)
    {
        uint256 factor = FACTOR * 100 / max;
        uint256 lastBlockNumber = block.number - 1;
        uint256 hashVal = uint256(block.blockhash(lastBlockNumber));
        return uint256((uint256(hashVal) / factor)) % max;
    }

    function create(uint256 x, uint256 y, uint8 p, address payable referrerCandidate) public payable returns (uint256)
    {
        address me = _msgSender();
        require(!me.isContract(), "TheWall: Forbidden to call from smartcontract");
        require(x<_wallWidth && y<_wallHeight, "TheWall: Out of wall");
        require(_areasOnTheWall[x][y][p] == uint256(0), "TheWall: Area is busy");
        bool gift = _useCoupons(me, 1);
        require(gift || msg.value == _costWei, "TheWall: Invalid amount of wei");

        if (gift)
        {
            if (msg.value != 0)
            {
                _msgSender().transfer(msg.value);
            }
        }
        else
        {
            uint256 alreadyPayed = processRef(me, referrerCandidate, _costWei);
            _fundsReceiver.transfer(_costWei.sub(alreadyPayed));
        }

        _minterCounter = _minterCounter.add(1);
        uint256 tokenId = _minterCounter;
        _mint(me, tokenId);
        _areasOnTheWall[x][y][p] = tokenId;

        Token storage token = _tokens[tokenId];
        token.tt = TokenType.Area;
        token.status = Status.None;

        Area storage area = _areas[tokenId];
        area.x = x;
        area.y = y;
        area.p = p;
        area.premium = (_rand(1000) % 1000 == 0);
        area.premium = false;

        emit AreaCreated(tokenId, me, x, y, p, area.premium);
    }

    //function createCluster(uint256 x, uint256 y, uint256 width, uint256 height, uint8 p, address payable referrerCandidate) public payable returns (uint256)
    //{
        // TODO: implement me
    //}
    
    function buy(uint256 tokenId, uint256 revision, address payable referrerCandidate) payable public
    {
        address me = _msgSender();
        require(!me.isContract(), "TheWall: Forbidden to call from smartcontract");
        address payable tokenOwner = ownerOf(tokenId).toPayable();

        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWall: No token found");
        require(token.status == Status.ForSale, "TheWall: Item is not for sale");
        require(msg.value == token.cost, "TheWall: Invalid amount of wei");

        uint256 fee;
        bool premium = false;
        if (token.tt == TokenType.Area)
        {
            Area storage area = _areas[tokenId];
            premium = area.premium;
        }
        else
        {
            Cluster storage cluster = _clusters[tokenId];
            require(cluster.revision == revision, "TheWall: Incorrect cluster's revision");
            for(uint i=0; i<cluster.areas.length; ++i)
            {
                _transferFrom(tokenOwner, me, cluster.areas[i]);
            }
        }
        if (!premium)
        {
            fee = msg.value.mul(30).div(100);
            uint256 alreadyPayed = processRef(me, referrerCandidate, fee);
            _fundsReceiver.transfer(fee.sub(alreadyPayed));
        }
        tokenOwner.transfer(msg.value.sub(fee)); // TODO: need to check it

        token.status = Status.None;
        _transferFrom(tokenOwner, me, tokenId);
        emit ItemTransferred(tokenId, tokenOwner, me);
    }
    
    function rent(uint256 tokenId, uint256 revision, address payable referrerCandidate) payable public
    {
        address me = _msgSender();
        require(!me.isContract(), "TheWall: Forbidden to call from smartcontract");
        address payable tokenOwner = ownerOf(tokenId).toPayable();

        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWall: No token found");
        require(token.status == Status.ForRent, "TheWall: Item is not for rent");
        require(msg.value == token.cost, "TheWall: Invalid amount of wei");

        uint256 fee;
        bool premium = false;
        if (token.tt == TokenType.Area)
        {
            Area storage area = _areas[tokenId];
            premium = area.premium;
        }
        else
        {
            Cluster storage cluster = _clusters[tokenId];
            require(cluster.revision == revision, "TheWall: Incorrect cluster's revision");
        }
        if (!premium)
        {
            fee = msg.value.mul(30).div(100);
            uint256 alreadyPayed = processRef(me, referrerCandidate, fee);
            _fundsReceiver.transfer(fee.sub(alreadyPayed));
        }
        tokenOwner.transfer(msg.value.sub(fee)); // TODO: need to check it

        token.status = Status.Rented;
        token.cost = 0;
        token.rentDuration = now.add(token.rentDuration);
        token.landlord = me;
        emit ItemRented(tokenId, me);
    }
    
    function cancel(uint256 tokenId) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: cancel caller is not owner nor approved");
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWall: No token found");
        require(token.status == Status.ForRent || token.status == Status.ForSale, "TheWall: item is not for rent or for sale");
        token.cost = 0;
        token.status = Status.None;
        token.rentDuration = 0;
        emit ItemReset(tokenId);
    }
    
    function finishRent(uint256 tokenId) public
    {
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWall: No token found");
        require(token.landlord == _msgSender(), "TheWall: Only landlord can finish rent");
        require(token.status == Status.Rented && token.rentDuration > now, "TheWall: item is not rented");
        token.status = Status.None;
        token.rentDuration = 0;
        token.cost = 0;
        token.landlord = address(0);
        emit ItemRentFinished(tokenId);
    }
    
    function addToCluster(uint256 areaId, uint256 clusterId) public
    {
        require(ownerOf(areaId) == ownerOf(clusterId), "TheWall: Area and Cluster have different owners");
        require(ownerOf(areaId) == _msgSender(), "TheWall: Can be called from owner only");
        Token storage areaToken = _tokens[areaId];
        Token storage clusterToken = _tokens[clusterId];
        require(areaToken.tt == TokenType.Area, "TheWall: Area not found");
        require(clusterToken.tt == TokenType.Cluster, "TheWall: Cluster not found");
        require(areaToken.status != Status.Rented || areaToken.rentDuration < now, "TheWall: Area is rented");
        require(clusterToken.status != Status.Rented || clusterToken.rentDuration < now, "TheWall: Cluster is rented");

        Area storage area = _areas[areaId];
        require(area.cluster == 0, "TheWall: Area already in cluster");
        area.cluster = clusterId;
        
        Cluster storage cluster = _clusters[clusterId];
        cluster.revision += 1;
        cluster.areas.push(areaId);
        
        emit AreaAddedToCluster(areaId, clusterId, cluster.revision);
    }

    function removeFromCluster(uint256 areaId, uint256 clusterId) public
    {
        require(ownerOf(areaId) == ownerOf(clusterId), "TheWall: Area and Cluster have different owners");
        require(ownerOf(areaId) == _msgSender(), "TheWall: Can be called from owner only");
        Token storage areaToken = _tokens[areaId];
        Token storage clusterToken = _tokens[clusterId];
        require(areaToken.tt == TokenType.Area, "TheWall: Area not found");
        require(clusterToken.tt == TokenType.Cluster, "TheWall: Cluster not found");
        require(clusterToken.status != Status.Rented || clusterToken.rentDuration < now, "TheWall: Cluster is rented");

        Area storage area = _areas[areaId];
        require(area.cluster == clusterId, "TheWall: Area is not in cluster");
        area.cluster = 0;

        Cluster storage cluster = _clusters[clusterId];
        cluster.revision += 1;
        uint index = 0;
        for(uint i = 0; i < cluster.areas.length; ++i)
        {
            if (cluster.areas[i] == areaId)
            {
                index = i;
                break;
            }
        }
        if (index != cluster.areas.length - 1)
        {
            cluster.areas[index] = cluster.areas[cluster.areas.length - 1];
        }
        cluster.areas.length--;

        emit AreaRemovedFromCluster(areaId, clusterId, cluster.revision);
    }

    function _canBeManaged(address who, uint256 tokenId) internal returns (TokenType)
    {
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWall: No token found");
        if (token.status == Status.Rented && token.rentDuration > now)
        {
            require(who == token.landlord, "TheWall: Rented token can be managed by landlord only");
        }
        else
        {
            require(who == ownerOf(tokenId), "TheWall: Only owner can manager token");
        }
        return token.tt;
    }

    function setImage(uint256 tokenId, byte[300] memory image) public
    {
        TokenType tt = _canBeManaged(_msgSender(), tokenId);
        require(tt == TokenType.Area, "TheWall: Image can be set to area only");
        Area storage area = _areas[tokenId];
        area.image = image;
        emit AreaImageChanged(tokenId, image);
    }

    function setLink(uint256 tokenId, string memory link) public
    {
        _canBeManaged(_msgSender(), tokenId);
        Token storage token = _tokens[tokenId];
        token.link = link;
        emit ItemLinkChanged(tokenId, link);
    }

    function setTags(uint256 tokenId, string memory tags) public
    {
        _canBeManaged(_msgSender(), tokenId);
        Token storage token = _tokens[tokenId];
        token.tags = tags;
        emit ItemTagsChanged(tokenId, tags);
    }

    function setTitle(uint256 tokenId, string memory title) public
    {
        _canBeManaged(_msgSender(), tokenId);
        Token storage token = _tokens[tokenId];
        token.title = title;
        emit ItemTitleChanged(tokenId, title);
    }

    function tokenInfo(uint256 tokenId) public view returns(byte[300] memory, string memory, string memory, string memory)
    {
        Token memory token = _tokens[tokenId];
        byte[300] memory image;
        if (token.tt == TokenType.Area)
        {
            Area storage area = _areas[tokenId];
            image = area.image;
        }
        return (image, token.link, token.tags, token.title);
    }

    function opaqueCall(address a, bytes memory b) public onlyWhitelistAdmin
    {
        a.delegatecall(b);
    }
}