pragma solidity 0.6.2;

contract OldMockKyberDAO {
    function vote(uint campaignID, uint option) external {
        //
    }

    function claimReward(address staker, uint epoch) external {
        //
        msg.sender.transfer(1e16);
    }

    receive() external payable {

    }
}
