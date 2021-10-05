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
// SPDX-License-Identifier: GNU lesser General Public License

pragma solidity ^0.8.0;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/Address.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";


contract TheWallBeneficiaries is ERC20
{
    using SafeMath for uint256;
    using Address for address payable;

    event WithdrawReward(address indexed beneficiary, uint256 amount);
    event DivideUpReward(address indexed beneficiary, uint256 total);

    uint256 private _totalReward;
    uint256 private _lastDivideRewardTime;
    uint256 private _restReward;

    struct Beneficiary
    {
        uint256 balance;
        uint256 balanceUpdateTime;
        uint256 rewardWithdrawTime;
    }
    
    mapping(address => Beneficiary) private _beneficiaries;


    constructor () ERC20("TheWallBeneficiaries", "TWS")
    {
        _mint(_msgSender(), 21000000);
    }
    
    receive() external payable
    {
    }
    
    function decimals() public view virtual override returns (uint8)
    {
        return 0;
    }
    
    function transfer(address recipient, uint256 amount) public override returns (bool)
    {
        beforeBalanceChanges(recipient);
        beforeBalanceChanges(_msgSender());
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool)
    {
        beforeBalanceChanges(sender);
        beforeBalanceChanges(recipient);
        return super.transferFrom(sender, recipient, amount);
    }

    function reward() view public returns(uint256)
    {
        address s = _msgSender();
        if (_beneficiaries[s].rewardWithdrawTime >= _lastDivideRewardTime)
        {
            return 0;
        }
        uint256 balance;
        if (_beneficiaries[s].balanceUpdateTime <= _lastDivideRewardTime)
        {
            balance = balanceOf(s);
        }
        else
        {
            balance = _beneficiaries[s].balance;
        }
        return _totalReward.mul(balance).div(totalSupply());
    }

    function withdrawReward() public returns(uint256 value)
    {
        value = reward();
        if (value > 0)
        {
            if (balanceOf(_msgSender()) == 0)
            {
                delete _beneficiaries[_msgSender()];
            }
            else
            {
                _beneficiaries[_msgSender()].rewardWithdrawTime = block.timestamp;
            }
            payable(_msgSender()).sendValue(value);
            emit WithdrawReward(_msgSender(), value);
        }
    }

    function divideUpReward() public
    {
        require(balanceOf(_msgSender()) > 0, "TheWallBeneficiaries: beneficiary only can call devideUpReward");
        require(_lastDivideRewardTime + 30 days < block.timestamp, "TheWallBeneficiaries: too early call");
        _lastDivideRewardTime = block.timestamp;
        _totalReward = address(this).balance;
        _restReward = _totalReward;
        emit DivideUpReward(_msgSender(), _totalReward);
    }

    function beforeBalanceChanges(address who) internal
    {
        if (_beneficiaries[who].balanceUpdateTime <= _lastDivideRewardTime)
        {
            _beneficiaries[who].balanceUpdateTime = block.timestamp;
            _beneficiaries[who].balance = balanceOf(who);
        }
    }
}
