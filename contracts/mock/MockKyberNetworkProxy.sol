pragma solidity 0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract MockKyberNetworkProxy {
    using SafeMath for uint256;

    address private kncAddress;
    // ETH = $200
    // KNC = $1
    address private ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function getExpectedRate(ERC20 src, ERC20 dest, uint srcQty) external view returns (uint expectedRate, uint slippageRate) {
        if (src == ERC20(ETH_ADDRESS) && dest == ERC20(kncAddress)){
            return (200e18, 200e18);
        }
    }

    // swap ether to knc
    // must send knc to contract first
    function swapEtherToToken(ERC20 token, uint minConversionRate) external payable returns(uint) {
        uint kncToSend = msg.value.mul(200e18).div(1e18);
        IERC20(kncAddress).transfer(msg.sender, kncToSend);
    }

    // swap knc to ether
    // must send eth to contract first
    function swapTokenToEther(ERC20 token, uint tokenQty, uint minRate) external payable returns(uint) {
        uint ethToSend = tokenQty.div(200);
        (bool success, ) = msg.sender.call.value(ethToSend)("");
    }


    // swap tokem to knc
    // must send knc to contract first
    function swapTokenToToken(ERC20 src, uint srcAmount, ERC20 dest, uint minRate) external returns(uint) {
        uint kncToSend = 1000000000;
        IERC20(kncAddress).transfer(msg.sender, kncToSend);
    }

    function setKncAddress(address _kncAddress) public {
        kncAddress = _kncAddress;
    }
}
