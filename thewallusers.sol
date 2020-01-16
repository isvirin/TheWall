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

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/roles/WhitelistAdminRole.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/GSN/Context.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/Address.sol";
import "./thewallcoupons.sol";


contract TheWallUsers is Context, WhitelistAdminRole
{
    using SafeMath for uint256;
    using Address for address payable;

    struct User
    {
        string          nickname;
        bytes           avatar;
        address payable referrer;
    }
    
    TheWallCoupons private _coupons;

    mapping (address => User) public _users;
    
    event NicknameChanged(address indexed user, string nickname);
    event AvatarChanged(address indexed user, bytes avatar);

    event CouponsCreated(address indexed owner, uint256 created);
    event CouponsUsed(address indexed owner, uint256 used);

    event ReferrerChanged(address indexed me, address indexed referrer);
    event ReferralPayment(address indexed referrer, address indexed referral, uint256 amountWei);

    constructor (address coupons) public
    {
        _coupons = TheWallCoupons(coupons);
        _coupons.setTheWallUsers(address(this));
    }

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
    
    function _useCoupons(address owner, uint256 count) internal returns(uint256 used)
    {
        used = _coupons.balanceOf(owner);
        if (count < used)
        {
            used = count;
        }
        if (used > 0)
        {
            _coupons._burn(owner, used);
            emit CouponsUsed(owner, used);
        }
    }

    function giveCoupons(address owner, uint256 count) public onlyWhitelistAdmin
    {
        require(owner != address(0));
        _coupons._mint(owner, count);
        emit CouponsCreated(owner, count);
    }
    
    function giveCouponsMulti(address[] memory owners, uint256 count) public onlyWhitelistAdmin
    {
        for(uint i = 0; i < owners.length; ++i)
        {
            _coupons._mint(owners[i], count);
            emit CouponsCreated(owners[i], count);
        }
    }
    
    function _processRef(address me, address payable referrerCandidate, uint256 amountWei) internal returns(uint256)
    {
        User storage user = _users[me];
        if (referrerCandidate != address(0) && !referrerCandidate.isContract() && user.referrer == address(0))
        {
            user.referrer = referrerCandidate;
            emit ReferrerChanged(me, referrerCandidate);
        }
        
        uint256 alreadyPayed = 0;
        uint256 refPayment = amountWei.mul(6).div(100);

        address payable ref = user.referrer;
        if (ref != address(0))
        {
            ref.sendValue(refPayment);
            alreadyPayed = refPayment;
            emit ReferralPayment(ref, me, refPayment);
            
            ref = _users[ref].referrer;
            if (ref != address(0))
            {
                ref.sendValue(refPayment);
                alreadyPayed = refPayment.mul(2);
                emit ReferralPayment(ref, me, refPayment);
            }
        }
        
        return alreadyPayed;
    }
}