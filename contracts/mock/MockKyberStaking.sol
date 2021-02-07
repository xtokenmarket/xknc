pragma solidity 0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockKyberStaking {
    address kncAddress;

    // need to approve first
    function deposit(uint amount) external {
        IERC20(kncAddress).transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint amount) external {
        IERC20(kncAddress).transfer(msg.sender, amount);
    }

    function setKncAddress(address _kncAddress) public {
        kncAddress = _kncAddress;
    }

    function getLatestStakeBalance(address _address) public returns(uint) {
        return IERC20(kncAddress).balanceOf(address(this));
    }
}
