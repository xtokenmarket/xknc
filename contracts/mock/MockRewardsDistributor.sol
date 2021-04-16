pragma solidity 0.6.2;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

contract MockRewardsDistributor {
    uint[] returnVal;

    function claim(
        uint256 cycle,
        uint256 index,
        address staker,
        IERC20[] calldata tokens,
        uint256[] calldata cumulativeAmounts,
        bytes32[] calldata merkleProof
    ) external returns(uint[] memory) {
        (bool success, ) = staker.call{value: 1e18}('');
        require(success, 'eth transfer failed');

        returnVal.push(1e18);
        return returnVal;
    }

    receive() external payable {
    }
}