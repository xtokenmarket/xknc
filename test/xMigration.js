const { expect, assert } = require('chai');
const { utils } = require('ethers');

describe('xMigration', () => {
	const provider = waffle.provider;
	const [wallet, user, user1, msigUser] = provider.getWallets();
	const FEE_DIVISORS = {
		MINT_FEE: '0',
		BURN_FEE: '500',
		CLAIM_FEE: '100',
	};

	let kyberStaking, kyberProxy, knc, kyberDao, xkncaLegacy, xkncV1, xknca, xmigration;
	let burnMintAmt = utils.parseEther('100');

	before(async () => {
		const KyberStaking = await ethers.getContractFactory('MockKyberStaking');
		kyberStaking = await KyberStaking.deploy();
		await kyberStaking.deployed();

		const KyberProxy = await ethers.getContractFactory('MockKyberNetworkProxy');
		kyberProxy = await KyberProxy.deploy();
		await kyberProxy.deployed();

		const KNC = await ethers.getContractFactory('MockKNC');
		knc = await KNC.deploy();
		await knc.deployed();

		const KyberDao = await ethers.getContractFactory('MockKyberDAO');
		kyberDao = await KyberDao.deploy();
		await kyberDao.deployed();

		const xKNCaLegacy = await ethers.getContractFactory('MockXKNC');
		xkncaLegacy = await xKNCaLegacy.deploy(kyberStaking.address, knc.address);
		await xkncaLegacy.deployed();

		await xkncaLegacy.transfer(user1.address, utils.parseEther('100'));

		await kyberStaking.setKncAddress(knc.address);
		await knc.transfer(kyberStaking.address, utils.parseEther('150'));

		const xKNC = await ethers.getContractFactory('xKNC');
		xkncV1 = await xKNC.deploy();

		const xKNCProxy = await ethers.getContractFactory('xKNCProxy');
		const xkncProxy = await xKNCProxy.deploy(xkncV1.address, msigUser.address); // transfer ownership to multisig
		const xkncProxyCast = await ethers.getContractAt('xKNC', xkncProxy.address);

		await xkncProxyCast.initialize(
			'xKNCa',
			'xKNC Mandate: Stakers',
			kyberStaking.address,
			kyberProxy.address,
			knc.address,
			kyberDao.address,
			FEE_DIVISORS.MINT_FEE,
			FEE_DIVISORS.BURN_FEE,
			FEE_DIVISORS.CLAIM_FEE
		);
		xknca = xkncProxyCast;
		await xknca.approveStakingContract(false);

		const xMigration = await ethers.getContractFactory('xMigration');
		xmigration = await xMigration.deploy(xkncaLegacy.address, xknca.address, knc.address);
		await xmigration.deployed();
	});

	it('should approve new xknc contract to spend knc', async () => {
		await xmigration.approveTarget();
		const approvedBal = await knc.allowance(xmigration.address, xknca.address);
		assert.isAbove(approvedBal, 0, 'Approval succeeded');
	});

	it('should approve the migration contract to spend legacy xKNCa', async () => {
		await xkncaLegacy.connect(user1).approve(xmigration.address, burnMintAmt);
		const approvedBal = await xkncaLegacy.allowance(user1.address, xmigration.address);
		assert.isAbove(approvedBal, 0, 'Approval succeeded');
	});

	it('should not able to migrate 0 balance', async () => {
		await expect(xmigration.migrate()).to.be.reverted;
	});

	it('migrate legacy xKNCa', async () => {
		const xkncaBalBefore = await xknca.balanceOf(user1.address);
		assert.equal(xkncaBalBefore, 0);

		await xmigration.connect(user1).migrate();

		const xkncaLegacyBalAfter = await xkncaLegacy.balanceOf(user1.address);
		assert.equal(xkncaLegacyBalAfter, 0);

		const xkncaBalAfter = await xknca.balanceOf(user1.address);
		assert.isAbove(xkncaBalAfter, 0);
	});
});
