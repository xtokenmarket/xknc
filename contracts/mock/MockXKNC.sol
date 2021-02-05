pragma solidity 0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./../interface/IKyberStaking.sol";

contract MockXKNC is ERC20 {
  using SafeMath for uint256;
  using SafeERC20 for ERC20;

  ERC20 public knc;
  IKyberStaking public kyberStaking;

  constructor(
      address _kyberStakingAddress,
      address _kyberTokenAddress
  ) public ERC20("xKNC", "xKNCa") {
      kyberStaking = IKyberStaking(_kyberStakingAddress);
      knc = ERC20(_kyberTokenAddress);
      super._mint(msg.sender, 2000e18);
  }

  function burn(
      uint256 tokensToRedeemTwei,
      bool redeemForKnc,
      uint256 minRate
  ) external {
      require(
          balanceOf(msg.sender) >= tokensToRedeemTwei,
          "Insufficient balance"
      );
      uint256 proRataKnc = tokensToRedeemTwei.div(2e18);
      _withdraw(proRataKnc);
      super._burn(msg.sender, tokensToRedeemTwei);
      if (redeemForKnc) {
          uint256 kncBal = knc.balanceOf(address(this));
          knc.safeTransfer(msg.sender, kncBal);
      }
  }

  function _withdraw(uint256 amount) private {
      kyberStaking.withdraw(amount);
  }

}
