const { expect, assert } = require('chai');
const { utils, BigNumber } = require('ethers');

describe('xKNC', () => {
	const provider = waffle.provider;
	const [wallet, user, msigUser, manager, manager2] = provider.getWallets();
	const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
	const FEE_DIVISORS = {
		MINT_FEE: '0',
		BURN_FEE: '500',
		CLAIM_FEE: '100',
	};

	// let xkncV1, knc, kyberProxy, kyberStaking, kyberDao, xknc;
	let oldKyberStaking, newKyberStaking, oldKnc, newKnc, kyberProxy, oldKyberDao, newKyberDao, xknc, xkncProxyCast, xkncProxy, rewardsDistributor

	before(async () => {
		const KyberStaking = await ethers.getContractFactory('MockKyberStaking');
		const KyberProxy = await ethers.getContractFactory('MockKyberNetworkProxy');
		const xKNCV1 = await ethers.getContractFactory('xKNCv1');
		const KNC = await ethers.getContractFactory('MockKNC');
		const KNCV3 = await ethers.getContractFactory('MockKNCV3');
		const OldKyberDao = await ethers.getContractFactory('OldMockKyberDAO');
		const KyberDao = await ethers.getContractFactory('MockKyberDAO');
		const RewardsDistributor = await ethers.getContractFactory('MockRewardsDistributor')

		oldKyberStaking = await KyberStaking.deploy();
		await oldKyberStaking.deployed();

		newKyberStaking = await KyberStaking.deploy()
		await newKyberStaking.deployed()

		kyberProxy = await KyberProxy.deploy();
		await kyberProxy.deployed();

		oldKnc = await KNC.deploy();
		await oldKnc.deployed();

		newKnc = await KNCV3.deploy(oldKnc.address)
		await newKnc.deployed()

		await newKyberStaking.setKncAddress(newKnc.address)

		oldKyberDao = await OldKyberDao.deploy();
		await oldKyberDao.deployed();

		newKyberDao = await KyberDao.deploy()
		await newKyberDao.deployed()

		xkncV1 = await xKNCV1.deploy();
		await xkncV1.deployed()

		rewardsDistributor = await RewardsDistributor.deploy()
		await rewardsDistributor.deployed()
		const tx = { to: rewardsDistributor.address, value: utils.parseEther('10') };
		await wallet.sendTransaction(tx);

		// new version with v3 migration
		const xKNC = await ethers.getContractFactory('xKNC');
		xknc = await xKNC.deploy()
		await xknc.deployed()

		const xKNCProxy = await ethers.getContractFactory('xKNCProxy');
		xkncProxy = await xKNCProxy.deploy(xkncV1.address, msigUser.address); // transfer ownership to multisig
		xkncProxyCast = await ethers.getContractAt('xKNCv1', xkncProxy.address);

		await xkncProxyCast.initialize(
			'xKNCa',
			'xKNC Mandate: Stakers',
			oldKyberStaking.address,
			kyberProxy.address,
			oldKnc.address,
			oldKyberDao.address,
			FEE_DIVISORS.MINT_FEE,
			FEE_DIVISORS.BURN_FEE,
			FEE_DIVISORS.CLAIM_FEE
		);

		// xknc = xkncProxyCast;

		// configure pre-upgrade version
		await kyberProxy.setKncAddress(oldKnc.address);
		await oldKnc.transfer(kyberProxy.address, utils.parseEther('500'));

		await oldKyberStaking.setKncAddress(oldKnc.address);
		// await oldKnc.transfer(oldKyberStaking.address, utils.parseEther('5'));

		const MockToken = await ethers.getContractFactory('MockToken');
		mockToken = await MockToken.deploy();
		await mockToken.deployed();

		const KyberFeeHandler = await ethers.getContractFactory('MockKyberFeeHandler');
		kyberFeeHandler = await KyberFeeHandler.deploy();
		await kyberFeeHandler.deployed();

		const TokenKyberFeeHandler = await ethers.getContractFactory('MockTokenKyberFeeHandler');
		tokenKyberFeeHandler = await TokenKyberFeeHandler.deploy(mockToken.address);
		await tokenKyberFeeHandler.deployed();

		const tx1 = { to: kyberFeeHandler.address, value: utils.parseEther('0.1') };
		await wallet.sendTransaction(tx1);
		await mockToken.transfer(tokenKyberFeeHandler.address, utils.parseEther('1'));

		await xkncProxyCast.addKyberFeeHandler(kyberFeeHandler.address, ETH_ADDRESS);
		await xkncProxyCast.approveStakingContract(false);
		await xkncProxyCast.approveKyberProxyContract(oldKnc.address, false);

		// mint and stake on pre-upgrade version
		await xkncProxyCast.mint(0, { value: utils.parseEther('0.01') });
		await oldKnc.approve(xkncProxyCast.address, utils.parseEther('20'))
		await xkncProxyCast.mintWithToken(utils.parseEther('20'))

		// ensure there are knc fees charged to the contract (fees only charged on burn)
		await xkncProxyCast.burn(utils.parseEther('100'), true, 0);

	});

	describe('xKNC: migration to v3', async () => {
		it('should show pre-migration balances', async () => {
			const totalSupply = await xkncProxyCast.totalSupply()
			assert.isAbove(totalSupply, 0, 'No supply');

			const stakedBal = await xkncProxyCast.getFundKncBalanceTwei()
			assert.isAbove(stakedBal, 0, 'Not staked');
		});

		it('should upgrade contract', async () => {
			await hre.network.provider.request({
				method: "hardhat_impersonateAccount",
				params: [msigUser.address]
			});
			const multisig = await ethers.provider.getSigner(msigUser.address)

			await xkncProxy.connect(multisig).upgradeTo(xknc.address)

			xkncProxyCast = await ethers.getContractAt('xKNC', xkncProxy.address);

			const rewardsDistributorAddress = await xkncProxyCast.getRewardDistributor()

			// old abi would fail
			assert.isOk('rewards distributor call didnt fail - migration successful')
		});

		it('should migrate to v3', async () => {
			await xkncProxyCast.migrateV3(
				newKnc.address,
				newKyberDao.address,
				newKyberStaking.address,
				rewardsDistributor.address
			)

			// TEST SETUP
			await kyberProxy.setKncAddress(newKnc.address);
			await newKnc.transfer(kyberProxy.address, utils.parseEther('1000'))

			// 

			const rewardsDistributorAddress = await xkncProxyCast.getRewardDistributor()
			assert.equal(rewardsDistributorAddress, rewardsDistributor.address)

			const oldKncStakedBalOldStakingContract = await oldKnc.balanceOf(oldKyberStaking.address)
			assert.equal(oldKncStakedBalOldStakingContract, 0)

			const oldKncBal = await oldKnc.balanceOf(xkncProxyCast.address)
			assert.equal(oldKncBal, 0)

			const newKncStakedBalNewStakingContract = await newKnc.balanceOf(newKyberStaking.address)
			assert.isAbove(newKncStakedBalNewStakingContract, 0)

			const expectedFeesInContract = (utils.parseEther('10')).div(500) // 10 knc = 100 xknc burned in test setup 
			const newKncBal = await newKnc.balanceOf(xkncProxyCast.address)
			assert.equal(expectedFeesInContract.toString(), newKncBal.toString())
		})
	});

	describe('xKNC: minting with ETH', async () => {
		it('should issue xKNC tokens to the caller', async () => {
			const xkncBalBefore = await xkncProxyCast.balanceOf(wallet.address);
			await xkncProxyCast.mint(0, { value: utils.parseEther('0.01') });
			const xkncBalAfter = await xkncProxyCast.balanceOf(wallet.address);

			assert.isAbove(xkncBalAfter, xkncBalBefore);
		});

		it('should result in staked KNC', async () => {
			const stakedBal = await xkncProxyCast.getFundKncBalanceTwei();
			assert.isAbove(stakedBal, 0, 'KNC staked');
		});
	});

	describe('xKNC: minting with KNC', async () => {
		let stakedBalBefore;
		it('should issue xKNC tokens to the caller', async () => {
			stakedBalBefore = await xkncProxyCast.getFundKncBalanceTwei();
			const xkncBalBefore = await xkncProxyCast.balanceOf(wallet.address);
			await newKnc.approve(xkncProxyCast.address, utils.parseEther('10000'));

			await xkncProxyCast.mintWithToken(utils.parseEther('0.01'));
			const xkncBalAfter = await xkncProxyCast.balanceOf(wallet.address);

			assert.isAbove(xkncBalAfter, xkncBalBefore, 'xKNC minted');
		});

		it('should result in staked KNC', async () => {
			const stakedBalAfter = await xkncProxyCast.getFundKncBalanceTwei();
			assert.isAbove(stakedBalAfter, stakedBalBefore, 'KNC staked');
		});
	});

	describe('xKNC: burning', async () => {
		it('should send ETH to caller if burning for ETH', async () => {
			const totalSupply = await xkncProxyCast.totalSupply();
			const toBurn = totalSupply.div(BigNumber.from(5));
			const ethBalBefore = await provider.getBalance(wallet.address);

			await xkncProxyCast.burn(toBurn, false, 0, { gasLimit: 1000000 });
			const ethBalAfter = await provider.getBalance(wallet.address);
			assert.isAbove(ethBalAfter, ethBalBefore);
		});

		it('should send KNC to caller if burning for KNC', async () => {
			const totalSupply = await xkncProxyCast.totalSupply();
			const toBurn = totalSupply.div(BigNumber.from(5));
			const kncBalBefore = await newKnc.balanceOf(wallet.address);

			await xkncProxyCast.burn(toBurn, true, 0);
			const kncBalAfter = await newKnc.balanceOf(wallet.address);
			assert.isAbove(kncBalAfter, kncBalBefore);
		});
	});

	describe('xKNC: DAO', async () => {
		it('should vote in a campaign', async () => {
			await xkncProxyCast.vote(1, 1);
			assert.isOk('Campaign vote submitted');
		});

		it('should not be able to vote in a campaign if called from non-owner', async () => {
			await expect(xkncProxyCast.connect(user).vote(1, 1)).to.be.reverted;
		});

		it('should claim ETH reward and convert to KNC', async () => {
			const stakedBalBefore = await xkncProxyCast.getFundKncBalanceTwei();
			await xkncProxyCast.claimReward(1, 1, [ETH_ADDRESS], [utils.parseEther('10')], [utils.formatBytes32String('string')], [0]);
			const stakedBalAfter = await xkncProxyCast.getFundKncBalanceTwei();
			assert.isAbove(stakedBalAfter, stakedBalBefore);
		});

		it('should not be able to claim if called from non-owner', async () => {
			await expect(xkncProxyCast.connect(user).claimReward(1, 1, [ETH_ADDRESS], [utils.parseEther('10')], [utils.formatBytes32String('string')], [0])).to.be.reverted;
		});
	});

	describe('xKNC: Util Functions', async () => {
		it('should set the fee divisors again by owner', async () => {
			await xkncProxyCast.setFeeDivisors('100', '500', '100');
			assert.isOk('Fee set');
		});

		it('should allow for a permissioned manager to be set for vote', async () => {
			await xkncProxyCast.setManager(manager.address);
			await expect(xkncProxyCast.connect(manager).setFeeDivisors('0', '500', '100')).to.be.reverted;
			await xkncProxyCast.connect(manager).vote(1, 1);
			assert.isOk('Campaign vote submitted as manager');
		});

		it('should allow for a permissioned manager to be set', async () => {
			await xkncProxyCast.setManager(manager2.address);
			await xkncProxyCast.connect(manager2).claimReward(1, 1, [ETH_ADDRESS], [utils.parseEther('10')], [utils.formatBytes32String('string')], [0])
			assert.isOk('Reward claimed as manager');
		});

		it('should not allow non admin to pause', async () => {
			await expect(xkncProxyCast.connect(msigUser).pause()).to.be.reverted;
		});

		it('should allow admin to pause', async () => {
			await xkncProxyCast.connect(manager2).pause();
			assert.isOk('Paused');
		});

		it('should not allow minting when paused', async () => {
			await expect(xkncProxyCast.mint('0', { value: utils.parseEther('1') })).to.be.reverted;
		});

		it('should allow minting once unpaused', async () => {
			await xkncProxyCast.connect(manager2).unpause();
			await xkncProxyCast.mint('0', { value: utils.parseEther('1') });
			assert.isOk('Minted');
		});
	});
});
