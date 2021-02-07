pragma solidity 0.6.2;

interface IKyberDAO {
    function vote(uint256 campaignID, uint256 option) external;
}
