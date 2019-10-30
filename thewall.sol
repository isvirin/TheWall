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
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/drafts/SignedSafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/drafts/Strings.sol";
import "./thewallcore.sol";


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
    event CouponsCreated(address indexed owner, uint256 total, uint256 created);
    event CouponsUsed(address indexed owner, uint256 total, uint256 used);
    
    using SafeMath for uint256;
    
    mapping (address => uint256) public _coupons;
    
    function _useCoupons(address owner, uint256 count) internal returns(uint256)
    {
        uint256 used;
        if (count >= _coupons[owner])
        {
            used = _coupons[owner];
            delete _coupons[owner];
        }
        else
        {
            _coupons[owner] -= count;
            used = count;
        }
        if (used > 0)
        {
            emit CouponsUsed(owner, _coupons[owner], used);
        }
        return used;
    }
    
    function giveCoupons(address[] memory owners, uint256 count) public onlyWhitelistAdmin
    {
        for(uint i = 0; i < owners.length; ++i)
        {
            _coupons[owners[i]] = _coupons[owners[i]].add(count);
            emit CouponsCreated(owners[i], _coupons[owners[i]], count);
        }
    }
}

contract RefModel
{
    using SafeMath for uint256;

    event ReferrerChanged(address indexed me, address indexed referrer);
    event ReferralPayment(address indexed referrer, address indexed referral, uint256 amountWei);

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
            emit ReferralPayment(ref, me, refPayment);
            
            ref = _referrers[ref];
            if (ref != address(0))
            {
                ref.transfer(refPayment);
                alreadyPayed = refPayment.mul(2);
                emit ReferralPayment(ref, me, refPayment);
            }
        }
        
        return alreadyPayed;
    }
}


