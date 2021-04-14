pragma solidity 0.6.2;

interface IRewardsDistributor {
  function claim(
    uint256 cycle,
    uint256 index,
    address user,
    IERC20[] calldata tokens,
    uint256[] calldata cumulativeAmounts,
    bytes32[] calldata merkleProof
  ) external returns (uint256[] memory claimAmounts);
}