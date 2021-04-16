pragma solidity 0.6.2;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";

import "../interface/IKyberNetworkProxy.sol";
import "../interface/IKyberStaking.sol";
import "../interface/IKyberFeeHandler.sol";

interface IKyberDAO {
    function vote(uint256 campaignID, uint256 option) external;
}


/*
 * xKNC KyberDAO Pool Token
 * Communal Staking Pool with Stated Governance Position
 */
contract xKNCv1 is
    Initializable,
    ERC20UpgradeSafe,
    OwnableUpgradeSafe,
    PausableUpgradeSafe,
    ReentrancyGuardUpgradeSafe
{
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    address private constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    ERC20 private knc;
    IKyberDAO private kyberDao;
    IKyberStaking private kyberStaking;
    IKyberNetworkProxy private kyberProxy;
    IKyberFeeHandler[] private kyberFeeHandlers;

    address[] private kyberFeeTokens;

    uint256 private constant PERCENT = 100;
    uint256 private constant MAX_UINT = 2**256 - 1;
    uint256 private constant INITIAL_SUPPLY_MULTIPLIER = 10;

    uint256 private withdrawableEthFees;
    uint256 private withdrawableKncFees;

    string public mandate;

    address private manager;
    address private manager2;

    struct FeeDivisors {
        uint256 mintFee;
        uint256 burnFee;
        uint256 claimFee;
    }

    FeeDivisors public feeDivisors;

    event FeeDivisorsSet(uint256 mintFee, uint256 burnFee, uint256 claimFee);

    enum FeeTypes {MINT, BURN, CLAIM}

    function initialize(
        string memory _symbol,
        string memory _mandate,
        IKyberStaking _kyberStaking,
        IKyberNetworkProxy _kyberProxy,
        ERC20 _knc,
        IKyberDAO _kyberDao,
        uint256 mintFee,
        uint256 burnFee,
        uint256 claimFee
    ) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ERC20_init_unchained("xKNC", _symbol);

        mandate = _mandate;
        kyberStaking = _kyberStaking;
        kyberProxy = _kyberProxy;
        knc = _knc;
        kyberDao = _kyberDao;

        _setFeeDivisors(mintFee, burnFee, claimFee);
    }

    /*
     * @notice Called by users buying with ETH
     * @dev Swaps ETH for KNC, deposits to Staking contract
     * @dev: Mints pro rata xKNC tokens
     * @param: kyberProxy.getExpectedRate(eth => knc)
     */
    function mint(uint256 minRate) external payable whenNotPaused {
        require(msg.value > 0, "Must send eth with tx");
        // ethBalBefore checked in case of eth still waiting for exch to KNC
        uint256 ethBalBefore = getFundEthBalanceWei().sub(msg.value);
        uint256 fee = _administerEthFee(FeeTypes.MINT, ethBalBefore);

        uint256 ethValueForKnc = msg.value.sub(fee);
        uint256 kncBalanceBefore = getFundKncBalanceTwei();

        _swapEtherToKnc(ethValueForKnc, minRate);
        _deposit(getAvailableKncBalanceTwei());

        uint256 mintAmount = _calculateMintAmount(kncBalanceBefore);

        return super._mint(msg.sender, mintAmount);
    }

    /*
     * @notice Called by users buying with KNC
     * @notice Users must submit ERC20 approval before calling
     * @dev Deposits to Staking contract
     * @dev: Mints pro rata xKNC tokens
     * @param: Number of KNC to contribue
     */
    function mintWithToken(uint256 kncAmountTwei) external whenNotPaused {
        require(kncAmountTwei > 0, "Must contribute KNC");
        knc.safeTransferFrom(msg.sender, address(this), kncAmountTwei);

        uint256 kncBalanceBefore = getFundKncBalanceTwei();
        _administerKncFee(kncAmountTwei, FeeTypes.MINT);

        _deposit(getAvailableKncBalanceTwei());

        uint256 mintAmount = _calculateMintAmount(kncBalanceBefore);

        return super._mint(msg.sender, mintAmount);
    }

    /*
     * @notice Called by users burning their xKNC
     * @dev Calculates pro rata KNC and redeems from Staking contract
     * @dev: Exchanges for ETH if necessary and pays out to caller
     * @param tokensToRedeem
     * @param redeemForKnc bool: if true, redeem for KNC; otherwise ETH
     * @param kyberProxy.getExpectedRate(knc => eth)
     */
    function burn(
        uint256 tokensToRedeemTwei,
        bool redeemForKnc,
        uint256 minRate
    ) external nonReentrant {
        require(
            balanceOf(msg.sender) >= tokensToRedeemTwei,
            "Insufficient balance"
        );

        uint256 proRataKnc =
            getFundKncBalanceTwei().mul(tokensToRedeemTwei).div(totalSupply());
        _withdraw(proRataKnc);
        super._burn(msg.sender, tokensToRedeemTwei);

        if (redeemForKnc) {
            uint256 fee = _administerKncFee(proRataKnc, FeeTypes.BURN);
            knc.safeTransfer(msg.sender, proRataKnc.sub(fee));
        } else {
            // safeguard to not overcompensate _burn sender in case eth still awaiting for exch to KNC
            uint256 ethBalBefore = getFundEthBalanceWei();
            kyberProxy.swapTokenToEther(
                knc,
                getAvailableKncBalanceTwei(),
                minRate
            );

            _administerEthFee(FeeTypes.BURN, ethBalBefore);

            uint256 valToSend = getFundEthBalanceWei().sub(ethBalBefore);
            (bool success, ) = msg.sender.call.value(valToSend)("");
            require(success, "Burn transfer failed");
        }
    }

    /*
     * @notice Calculates proportional issuance according to KNC contribution
     * @notice Fund starts at ratio of INITIAL_SUPPLY_MULTIPLIER/1 == xKNC supply/KNC balance
     * and approaches 1/1 as rewards accrue in KNC
     * @param kncBalanceBefore used to determine ratio of incremental to current KNC
     */
    function _calculateMintAmount(uint256 kncBalanceBefore)
        private
        view
        returns (uint256 mintAmount)
    {
        uint256 kncBalanceAfter = getFundKncBalanceTwei();
        if (totalSupply() == 0)
            return kncBalanceAfter.mul(INITIAL_SUPPLY_MULTIPLIER);

        mintAmount = (kncBalanceAfter.sub(kncBalanceBefore))
            .mul(totalSupply())
            .div(kncBalanceBefore);
    }

    /*
     * @notice KyberDAO deposit
     */
    function _deposit(uint256 amount) private {
        kyberStaking.deposit(amount);
    }

    /*
     * @notice KyberDAO withdraw
     */
    function _withdraw(uint256 amount) private {
        kyberStaking.withdraw(amount);
    }

    /*
     * @notice Vote on KyberDAO campaigns
     * @dev Admin calls with relevant params for each campaign in an epoch
     * @param DAO campaign ID
     * @param Choice of voting option
     */
    function vote(uint256 campaignID, uint256 option)
        external
        onlyOwnerOrManager
    {
        kyberDao.vote(campaignID, option);
    }

    /*
     * @notice Claim reward from previous epoch
     * @notice All fee handlers should be called at once
     * @dev Admin calls with relevant params
     * @dev ETH/other asset rewards swapped into KNC
     * @param epoch - KyberDAO epoch
     * @param feeHandlerIndices - indices of feeHandler contract to claim from
     * @param maxAmountsToSell - sellAmount above which slippage would be too high
     * and rewards would redirected into KNC in multiple trades
     * @param minRates - kyberProxy.getExpectedRate(eth/token => knc)
     */
    function claimReward(
        uint256 epoch,
        uint256[] calldata feeHandlerIndices,
        uint256[] calldata maxAmountsToSell,
        uint256[] calldata minRates
    ) external onlyOwnerOrManager {
        require(
            feeHandlerIndices.length == maxAmountsToSell.length,
            "Arrays must be equal length"
        );
        require(
            maxAmountsToSell.length == minRates.length,
            "Arrays must be equal length"
        );

        uint256 ethBalBefore = getFundEthBalanceWei();
        for (uint256 i = 0; i < feeHandlerIndices.length; i++) {
            kyberFeeHandlers[i].claimStakerReward(address(this), epoch);

            if (kyberFeeTokens[i] == ETH_ADDRESS) {
                _administerEthFee(FeeTypes.CLAIM, ethBalBefore);
            }

            _unwindRewards(
                feeHandlerIndices[i],
                maxAmountsToSell[i],
                minRates[i]
            );
        }

        _deposit(getAvailableKncBalanceTwei());
    }

    /*
     * @notice Called when rewards size is too big for the one trade executed by `claimReward`
     * @param feeHandlerIndices - index of feeHandler previously claimed from
     * @param maxAmountsToSell - sellAmount above which slippage would be too high
     * and rewards would redirected into KNC in multiple trades
     * @param minRates - kyberProxy.getExpectedRate(eth/token => knc)
     */
    function unwindRewards(
        uint256[] calldata feeHandlerIndices,
        uint256[] calldata maxAmountsToSell,
        uint256[] calldata minRates
    ) external onlyOwnerOrManager {
        for (uint256 i = 0; i < feeHandlerIndices.length; i++) {
            _unwindRewards(
                feeHandlerIndices[i],
                maxAmountsToSell[i],
                minRates[i]
            );
        }

        _deposit(getAvailableKncBalanceTwei());
    }

    /*
     * @notice Exchanges reward tokens (ETH, etc) for KNC
     */
    function _unwindRewards(
        uint256 feeHandlerIndex,
        uint256 maxAmountToSell,
        uint256 minRate
    ) private {
        address rewardTokenAddress = kyberFeeTokens[feeHandlerIndex];

        uint256 amountToSell;
        if (rewardTokenAddress == ETH_ADDRESS) {
            uint256 ethBal = getFundEthBalanceWei();
            if (maxAmountToSell < ethBal) {
                amountToSell = maxAmountToSell;
            } else {
                amountToSell = ethBal;
            }

            _swapEtherToKnc(amountToSell, minRate);
        } else {
            uint256 tokenBal =
                IERC20(rewardTokenAddress).balanceOf(address(this));
            if (maxAmountToSell < tokenBal) {
                amountToSell = maxAmountToSell;
            } else {
                amountToSell = tokenBal;
            }

            uint256 kncBalanceBefore = getAvailableKncBalanceTwei();

            _swapTokenToKnc(rewardTokenAddress, amountToSell, minRate);

            uint256 kncBalanceAfter = getAvailableKncBalanceTwei();
            _administerKncFee(
                kncBalanceAfter.sub(kncBalanceBefore),
                FeeTypes.CLAIM
            );
        }
    }

    function _swapEtherToKnc(uint256 amount, uint256 minRate) private {
        kyberProxy.swapEtherToToken.value(amount)(knc, minRate);
    }

    function _swapTokenToKnc(
        address fromAddress,
        uint256 amount,
        uint256 minRate
    ) private {
        kyberProxy.swapTokenToToken(ERC20(fromAddress), amount, knc, minRate);
    }

    /*
     * @notice Returns ETH balance belonging to the fund
     */
    function getFundEthBalanceWei() public view returns (uint256) {
        return address(this).balance.sub(withdrawableEthFees);
    }

    /*
     * @notice Returns KNC balance staked to DAO
     */
    function getFundKncBalanceTwei() public view returns (uint256) {
        return kyberStaking.getLatestStakeBalance(address(this));
    }

    /*
     * @notice Returns KNC balance available to stake
     */
    function getAvailableKncBalanceTwei() public view returns (uint256) {
        return knc.balanceOf(address(this)).sub(withdrawableKncFees);
    }

    function _administerEthFee(FeeTypes _type, uint256 ethBalBefore)
        private
        returns (uint256 fee)
    {
        uint256 feeRate = getFeeRate(_type);
        if (feeRate == 0) return 0;

        fee = (getFundEthBalanceWei().sub(ethBalBefore)).div(feeRate);
        withdrawableEthFees = withdrawableEthFees.add(fee);
    }

    function _administerKncFee(uint256 _kncAmount, FeeTypes _type)
        private
        returns (uint256 fee)
    {
        uint256 feeRate = getFeeRate(_type);
        if (feeRate == 0) return 0;

        fee = _kncAmount.div(feeRate);
        withdrawableKncFees = withdrawableKncFees.add(fee);
    }

    function getFeeRate(FeeTypes _type) public view returns (uint256) {
        if (_type == FeeTypes.MINT) return feeDivisors.mintFee;
        if (_type == FeeTypes.BURN) return feeDivisors.burnFee;
        if (_type == FeeTypes.CLAIM) return feeDivisors.claimFee;
    }

    /*
     * @notice Called on initial deployment and on the addition of new fee handlers
     * @param Address of KyberFeeHandler contract
     * @param Address of underlying rewards token
     */
    function addKyberFeeHandler(
        address _kyberfeeHandlerAddress,
        address _tokenAddress
    ) external onlyOwnerOrManager {
        kyberFeeHandlers.push(IKyberFeeHandler(_kyberfeeHandlerAddress));
        kyberFeeTokens.push(_tokenAddress);

        if (_tokenAddress != ETH_ADDRESS) {
            _approveKyberProxyContract(_tokenAddress, false);
        }
    }

    /* UTILS */

    /*
     * @notice Called by admin on deployment
     * @dev Approves Kyber Staking contract to deposit KNC
     * @param Pass _reset as true if resetting allowance to zero
     */
    function approveStakingContract(bool _reset) external onlyOwnerOrManager {
        uint256 amount = _reset ? 0 : MAX_UINT;
        knc.approve(address(kyberStaking), amount);
    }

    /*
     * @notice Called by admin on deployment for KNC
     * @dev Approves Kyber Proxy contract to trade KNC
     * @param Token to approve on proxy contract
     * @param Pass _reset as true if resetting allowance to zero
     */
    function approveKyberProxyContract(address _token, bool _reset)
        external
        onlyOwnerOrManager
    {
        _approveKyberProxyContract(_token, _reset);
    }

    function _approveKyberProxyContract(address _token, bool _reset) private {
        uint256 amount = _reset ? 0 : MAX_UINT;
        IERC20(_token).approve(address(kyberProxy), amount);
    }

    /*
     * @notice Called by admin on deployment
     * @dev (1 / feeDivisor) = % fee on mint, burn, ETH claims
     * @dev ex: A feeDivisor of 334 suggests a fee of 0.3%
     * @param feeDivisors[mint, burn, claim]:
     */
    function setFeeDivisors(
        uint256 _mintFee,
        uint256 _burnFee,
        uint256 _claimFee
    ) external onlyOwner {
        _setFeeDivisors(_mintFee, _burnFee, _claimFee);
    }

    function _setFeeDivisors(
        uint256 _mintFee,
        uint256 _burnFee,
        uint256 _claimFee
    ) private {
        require(
            _mintFee >= 100 || _mintFee == 0,
            "Mint fee must be zero or equal to or less than 1%"
        );
        require(_burnFee >= 100, "Burn fee must be equal to or less than 1%");
        require(_claimFee >= 10, "Claim fee must be less than 10%");
        feeDivisors.mintFee = _mintFee;
        feeDivisors.burnFee = _burnFee;
        feeDivisors.claimFee = _claimFee;

        emit FeeDivisorsSet(_mintFee, _burnFee, _claimFee);
    }

    function withdrawFees() external onlyOwner {
        uint256 ethFees = withdrawableEthFees;
        uint256 kncFees = withdrawableKncFees;

        withdrawableEthFees = 0;
        withdrawableKncFees = 0;

        (bool success, ) = msg.sender.call.value(ethFees)("");
        require(success, "Burn transfer failed");

        knc.safeTransfer(owner(), kncFees);
    }

    function setManager(address _manager) external onlyOwner {
        manager = _manager;
    }

    function setManager2(address _manager2) external onlyOwner {
        manager2 = _manager2;
    }

    function pause() external onlyOwnerOrManager {
        _pause();
    }

    function unpause() external onlyOwnerOrManager {
        _unpause();
    }

    modifier onlyOwnerOrManager {
        require(
            msg.sender == owner() ||
                msg.sender == manager ||
                msg.sender == manager2,
            "Non-admin caller"
        );
        _;
    }

    /*
     * @notice Fallback to accommodate claimRewards function
     */
    receive() external payable {
        require(msg.sender != tx.origin, "Errant ETH deposit");
    }
}
