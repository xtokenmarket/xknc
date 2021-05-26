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

/**
 * Mainnet deployment script
 * Deploys implementation only, and initializes it
 */
async function main() {
  const accounts = await ethers.getSigners();
	const [deployer] = accounts;

  console.log(
    'Deploying contracts with the account:',
    await deployer.getAddress()
  );

  const xKNC = await ethers.getContractFactory('xKNC')
  const xknc = await xKNC.deploy()
  await xknc.deployed()
  console.log('xknc deployed at:', xknc.address);

  let tx = await xknc.initialize(
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
  await tx.wait();
  console.log('xknc initialized');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