contract TheWall is ERC721Full, WhitelistAdminRole, RefModel, Users, Marketing
{
    using Address for address;
    using SignedSafeMath for int256;
    using Strings for uint256;

    event SizeChanged(int256 wallWidth, int256 wallHeight);
    event FundsReceiverChanged(address fundsReceiver);
    event Payment(address indexed sender, uint256 amountWei);

    event AreaCostChanged(uint256 costWei);

    event AreaCreated(uint256 indexed tokenId, address indexed owner, int256 x, int256 y, bool premium);
    event ClusterCreated(uint indexed tokenId, address indexed owner, string title);
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
    event ItemRented(uint indexed tokenId, address indexed landlord, uint256 finishTime);
    event ItemReset(uint indexed tokenId);
    event ItemRentFinished(uint indexed tokenId);

    TheWallCore private _core;
    address payable private _fundsReceiver;
    uint256 private _costWei;
    int256  private _wallWidth;
    int256  private _wallHeight;
    uint256 private _minterCounter;
    string  private _baseTokenURI;
    

    constructor(address core) public ERC721Full("TheWall", "TW")
    {
        _core = TheWallCore(core);
        _wallWidth = 1000;
        _wallHeight = 1000;
        _costWei = 1 ether / 10;
        _baseTokenURI = "https://thewall.global/erc721/";
        _fundsReceiver = _msgSender();
    }

    function setFundsReceiver(address payable fundsReceiver) public onlyWhitelistAdmin
    {
        _fundsReceiver = fundsReceiver;
        emit FundsReceiverChanged(fundsReceiver);
    }
    
    function setWallSize(int256 wallWidth, int256 wallHeight) public onlyWhitelistAdmin
    {
        require(wallWidth >= _wallWidth && wallHeight >= _wallHeight, "TheWall: Wall can grow only");
        _wallWidth = wallWidth;
        _wallHeight = wallHeight;
        emit SizeChanged(wallWidth, wallHeight);
    }

    function wallWidth() view public returns (int256)
    {
        return _wallWidth;
    }

    function wallHeight() view public returns (int256)
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

    function setBaseTokenURI(string memory uri) public onlyWhitelistAdmin
    {
        _baseTokenURI = uri;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory)
    {
        require(_exists(tokenId), "TheWall: URI query for nonexistent token");
        return string(abi.encodePacked(_baseTokenURI, tokenId.fromUint256()));
    }

    function transferFrom(address from, address to, uint256 tokenId) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: transfer caller is not owner nor approved");
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
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: transfer caller is not owner nor approved");
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
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: forSale caller is not owner nor approved");
        _core._forSale(tokenId, priceWei);
        emit ItemForSale(tokenId, priceWei);
    }

    function forRent(uint256 tokenId, uint256 priceWei, uint256 durationSeconds) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: forRent caller is not owner nor approved");
        _core._forRent(tokenId, priceWei, durationSeconds);
        emit ItemForRent(tokenId, priceWei, durationSeconds);
    }

    function createCluster(string memory title) public returns (uint256)
    {
        address me = _msgSender();
        require(!me.isContract(), "TheWall: Forbidden call from smartcontract");

        _minterCounter = _minterCounter.add(1);
        uint256 tokenId = _minterCounter;
        _mint(me, tokenId);
        _core._createCluster(tokenId, title);

        emit ClusterCreated(tokenId, me, title);
        return tokenId;
    }

    function removeCluster(uint256 tokenId) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: removeCluster caller is not owner nor approved");
        _core._removeCluster(tokenId);
        _burn(tokenId);
        emit ClusterRemoved(tokenId);
    }
    
    function _create(address owner, int256 x, int256 y, uint256 clusterId) internal returns (uint256)
    {
        _minterCounter = _minterCounter.add(1);
        uint256 tokenId = _minterCounter;
        _mint(owner, tokenId);
        
        bool premium;
        uint256 revision;
        (premium, revision) = _core._create(tokenId, x, y, clusterId);
        
        emit AreaCreated(tokenId, owner, x, y, premium);
        if (clusterId != 0)
        {
            emit AreaAddedToCluster(tokenId, clusterId, revision);
        }
        
        return tokenId;
    }

    function create(int256 x, int256 y, address payable referrerCandidate) public payable returns (uint256)
    {
        address me = _msgSender();
        require(!me.isContract(), "TheWall: Forbidden to call from smartcontract");
        require(_core._abs(x) < _wallWidth && _core._abs(y) < _wallHeight, "TheWall: Out of wall");
        require(_core._areaOnTheWall(x, y) == uint256(0), "TheWall: Area is busy");
        bool gift = (_useCoupons(me, 1) == 1);
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
            emit Payment(me, msg.value);
        }
        return _create(me, x, y, 0);
    }

    function createMulti(int256 x, int256 y, int256 width, int256 height, address payable referrerCandidate) public payable returns (uint256)
    {
        address me = _msgSender();
        require(!me.isContract(), "TheWall: Forbidden to call from smartcontract");
        require(_core._abs(x) < _wallWidth && _core._abs(y) < _wallHeight, "TheWall: Out of wall");
        require(_core._abs(x.add(width)) < _wallWidth && _core._abs(y.add(height)) < _wallHeight, "TheWall: Out of wall 2");
        require(width > 0 && height > 0, "TheWall: dimensions must be greater than zero");

        uint256 areasNum = 0;
        int256 i;
        int256 j;
        for(i = 0; i < width; ++i)
        {
            for(j = 0; j < height; ++j)
            {
                if (_core._areaOnTheWall(x ,y) == uint256(0))
                {
                    areasNum = areasNum.add(1);
                }
            }
        }
        require(areasNum > 0, "TheWall: All areas inside are busy");
        
        uint256 usedCoupons = _useCoupons(me, areasNum);
        areasNum -= usedCoupons;

        uint256 costMulti = _costWei.mul(areasNum);
        require(costMulti <= msg.value, "TheWall: Invalid amount of wei");
        if (msg.value > costMulti)
        {
            _msgSender().transfer(msg.value.sub(costMulti));
        }

        if (costMulti > 0)
        {
            uint256 alreadyPayed = processRef(me, referrerCandidate, costMulti);
            _fundsReceiver.transfer(costMulti.sub(alreadyPayed));
            emit Payment(me, costMulti);
        }

        uint256 cluster = createCluster("");
        for(i = 0; i < width; ++i)
        {
            for(j = 0; j < height; ++j)
            {
                if (_core._areaOnTheWall(x, y) == uint256(0))
                {
                    _create(me, x + i, y + j, cluster);
                }
            }
        }
    }

    function buy(uint256 tokenId, uint256 revision, address payable referrerCandidate) payable public
    {
        address me = _msgSender();
        require(!me.isContract(), "TheWall: Forbidden to call from smartcontract");
        address payable tokenOwner = ownerOf(tokenId).toPayable();

        uint256 fee;
        bool premium = _core._buy(tokenId, msg.value, revision);
        emit Payment(me, msg.value);
        uint256[] memory tokens = _core._areasInCluster(tokenId);
        for(uint i = 0; i < tokens.length; ++i)
        {
            _transferFrom(tokenOwner, me, tokens[i]);
        }
        if (!premium)
        {
            fee = msg.value.mul(30).div(100);
            uint256 alreadyPayed = processRef(me, referrerCandidate, fee);
            _fundsReceiver.transfer(fee.sub(alreadyPayed));
        }
        tokenOwner.transfer(msg.value.sub(fee)); // TODO: need to check it
        _transferFrom(tokenOwner, me, tokenId);
        emit ItemTransferred(tokenId, tokenOwner, me);
    }

    function rent(uint256 tokenId, uint256 revision, address payable referrerCandidate) payable public
    {
        address me = _msgSender();
        require(!me.isContract(), "TheWall: Forbidden to call from smartcontract");
        address payable tokenOwner = ownerOf(tokenId).toPayable();

        uint256 fee;
        bool premium;
        uint256 rentDuration;
        (premium, rentDuration) = _core._rent(tokenId, me, msg.value, revision);
        emit Payment(me, msg.value);
        if (!premium)
        {
            fee = msg.value.mul(30).div(100);
            uint256 alreadyPayed = processRef(me, referrerCandidate, fee);
            _fundsReceiver.transfer(fee.sub(alreadyPayed));
        }
        tokenOwner.transfer(msg.value.sub(fee)); // TODO: need to check it
        emit ItemRented(tokenId, me, rentDuration);
    }
    
    function cancel(uint256 tokenId) public
    {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "TheWall: cancel caller is not owner nor approved");
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
        require(ownerOf(areaId) == ownerOf(clusterId), "TheWall: Area and Cluster have different owners");
        require(ownerOf(areaId) == _msgSender(), "TheWall: Can be called from owner only");
        uint256 revision = _core._addToCluster(areaId, clusterId);
        emit AreaAddedToCluster(areaId, clusterId, revision);
    }

    function removeFromCluster(uint256 areaId, uint256 clusterId) public
    {
        require(ownerOf(areaId) == ownerOf(clusterId), "TheWall: Area and Cluster have different owners");
        require(ownerOf(areaId) == _msgSender(), "TheWall: Can be called from owner only");
        uint256 revision = _core._removeFromCluster(areaId, clusterId);
        emit AreaRemovedFromCluster(areaId, clusterId, revision);
    }

    function setImage(uint256 tokenId, byte[300] memory image) public
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

    function tokenInfo(uint256 tokenId) public view returns(byte[300] memory, string memory, string memory, string memory)
    {
        return _core.tokenInfo(tokenId);
    }

    function opaqueCall(address a, bytes memory b) public onlyWhitelistAdmin
    {
        a.delegatecall(b);
    }
}