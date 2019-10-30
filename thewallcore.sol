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

import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/roles/WhitelistAdminRole.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/math/SafeMath.sol";


contract TheWallCore is WhitelistAdminRole
{
    using SafeMath for uint256;

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
        int256     x;
        int256     y;
        bool       premium;
        uint256    cluster;
        byte[300]  image;
    }

    struct Cluster
    {
        uint256[]  areas;
        uint256    revision;
    }

    // x => y => area erc-721
    mapping (int256 => mapping (int256 => uint256)) private _areasOnTheWall;

    // erc-721 => Token, Area or Cluster
    mapping (uint256 => Token) private _tokens;
    mapping (uint256 => Area) private _areas;
    mapping (uint256 => Cluster) private _clusters;


    function _canBeTransferred(uint256 tokenId) public view returns(TokenType)
    {
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWallCore: No such token found");
        require(token.status != Status.Rented || token.rentDuration < now, "TheWallCore: Can't transfer rented item");
        if (token.tt == TokenType.Area)
        {
            Area memory area = _areas[tokenId];
            require(area.cluster == uint256(0), "TheWallCore: Can't transfer area owned by cluster");
        }
        return token.tt;
    }

    function _areasInCluster(uint256 clusterId) public view returns(uint256[] memory)
    {
        return _clusters[clusterId].areas;
    }

    function _forSale(uint256 tokenId, uint256 priceWei) onlyWhitelistAdmin public
    {
        _canBeTransferred(tokenId);
        Token storage token = _tokens[tokenId];
        token.cost = priceWei;
        token.status = Status.ForSale;
    }

    function _forRent(uint256 tokenId, uint256 priceWei, uint256 durationSeconds) onlyWhitelistAdmin public
    {
        _canBeTransferred(tokenId);
        Token storage token = _tokens[tokenId];
        token.cost = priceWei;
        token.status = Status.ForRent;
        token.rentDuration = durationSeconds;
    }

    function _createCluster(uint256 tokenId, string memory title) onlyWhitelistAdmin public
    {
        Token storage token = _tokens[tokenId];
        token.tt = TokenType.Cluster;
        token.status = Status.None;
        token.title = title;

        Cluster storage cluster = _clusters[tokenId];
        cluster.revision = 1;
    }

    function _removeCluster(uint256 tokenId) onlyWhitelistAdmin public
    {
        Token storage token = _tokens[tokenId];
        require(token.tt == TokenType.Cluster, "TheWallCore: no cluster found for remove");
        require(token.status != Status.Rented || token.rentDuration < now, "TheWallCore: can't remove rented cluster");

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
    }
    
    uint256 constant private FACTOR =  1157920892373161954235709850086879078532699846656405640394575840079131296399;
    function _rand(uint max) view internal returns (uint256)
    {
        uint256 factor = FACTOR * 100 / max;
        uint256 lastBlockNumber = block.number - 1;
        uint256 hashVal = uint256(blockhash(lastBlockNumber));
        return uint256((uint256(hashVal) / factor)) % max;
    }

    function _abs(int256 v) pure public returns (int256)
    {
        if (v < 0)
        {
            v = -v;
        }
        return v;
    }

    function _create(uint256 tokenId, int256 x, int256 y, uint256 clusterId) onlyWhitelistAdmin public returns (bool premium, uint256 revision)
    {
        _areasOnTheWall[x][y] = tokenId;

        Token storage token = _tokens[tokenId];
        token.tt = TokenType.Area;
        token.status = Status.None;

        Area storage area = _areas[tokenId];
        area.x = x;
        area.y = y;
        if (_abs(x) <= 100 && _abs(y) <= 100)
        {
            area.premium = true;
        }
        else
        {
            area.premium = (_rand(1000) % 1000 == 0);
        }
        premium = area.premium;

        revision = 0;
        if (clusterId !=0)
        {
            area.cluster = clusterId;
        
            Cluster storage cluster = _clusters[clusterId];
            cluster.revision += 1;
            revision = cluster.revision;
            cluster.areas.push(tokenId);
        }
        
        return (premium, revision);
    }

    function _areaOnTheWall(int256 x, int256 y) public view returns(uint256)
    {
        return _areasOnTheWall[x][y];
    }

    function _buy(uint256 tokenId, uint256 weiAmount, uint256 revision) payable onlyWhitelistAdmin public returns(bool premium)
    {
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWallCore: No token found");
        require(token.status == Status.ForSale, "TheWallCore: Item is not for sale");
        require(weiAmount == token.cost, "TheWallCore: Invalid amount of wei");

        premium = false;
        if (token.tt == TokenType.Area)
        {
            Area storage area = _areas[tokenId];
            premium = area.premium;
        }
        else
        {
            Cluster storage cluster = _clusters[tokenId];
            require(cluster.revision == revision, "TheWallCore: Incorrect cluster's revision");
        }
        
        token.status = Status.None;
        return premium;
    }
    
    function _rent(uint256 tokenId, address me, uint256 weiAmount, uint256 revision) payable onlyWhitelistAdmin public returns(bool premium, uint256 rentDuration)
    {
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWallCore: No token found");
        require(token.status == Status.ForRent, "TheWallCore: Item is not for rent");
        require(weiAmount == token.cost, "TheWallCore: Invalid amount of wei");

        premium = false;
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

        rentDuration = now.add(token.rentDuration);
        token.status = Status.Rented;
        token.cost = 0;
        token.rentDuration = rentDuration;
        token.landlord = me;
        return (premium, rentDuration);
    }
    
    function _cancel(uint256 tokenId) onlyWhitelistAdmin public
    {
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWallCore: No token found");
        require(token.status == Status.ForRent || token.status == Status.ForSale, "TheWallCore: item is not for rent or for sale");
        token.cost = 0;
        token.status = Status.None;
        token.rentDuration = 0;
    }
    
    function _finishRent(address who, uint256 tokenId) onlyWhitelistAdmin public
    {
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWallCore: No token found");
        require(token.landlord == who, "TheWall: Only landlord can finish rent");
        require(token.status == Status.Rented && token.rentDuration > now, "TheWallCore: item is not rented");
        token.status = Status.None;
        token.rentDuration = 0;
        token.cost = 0;
        token.landlord = address(0);
    }
    
    function _addToCluster(uint256 areaId, uint256 clusterId) onlyWhitelistAdmin public returns(uint256 revision)
    {
        Token storage areaToken = _tokens[areaId];
        Token storage clusterToken = _tokens[clusterId];
        require(areaToken.tt == TokenType.Area, "TheWallCore: Area not found");
        require(clusterToken.tt == TokenType.Cluster, "TheWallCore: Cluster not found");
        require(areaToken.status != Status.Rented || areaToken.rentDuration < now, "TheWallCore: Area is rented");
        require(clusterToken.status != Status.Rented || clusterToken.rentDuration < now, "TheWallCore: Cluster is rented");

        Area storage area = _areas[areaId];
        require(area.cluster == 0, "TheWallCore: Area already in cluster");
        area.cluster = clusterId;
        
        Cluster storage cluster = _clusters[clusterId];
        cluster.revision += 1;
        cluster.areas.push(areaId);
        return cluster.revision;
    }

    function _removeFromCluster(uint256 areaId, uint256 clusterId) onlyWhitelistAdmin public returns(uint256 revision)
    {
        Token storage areaToken = _tokens[areaId];
        Token storage clusterToken = _tokens[clusterId];
        require(areaToken.tt == TokenType.Area, "TheWallCore: Area not found");
        require(clusterToken.tt == TokenType.Cluster, "TheWallCore: Cluster not found");
        require(clusterToken.status != Status.Rented || clusterToken.rentDuration < now, "TheWallCore: Cluster is rented");

        Area storage area = _areas[areaId];
        require(area.cluster == clusterId, "TheWallCore: Area is not in cluster");
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
        return cluster.revision;
    }

    function _canBeManaged(address who, address owner, uint256 tokenId) internal view returns (TokenType)
    {
        Token storage token = _tokens[tokenId];
        require(token.tt != TokenType.Unknown, "TheWallCore: No token found");
        if (token.status == Status.Rented && token.rentDuration > now)
        {
            require(who == token.landlord, "TheWallCore: Rented token can be managed by landlord only");
        }
        else
        {
            require(who == owner, "TheWallCore: Only owner can manager token");
        }
        return token.tt;
    }

    function _setImage(address who, address owner, uint256 tokenId, byte[300] memory image) onlyWhitelistAdmin public
    {
        TokenType tt = _canBeManaged(who, owner, tokenId);
        require(tt == TokenType.Area, "TheWallCore: Image can be set to area only");
        Area storage area = _areas[tokenId];
        area.image = image;
    }

    function _setLink(address who, address owner, uint256 tokenId, string memory link) onlyWhitelistAdmin public
    {
        _canBeManaged(who, owner, tokenId);
        Token storage token = _tokens[tokenId];
        token.link = link;
    }

    function _setTags(address who, address owner, uint256 tokenId, string memory tags) onlyWhitelistAdmin public
    {
        _canBeManaged(who, owner, tokenId);
        Token storage token = _tokens[tokenId];
        token.tags = tags;
    }

    function _setTitle(address who, address owner, uint256 tokenId, string memory title) onlyWhitelistAdmin public
    {
        _canBeManaged(who, owner, tokenId);
        Token storage token = _tokens[tokenId];
        token.title = title;
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

    function _opaqueCall(address a, bytes memory b) onlyWhitelistAdmin public
    {
        a.delegatecall(b);
    }
}