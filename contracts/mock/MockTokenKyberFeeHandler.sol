pragma solidity 0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockTokenKyberFeeHandler {
    IERC20 feeToken;

    constructor(address _tokenAddress) public {
        feeToken = IERC20(_tokenAddress);
    }

    function claimStakerReward(address _address, uint _epoch) external returns(uint tokenBal) {
        tokenBal = feeToken.balanceOf(address(this));
        feeToken.transfer(msg.sender, tokenBal);
    }

    receive() external payable {

    }
}
