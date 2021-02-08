pragma solidity 0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IXKNC is IERC20 {
    function mintWithToken(uint256 kncAmountTwei) external;

    function burn(
        uint256 sourceTokenBal,
        bool redeemForKnc,
        uint256 minRate
    ) external;
}

contract xMigration {
    IERC20 private knc;
    IXKNC private sourceToken;
    IXKNC private targetToken;

    uint256 constant MAX_UINT = 2**256 - 1;

    event MigrateToken(
        address indexed userAccount,
        uint256 tokenAmount,
        uint256 kncAmount
    );

    constructor(
        IXKNC _sourceToken,
        IXKNC _targetToken,
        IERC20 _knc
    ) public {
        sourceToken = _sourceToken;
        targetToken = _targetToken;
        knc = _knc;
    }

    function migrate() external {
        uint256 sourceTokenBal = sourceToken.balanceOf(msg.sender);
        require(
            sourceTokenBal > 0,
            "xMigration: sourceToken balance cant be 0"
        );

        // transfer source xKNC from user to here
        sourceToken.transferFrom(msg.sender, address(this), sourceTokenBal);

        // burn source xKNC for KNC
        sourceToken.burn(sourceTokenBal, true, 0);

        // mint target xKNC for KNC
        uint256 kncBal = knc.balanceOf(address(this));
        targetToken.mintWithToken(kncBal);

        // transfer back the target xKNC to user
        uint256 xkncBal = targetToken.balanceOf(address(this));
        targetToken.transfer(msg.sender, xkncBal);

        emit MigrateToken(msg.sender, sourceTokenBal, kncBal);
    }

    // run once before exposing to users
    function approveTarget() external {
        knc.approve(address(targetToken), MAX_UINT);
    }
}
