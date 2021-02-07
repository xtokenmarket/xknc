const hre = require("hardhat");
const { ethers } = require("hardhat");

// mainnet
const KYBER_PROXY_ADDRESS = '0x9AAb3f75489902f3a48495025729a0AF77d4b11e'
const KYBER_TOKEN_ADDRESS = '0xdd974D5C2e2928deA5F71b9825b8b646686BD200'
const KYBER_STAKING_ADDRESS = '0xECf0bdB7B3F349AbfD68C3563678124c5e8aaea3'
const KYBER_DAO_ADDRESS = '0x49bdd8854481005bBa4aCEbaBF6e06cD5F6312e9'
const KYBER_FEE_HANDLER_ETH = '0xd3d2b5643e506c6d9B7099E9116D7aAa941114fe'
const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'
const FEE_DIVISORS = {
  MINT_FEE: '0',
  BURN_FEE: '500',
  CLAIM_FEE: '100',
};

// run on mainnet fork
async function main() {
  const accounts = await ethers.getSigners();
	const [deployer, user1, user2] = accounts;

  console.log(
    'Deploying contracts with the account:',
    await deployer.getAddress()
  )

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const xKNC = await ethers.getContractFactory('xKNC')
  const xknc = await xKNC.deploy()
  await xknc.deployed()
  console.log('xKNC address:', xknc.address)

  const xKNCProxy = await ethers.getContractFactory('xKNCProxy');
  const xkncProxy = await xKNCProxy.deploy(xknc.address, user1.address); // transfer ownership to multisig
  const xkncProxyCast = await ethers.getContractAt('xKNC', xkncProxy.address);

  await xkncProxyCast.initialize(
      "xKNCa",
      'xKNC Mandate: Stakers',
      KYBER_STAKING_ADDRESS,
      KYBER_PROXY_ADDRESS,
      KYBER_TOKEN_ADDRESS,
      KYBER_DAO_ADDRESS,
      FEE_DIVISORS.MINT_FEE,
      FEE_DIVISORS.BURN_FEE,
      FEE_DIVISORS.CLAIM_FEE
  )

  await xkncProxyCast.addKyberFeeHandler(KYBER_FEE_HANDLER_ETH, ETH_ADDRESS)
  console.log('ETH fee handler added')
  await xkncProxyCast.approveStakingContract(false);
  console.log('kyber staking contract approved')
  await xkncProxyCast.approveKyberProxyContract(KYBER_TOKEN_ADDRESS, false);
  console.log('knc approved on proxy contract')

  await xkncProxyCast.mint('0', { value: ethers.utils.parseEther('1')})
  const xkncBal = await xkncProxyCast.balanceOf(deployer.address)
  console.log('xkncBal', xkncBal.toString())
  
  const toBurn = xkncBal.div(50)
  await xkncProxyCast.burn(toBurn, true, '0')

  const xkncBal2 = await xkncProxyCast.balanceOf(deployer.address)
  console.log('xkncBal2', xkncBal2.toString())
  
  const knc = await ethers.getContractAt('ERC20', KYBER_TOKEN_ADDRESS)
  const kncBal = await knc.balanceOf(deployer.address)  
  console.log('kncBal', kncBal.toString())
  
  await knc.approve(xkncProxyCast.address, toBurn)
  await xkncProxyCast.mintWithToken(kncBal)
  
  const xkncBal3 = await xkncProxyCast.balanceOf(deployer.address)
  console.log('xkncBal3', xkncBal3.toString())
  
  const stakedBalance = await xkncProxyCast.getFundKncBalanceTwei()
  console.log('stakedBalance', stakedBalance.toString())
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
