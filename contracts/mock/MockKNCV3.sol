pragma solidity 0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockKNCV3 is ERC20 {
    ERC20 oldKnc;

    constructor(ERC20 _oldKnc) public ERC20("Kyber", "KNC") {
        oldKnc = _oldKnc;
        _mint(msg.sender, 10000e18);
    }

    function mintWithOldKnc(uint amount) external {
        oldKnc.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }
}