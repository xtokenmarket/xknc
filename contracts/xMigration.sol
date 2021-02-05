pragma solidity 0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IXKNC {
    function mintWithKnc(uint256 kncAmountTwei) external;
    function burn(uint256 sourceTokenBal, bool redeemForKnc, uint256 minRate) external;
}

contract xMigration {

    using SafeERC20 for ERC20;

    ERC20 public knc;
    IXKNC private targetToken;
    IXKNC private sourceToken;
    address private targetTokenAddress;
    address private sourceTokenAddress;

    constructor(
        address _sourceToken,
        address _targetToken,
        address _kyberTokenAddress
    ) public {
        targetTokenAddress = _targetToken;
        sourceTokenAddress = _sourceToken;
        sourceToken = IXKNC(_sourceToken);
        targetToken = IXKNC(_targetToken);
        knc = ERC20(_kyberTokenAddress);
    }

    function migrate() external {
      uint256 sourceTokenBal = ERC20(sourceTokenAddress).balanceOf(msg.sender);
      require(sourceTokenBal > 0,
        "xMigration: sourceToken balance cant be 0");

      // transfer source xKNC from user to here
      ERC20(sourceTokenAddress).safeTransferFrom(
        msg.sender,
        address(this),
        sourceTokenBal
      );

      // burn source xKNC for KNC
      sourceToken.burn(sourceTokenBal, true, 0);

      // mint target xKNC for KNC
      uint256 kncBal = knc.balanceOf(address(this));
      knc.approve(address(targetToken), kncBal);
      targetToken.mintWithKnc(kncBal);

      // transfer back the target xKNC to user
      ERC20(targetTokenAddress).safeTransfer(msg.sender, sourceTokenBal);

      emit MigrateToken(msg.sender, sourceTokenBal, kncBal);
    }

    event MigrateToken(
      address userAccount,
      uint256 tokenAmount,
      uint256 kncAmount
    );

}
