const { expect } = require("chai");
const { ethers, waffle, upgrades } = require("hardhat");
const aave = require("./aave/deploy");
const compound = require("./compound/deploy");
const transparentProxy = require("./utils/transparentProxy");
const m = require("mocha-logger");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Reserve pool tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  async function ReservePoolTestFixture() {
    const [deployer, feeCollector, alice, bob, carol] =
      await ethers.getSigners();

    const ERC20Token = await ethers.getContractFactory(`MockERC20`);
    let token0 = await ERC20Token.deploy("Mock token0", "Token0", 18);
    let usdt = await ERC20Token.deploy("Mock USDT", "USDT", 6);

    // deploy AAVE contracts
    let aaveContracts = await aave.deployContracts({
      token0: token0,
      usdt: usdt,
    });
    let aPool = aaveContracts.pool;
    let wETH = aaveContracts.wETH;
    let aOracle = aaveContracts.priceOracle;

    // deploy compound contracts
    let compoundContracts = await compound.deployContracts({
      token0: token0,
      usdt: usdt,
    });
    let comptroller = compoundContracts.comptroller;
    let cToken0 = compoundContracts.cToken0;
    let cUSDT = compoundContracts.cUSDT;
    let cETH = compoundContracts.cETH;
    let comp = compoundContracts.comp;

    let borrowAmount = ethers.utils.parseUnits("10", "ether");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount.mul(2));
    await token0.approve(cToken0.address, supplyAmount);
    await token0.approve(aPool.address, supplyAmount);

    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    await usdt.mint(deployer.address, supplyAmount.mul(2));
    await usdt.approve(cUSDT.address, supplyAmount);
    await usdt.approve(aPool.address, supplyAmount);

    await cUSDT.mint(supplyAmount);
    await aPool.supply(usdt.address, supplyAmount, deployer.address, 0);
    await cUSDT.borrow(borrowAmount);
    await aPool.borrow(usdt.address, borrowAmount, 2, 0, deployer.address);

    await wETH.deposit({ value: supplyAmount });
    await wETH.approve(aPool.address, supplyAmount);

    await cETH.mint({ value: supplyAmount });
    await aPool.supply(wETH.address, supplyAmount, deployer.address, 0);
    await cETH.borrow(borrowAmount);
    await aPool.borrow(wETH.address, borrowAmount, 2, 0, deployer.address);
    await wETH.withdraw(borrowAmount);

    // deploy aggregator contracts
    // strategy
    let Strategy = await ethers.getContractFactory("Strategy");
    let strategy = await Strategy.deploy();
    await strategy.setMaxLTVs(
      [token0.address, ETHAddress, usdt.address],
      [700000, 700000, 700000]
    );

    // protocolsHandler
    const proxyAdmin = await transparentProxy.deployProxyAdmin();
    let protocolsHandler = await transparentProxy.deployProxy({
      implementationFactory: "ProtocolsHandler",
      libraries: {},
      initializeParams: [[], strategy.address],
      proxyAdmin: proxyAdmin,
    });

    let AAVEHandler = await ethers.getContractFactory("AAVELogic");
    let aaveHandler = await AAVEHandler.deploy(
      protocolsHandler.address,
      aPool.address,
      wETH.address
    );

    let CompoundHandler = await ethers.getContractFactory("CompoundLogic");
    let compoundHandler = await CompoundHandler.deploy(
      protocolsHandler.address,
      comptroller.address,
      cETH.address,
      comp.address,
      { gasLimit: 5000000 }
    );

    await compoundHandler.updateCTokenList(cToken0.address);
    await compoundHandler.updateCTokenList(cUSDT.address);

    // priceOracle
    let PriceOracle = await ethers.getContractFactory("MockPriceOracle");
    let priceOracle = await PriceOracle.deploy();
    await priceOracle.addAsset(token0.address, 18);
    await priceOracle.addAsset(usdt.address, 6);
    await priceOracle.addAsset(ETHAddress, 18);
    await priceOracle.setAssetPrice(token0.address, 10000000000); // set price to 100.00
    await priceOracle.setAssetPrice(usdt.address, 100000000); // set price to 1.00
    await priceOracle.setAssetPrice(ETHAddress, 200000000000); // set price to 2000.00

    // config
    let Config = await ethers.getContractFactory("Config");
    let config = await Config.deploy();

    // rewards
    let Rewards = await ethers.getContractFactory("Rewards");
    let rewards = await Rewards.deploy(protocolsHandler.address);

    // sToken
    let SToken = await ethers.getContractFactory("SToken");
    let sToken = await SToken.deploy();

    // dToken
    let DToken = await ethers.getContractFactory("DToken");
    let dToken = await DToken.deploy();

    // reservePool
    let reservePool = await transparentProxy.deployProxy({
      implementationFactory: "ReservePool",
      libraries: {},
      initializeParams: [100000],
      proxyAdmin: proxyAdmin,
    });

    // router
    let SupplyLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/SupplyLogic.sol:SupplyLogic"
    );
    let supplyLogic = await SupplyLogic.deploy();

    let RedeemLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/RedeemLogic.sol:RedeemLogic"
    );
    let redeemLogic = await RedeemLogic.deploy();

    let BorrowLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/BorrowLogic.sol:BorrowLogic"
    );
    let borrowLogic = await BorrowLogic.deploy();

    let RepayLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/RepayLogic.sol:RepayLogic"
    );
    let repayLogic = await RepayLogic.deploy();

    let LiquidateLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/LiquidateLogic.sol:LiquidateLogic"
    );
    let liquidateLogic = await LiquidateLogic.deploy();

    let router = await transparentProxy.deployProxy({
      implementationFactory: "Router",
      libraries: {
        SupplyLogic: supplyLogic.address,
        RedeemLogic: redeemLogic.address,
        BorrowLogic: borrowLogic.address,
        RepayLogic: repayLogic.address,
        LiquidateLogic: liquidateLogic.address,
      },
      initializeParams: [
        protocolsHandler.address,
        priceOracle.address,
        config.address,
        rewards.address,
        sToken.address,
        dToken.address,
        reservePool.address,
        feeCollector.address,
      ],
      proxyAdmin: proxyAdmin,
    });

    await config.setRouter(router.address);
    await protocolsHandler.transferOwnership(router.address);
    await rewards.transferOwnership(router.address);
    await reservePool.transferOwnership(router.address);

    await router.addProtocol(aaveHandler.address);
    await router.addProtocol(compoundHandler.address);

    await router.addAsset({
      underlying: token0.address,
      decimals: 18,
      collateralable: true,
      sTokenName: "s-token0",
      sTokenSymbol: "sT0",
      dTokenName: "d-token0",
      dTokenSymbol: "dT0",
      config: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
        feeRate: 10000,
      },
      maxReserve: ethers.utils.parseUnits("10", "ether"),
      executeSupplyThreshold: ethers.utils.parseUnits("1", "ether"),
    });

    await router.addAsset({
      underlying: usdt.address,
      decimals: 6,
      collateralable: true,
      sTokenName: "s-USDT",
      sTokenSymbol: "sUSDT",
      dTokenName: "d-USDT",
      dTokenSymbol: "dUSDT",
      config: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
        feeRate: 10000,
      },
      maxReserve: 100000000,
      executeSupplyThreshold: 1000000,
    });

    await router.addAsset({
      underlying: ETHAddress,
      decimals: 18,
      collateralable: true,
      sTokenName: "s-ETH",
      sTokenSymbol: "sETH",
      dTokenName: "d-ETH",
      dTokenSymbol: "dETH",
      config: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
        feeRate: 10000,
      },
      maxReserve: ethers.utils.parseUnits("1", "ether"),
      executeSupplyThreshold: ethers.utils.parseUnits("0.1", "ether"),
    });

    return {
      deployer: deployer,
      feeCollector: feeCollector,
      alice: alice,
      bob: bob,
      carol: carol,

      router: router,
      config: config,
      priceOracle: priceOracle,
      protocolsHandler: protocolsHandler,
      reservePool: reservePool,
      rewards: rewards,
      sTokenImplement: sToken,
      dTokenImplement: dToken,

      token0: token0,
      usdt: usdt,
      wETH: wETH,
      cToken0: cToken0,
      cETH: cETH,
    };
  }

  async function supply(supplier, router, token, supplyAmount, executeNow) {
    let sToken;
    if (token == null) {
      let asset = await router.assets(ETHAddress);
      sToken = await ethers.getContractAt("ISToken", asset.sToken);

      let tx = await router.supply(
        { asset: ETHAddress, amount: supplyAmount, to: supplier.address },
        true,
        true,
        { value: supplyAmount }
      );
    } else {
      await token.connect(supplier).mint(supplier.address, supplyAmount);
      await token.connect(supplier).approve(router.address, supplyAmount);

      let asset = await router.assets(token.address);
      sToken = await ethers.getContractAt("ISToken", asset.sToken);

      let tx = await router
        .connect(supplier)
        .supply(
          { asset: token.address, amount: supplyAmount, to: supplier.address },
          true,
          executeNow
        );
    }

    return sToken;
  }

  async function borrow(borrower, router, token, borrowAmount, executeNow) {
    let dToken;
    if (token == null) {
      let asset = await router.assets(ETHAddress);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.connect(borrower).borrow(
        {
          asset: ETHAddress,
          amount: borrowAmount,
          to: borrower.address,
        },
        executeNow
      );
    } else {
      let asset = await router.assets(token.address);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.connect(borrower).borrow(
        {
          asset: token.address,
          amount: borrowAmount,
          to: borrower.address,
        },
        executeNow
      );
    }

    return dToken;
  }

  describe("reserve pool init", function () {
    it("should set data properly", async () => {
      const { reservePool, router } = await loadFixture(ReservePoolTestFixture);
      expect(await reservePool.maxPendingRatio()).to.equal(100000);
      expect(await router.reservePool()).to.equal(reservePool.address);
    });
  });

  describe("reserve pool supply tests", function () {
    it("should not supply", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("10.1", "ether");
      await token0.approve(router.address, supplyAmount);
      let tx = router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: deployer.address,
        },
        true,
        false
      );

      await expect(tx).to.be.revertedWith(
        "ReservePool: pending list not allowed"
      );
    });

    it("should add to pending list when requested", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await token0.approve(router.address, supplyAmount);
      let tx = await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: deployer.address,
        },
        true,
        false
      );

      let userPendingSupply = await reservePool.pendingSupplies(
        token0.address,
        deployer.address
      );
      let lastAccountToSupply = await reservePool.lastAccountsToSupply(
        token0.address
      );
      let nextAccountToSupply = await reservePool.nextAccountsToSupply(
        token0.address
      );
      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      await expect(userPendingSupply.nextAccount).to.equal(
        ethers.constants.AddressZero
      );
      await expect(userPendingSupply.amount).to.equal(supplyAmount);
      await expect(userPendingSupply.collateralable).to.equal(true);
      await expect(lastAccountToSupply).to.equal(deployer.address);
      await expect(nextAccountToSupply).to.equal(deployer.address);
      await expect(reserve).to.equal(supplyAmount);
      await expect(balance).to.equal(supplyAmount);
    });

    it("should emit events when adding to pending list", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await token0.approve(router.address, supplyAmount);
      let tx = await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: deployer.address,
        },
        true,
        false
      );

      let receipt = await tx.wait();
      m.log("supply gas used:", receipt.gasUsed);

      await expect(tx)
        .to.emit(reservePool, "PendingListUpdated")
        .withArgs(token0.address, deployer.address, supplyAmount, true);
    });

    it("should add multiple to pending list when requested", async () => {
      const { deployer, alice, bob, router, reservePool, token0 } =
        await loadFixture(ReservePoolTestFixture);

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: alice.address,
        },
        true,
        false
      );

      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: bob.address,
        },
        false,
        false
      );

      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: alice.address,
        },
        true,
        false
      );

      let alicePendingSupply = await reservePool.pendingSupplies(
        token0.address,
        alice.address
      );

      let bobPendingSupply = await reservePool.pendingSupplies(
        token0.address,
        bob.address
      );

      let lastAccountToSupply = await reservePool.lastAccountsToSupply(
        token0.address
      );

      let nextAccountToSupply = await reservePool.nextAccountsToSupply(
        token0.address
      );

      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      await expect(alicePendingSupply.nextAccount).to.equal(bob.address);
      await expect(alicePendingSupply.amount).to.equal(supplyAmount.mul(2));
      await expect(alicePendingSupply.collateralable).to.equal(true);
    });

    it("should execute supply when requested", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await token0.approve(router.address, supplyAmount);
      let tx = await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: deployer.address,
        },
        true,
        true
      );

      let userPendingSupply = await reservePool.pendingSupplies(
        token0.address,
        deployer.address
      );
      let lastAccountToSupply = await reservePool.lastAccountsToSupply(
        token0.address
      );
      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      let assetToken0 = await router.assets(token0.address);
      let sToken0 = await ethers.getContractAt("ISToken", assetToken0.sToken);
      let sTokenBalance = await sToken0.balanceOf(deployer.address);
      let underlyingBalance = await sToken0.scaledBalanceOf(deployer.address);

      await expect(userPendingSupply.amount).to.equal(0);
      await expect(lastAccountToSupply).to.equal(ethers.constants.AddressZero);
      await expect(reserve).to.equal(0);
      await expect(balance).to.equal(0);
      await expect(sTokenBalance).to.equal(supplyAmount);
      await expect(underlyingBalance).to.be.within(
        supplyAmount.sub(1),
        supplyAmount
      );
    });

    it("should emit events when execute supply", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await token0.approve(router.address, supplyAmount);
      let tx = await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: deployer.address,
        },
        true,
        true
      );

      let receipt = await tx.wait();
      m.log("supply gas used:", receipt.gasUsed);

      await expect(tx)
        .to.emit(reservePool, "PendingListUpdated")
        .withArgs(token0.address, deployer.address, supplyAmount, true);

      await expect(tx)
        .to.emit(reservePool, "SupplyExecuted")
        .withArgs(deployer.address);
    });

    it("should execute 2 supplies on 1 execution", async () => {
      const { deployer, alice, bob, router, reservePool, token0 } =
        await loadFixture(ReservePoolTestFixture);

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: alice.address,
        },
        true,
        false
      );

      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: bob.address,
        },
        false,
        true
      );

      let alicePendingSupply = await reservePool.pendingSupplies(
        token0.address,
        alice.address
      );

      let bobPendingSupply = await reservePool.pendingSupplies(
        token0.address,
        bob.address
      );

      let lastAccountToSupply = await reservePool.lastAccountsToSupply(
        token0.address
      );

      let nextAccountToSupply = await reservePool.nextAccountsToSupply(
        token0.address
      );

      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      let assetToken0 = await router.assets(token0.address);
      let sToken0 = await ethers.getContractAt("ISToken", assetToken0.sToken);

      let aliceSTokenBalance = await sToken0.balanceOf(alice.address);
      let aliceUnderlyingBalance = await sToken0.scaledBalanceOf(alice.address);
      let bobSTokenBalance = await sToken0.balanceOf(bob.address);
      let bobUnderlyingBalance = await sToken0.scaledBalanceOf(bob.address);

      await expect(alicePendingSupply.nextAccount).to.equal(
        ethers.constants.AddressZero
      );
      await expect(alicePendingSupply.amount).to.equal(0);
      await expect(alicePendingSupply.collateralable).to.equal(false);

      await expect(bobPendingSupply.nextAccount).to.equal(
        ethers.constants.AddressZero
      );
      await expect(bobPendingSupply.amount).to.equal(0);
      await expect(bobPendingSupply.collateralable).to.equal(false);

      await expect(lastAccountToSupply).to.equal(ethers.constants.AddressZero);
      await expect(nextAccountToSupply).to.equal(ethers.constants.AddressZero);
      await expect(reserve).to.equal(0);
      await expect(balance).to.equal(0);

      await expect(aliceSTokenBalance).to.equal(supplyAmount);
      await expect(aliceUnderlyingBalance).to.equal(supplyAmount);
      await expect(bobSTokenBalance).to.equal(supplyAmount);
      await expect(bobUnderlyingBalance).to.equal(supplyAmount);
    });

    it("should emit events when execute 2 supplies", async () => {
      const { router, reservePool, token0, alice, bob } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: alice.address,
        },
        true,
        false
      );

      await token0.approve(router.address, supplyAmount);
      let tx = await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: bob.address,
        },
        false,
        true
      );

      await expect(tx)
        .to.emit(reservePool, "SupplyExecuted")
        .withArgs(alice.address);

      await expect(tx)
        .to.emit(reservePool, "SupplyExecuted")
        .withArgs(bob.address);
    });

    it("should execute supply with external trigger", async () => {
      const { deployer, alice, bob, router, reservePool, token0 } =
        await loadFixture(ReservePoolTestFixture);

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: alice.address,
        },
        true,
        false
      );

      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: bob.address,
        },
        false,
        false
      );

      await reservePool.executeRepayAndSupply(token0.address, 1);

      let alicePendingSupply = await reservePool.pendingSupplies(
        token0.address,
        alice.address
      );

      let bobPendingSupply = await reservePool.pendingSupplies(
        token0.address,
        bob.address
      );

      let lastAccountToSupply = await reservePool.lastAccountsToSupply(
        token0.address
      );

      let nextAccountToSupply = await reservePool.nextAccountsToSupply(
        token0.address
      );

      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      let assetToken0 = await router.assets(token0.address);
      let sToken0 = await ethers.getContractAt("ISToken", assetToken0.sToken);

      let aliceSTokenBalance = await sToken0.balanceOf(alice.address);
      let aliceUnderlyingBalance = await sToken0.scaledBalanceOf(alice.address);
      let bobSTokenBalance = await sToken0.balanceOf(bob.address);
      let bobUnderlyingBalance = await sToken0.scaledBalanceOf(bob.address);

      await expect(alicePendingSupply.nextAccount).to.equal(
        ethers.constants.AddressZero
      );
      await expect(alicePendingSupply.amount).to.equal(0);
      await expect(alicePendingSupply.collateralable).to.equal(false);

      await expect(bobPendingSupply.nextAccount).to.equal(
        ethers.constants.AddressZero
      );
      await expect(bobPendingSupply.amount).to.equal(supplyAmount);
      await expect(bobPendingSupply.collateralable).to.equal(false);

      await expect(lastAccountToSupply).to.equal(bob.address);
      await expect(nextAccountToSupply).to.equal(bob.address);
      await expect(reserve).to.equal(supplyAmount);
      await expect(balance).to.equal(supplyAmount);

      await expect(aliceSTokenBalance).to.equal(supplyAmount);
      await expect(aliceUnderlyingBalance).to.be.within(
        supplyAmount.sub(1),
        supplyAmount
      );
      await expect(bobSTokenBalance).to.equal(0);
      await expect(bobUnderlyingBalance).to.equal(0);
    });

    it("should emit events when execute with external trigger", async () => {
      const { deployer, alice, bob, router, reservePool, token0 } =
        await loadFixture(ReservePoolTestFixture);

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: alice.address,
        },
        true,
        false
      );

      await token0.approve(router.address, supplyAmount);
      await router.supply(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: bob.address,
        },
        false,
        false
      );

      let tx = await reservePool.executeRepayAndSupply(token0.address, 1);

      await tx.wait();

      await expect(tx)
        .to.emit(reservePool, "SupplyExecuted")
        .withArgs(alice.address);
    });
  });

  describe("reserve pool redeem tests", function () {
    it("should not redeem", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, supplyAmount, true);
      await supply(deployer, router, token0, supplyAmount, false);

      let tx = router.redeem(
        {
          asset: token0.address,
          amount: supplyAmount.mul(2),
          to: deployer.address,
        },
        true,
        false
      );

      await expect(tx).to.be.revertedWith("ReservePool: insufficient balance");
    });

    it("should execute redeem when requested", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, supplyAmount, true);
      await supply(deployer, router, token0, supplyAmount, false);

      let tx = await router.redeem(
        {
          asset: token0.address,
          amount: supplyAmount.mul(3),
          to: deployer.address,
        },
        true,
        true
      );

      let userPendingSupply = await reservePool.pendingSupplies(
        token0.address,
        deployer.address
      );
      let lastAccountToSupply = await reservePool.lastAccountsToSupply(
        token0.address
      );
      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      let assetToken0 = await router.assets(token0.address);
      let sToken0 = await ethers.getContractAt("ISToken", assetToken0.sToken);
      let sTokenBalance = await sToken0.balanceOf(deployer.address);
      let underlyingBalance = await sToken0.scaledBalanceOf(deployer.address);
      let totalSupplies = await router.totalSupplied(token0.address);

      await expect(userPendingSupply.amount).to.equal(0);
      await expect(lastAccountToSupply).to.equal(deployer.address);
      await expect(reserve).to.equal(0);
      await expect(balance).to.equal(0);
      await expect(sTokenBalance).to.equal(0);
      await expect(totalSupplies).to.equal(0);
    });

    it("should emit events when execute redeem", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      let sToken0 = await supply(deployer, router, token0, supplyAmount, true);
      await supply(deployer, router, token0, supplyAmount, false);

      let tx = router.redeem(
        {
          asset: token0.address,
          amount: supplyAmount.mul(3),
          to: deployer.address,
        },
        true,
        true
      );

      await expect(tx)
        .to.emit(reservePool, "PendingListUpdated")
        .withArgs(token0.address, deployer.address, 0, true);
      await expect(tx)
        .to.emit(sToken0, "Transfer")
        .withArgs(deployer.address, ethers.constants.AddressZero, supplyAmount);
    });

    it("should redeem from reserve when requested", async () => {
      const { router, reservePool, token0, alice, bob } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await supply(alice, router, token0, supplyAmount, true);
      await supply(bob, router, token0, supplyAmount, false);

      let tx = await router.connect(alice).redeem(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: alice.address,
        },
        true,
        false
      );

      let alicePendingSupply = await reservePool.pendingSupplies(
        token0.address,
        alice.address
      );

      let bobPendingSupply = await reservePool.pendingSupplies(
        token0.address,
        bob.address
      );

      let redeemedAmount = await reservePool.redeemedAmounts(token0.address);
      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      let assetToken0 = await router.assets(token0.address);
      let sToken0 = await ethers.getContractAt("ISToken", assetToken0.sToken);
      let sTokenBalance = await sToken0.balanceOf(alice.address);
      let underlyingBalance = await sToken0.scaledBalanceOf(alice.address);
      let totalSupplies = await router.totalSupplied(token0.address);

      await expect(redeemedAmount).to.equal(supplyAmount);
      await expect(bobPendingSupply.amount).to.equal(supplyAmount);
      await expect(reserve).to.equal(0);
      await expect(balance).to.equal(0);
      await expect(sTokenBalance).to.equal(21571301644);
      await expect(underlyingBalance).to.equal(21571302110);
      await expect(totalSupplies).to.equal(21571302110);
    });

    it("should not emit events when redeem from reserve", async () => {
      const { router, reservePool, token0, alice, bob } = await loadFixture(
        ReservePoolTestFixture
      );

      let supplyAmount = ethers.utils.parseUnits("1", "ether");
      await supply(alice, router, token0, supplyAmount, true);
      await supply(bob, router, token0, supplyAmount, false);

      let tx = await router.connect(alice).redeem(
        {
          asset: token0.address,
          amount: supplyAmount,
          to: alice.address,
        },
        true,
        false
      );

      await expect(tx).to.not.emit(reservePool, "PendingListUpdated");
    });
  });

  describe("reserve pool borrow tests", function () {
    it("should not borrow", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let borrowAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, borrowAmount.mul(3), true);
      await supply(deployer, router, token0, borrowAmount, false);

      let tx = router.borrow(
        {
          asset: token0.address,
          amount: borrowAmount.mul(2),
          to: deployer.address,
        },
        false
      );

      await expect(tx).to.be.revertedWith("ReservePool: insufficient balance");
    });

    it("should execute borrow when requested", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let borrowAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, borrowAmount.mul(2), true);
      await supply(deployer, router, token0, borrowAmount, false);

      let tx = await router.borrow(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        true
      );

      let userLentAmount = await reservePool.lentAmounts(token0.address);
      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      let assetToken0 = await router.assets(token0.address);
      let dToken0 = await ethers.getContractAt("IDToken", assetToken0.dToken);
      let dTokenBalance = await dToken0.balanceOf(deployer.address);
      let underlyingBalance = await dToken0.scaledDebtOf(deployer.address);
      let totalBorrowed = await router.totalBorrowed(token0.address);

      await expect(userLentAmount).to.equal(0);
      await expect(reserve).to.equal(borrowAmount);
      await expect(balance).to.equal(borrowAmount);
      await expect(dTokenBalance).to.equal(borrowAmount);
      await expect(underlyingBalance).to.equal(borrowAmount);
      await expect(totalBorrowed).to.equal(underlyingBalance);
    });

    it("should emit events when execute borrow from reserve", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let borrowAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, borrowAmount.mul(2), true);
      await supply(deployer, router, token0, borrowAmount, false);

      let tx = await router.borrow(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        true
      );

      let assetToken0 = await router.assets(token0.address);
      let dToken0 = await ethers.getContractAt("IDToken", assetToken0.dToken);

      await expect(tx)
        .to.emit(dToken0, "Transfer")
        .withArgs(ethers.constants.AddressZero, deployer.address, borrowAmount);
    });

    it("should borrow from reserve when requested", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let borrowAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, borrowAmount.mul(2), true);
      await supply(deployer, router, token0, borrowAmount, false);

      let tx = await router.borrow(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        false
      );

      let userLentAmount = await reservePool.lentAmounts(token0.address);
      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      let assetToken0 = await router.assets(token0.address);
      let dToken0 = await ethers.getContractAt("IDToken", assetToken0.dToken);
      let dTokenBalance = await dToken0.balanceOf(deployer.address);
      let underlyingBalance = await dToken0.scaledDebtOf(deployer.address);
      let totalBorrowed = await router.totalBorrowed(token0.address);

      await expect(userLentAmount).to.equal(borrowAmount);
      await expect(reserve).to.equal(0);
      await expect(balance).to.equal(0);
      await expect(dTokenBalance).to.equal(borrowAmount);
      await expect(underlyingBalance).to.equal(borrowAmount);
      await expect(totalBorrowed).to.equal(underlyingBalance);
    });

    it("should emit events when borrow from reserve", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let borrowAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, borrowAmount.mul(2), true);
      await supply(deployer, router, token0, borrowAmount, false);

      let tx = await router.borrow(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        false
      );

      let assetToken0 = await router.assets(token0.address);
      let dToken0 = await ethers.getContractAt("IDToken", assetToken0.dToken);

      await expect(tx)
        .to.emit(token0, "Transfer")
        .withArgs(reservePool.address, deployer.address, borrowAmount);

      await expect(tx)
        .to.emit(dToken0, "Transfer")
        .withArgs(ethers.constants.AddressZero, deployer.address, borrowAmount);
    });
  });

  describe("reserve pool repay tests", function () {
    it("should not repay", async () => {
      const { deployer, router, reservePool, token0 } = await loadFixture(
        ReservePoolTestFixture
      );

      let borrowAmount = ethers.utils.parseUnits("20", "ether");
      await supply(deployer, router, token0, borrowAmount.mul(3), true);
      await borrow(deployer, router, token0, borrowAmount, true);

      await token0.approve(router.address, borrowAmount);
      let tx = router.repay(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        false
      );

      await expect(tx).to.be.revertedWith(
        "ReservePool: excceed max pending ratio"
      );

      await supply(deployer, router, token0, borrowAmount.div(2), false);
      await token0.approve(router.address, borrowAmount);
      tx = router.repay(
        {
          asset: token0.address,
          amount: borrowAmount.div(10),
          to: deployer.address,
        },
        false
      );

      await expect(tx).to.be.revertedWith("ReservePool: max reserve excceeded");
    });

    it("should execute repay when requested", async () => {
      const { deployer, router, reservePool, token0, alice } =
        await loadFixture(ReservePoolTestFixture);

      let borrowAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, borrowAmount.mul(30), true);
      await borrow(deployer, router, token0, borrowAmount.mul(10), true);

      await supply(alice, router, token0, borrowAmount.mul(2), true);
      await borrow(alice, router, token0, borrowAmount, true);

      await token0.mint(deployer.address, borrowAmount.mul(2));
      await token0.approve(router.address, borrowAmount.mul(2));

      let tx = await router.repay(
        {
          asset: token0.address,
          amount: borrowAmount.mul(2),
          to: alice.address,
        },
        true
      );

      let pendingRepayAmount = await reservePool.pendingRepayAmounts(
        token0.address
      );
      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      let assetToken0 = await router.assets(token0.address);
      let dToken0 = await ethers.getContractAt("IDToken", assetToken0.dToken);
      let dTokenBalance = await dToken0.balanceOf(alice.address);
      let underlyingBalance = await dToken0.scaledDebtOf(alice.address);
      let totalBorrowed = await router.totalBorrowed(token0.address);

      await expect(pendingRepayAmount).to.equal(0);
      await expect(reserve).to.equal(0);
      await expect(balance).to.equal(0);
      await expect(dTokenBalance).to.equal(0);
      await expect(underlyingBalance).to.equal(0);
      await expect(totalBorrowed).to.be.below(borrowAmount.mul(11));
    });

    it("should emit events when execute repay", async () => {});

    it("should repay to reserve pool", async () => {
      const { deployer, router, reservePool, token0, alice } =
        await loadFixture(ReservePoolTestFixture);

      let borrowAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, borrowAmount.mul(30), true);
      await borrow(deployer, router, token0, borrowAmount.mul(10), true);

      await supply(alice, router, token0, borrowAmount.mul(2), true);
      await borrow(alice, router, token0, borrowAmount, true);

      await token0.mint(deployer.address, borrowAmount.mul(2));
      await token0.approve(router.address, borrowAmount.mul(2));

      let balanceBefore = await token0.balanceOf(deployer.address);
      let tx = await router.repay(
        {
          asset: token0.address,
          amount: borrowAmount.mul(2),
          to: alice.address,
        },
        false
      );
      let balanceAfter = await token0.balanceOf(deployer.address);
      let repayedAmount = balanceBefore.sub(balanceAfter);

      let pendingRepayAmount = await reservePool.pendingRepayAmounts(
        token0.address
      );
      let fee = await router.collectedFees(token0.address);
      let reserve = await reservePool.reserves(token0.address);
      let balance = await token0.balanceOf(reservePool.address);

      let assetToken0 = await router.assets(token0.address);
      let dToken0 = await ethers.getContractAt("IDToken", assetToken0.dToken);
      let dTokenBalance = await dToken0.balanceOf(alice.address);
      let underlyingBalance = await dToken0.scaledDebtOf(alice.address);
      let totalBorrowed = await router.totalBorrowed(token0.address);

      await expect(pendingRepayAmount).to.equal(repayedAmount.sub(fee));
      await expect(reserve).to.equal(repayedAmount.sub(fee));
      await expect(balance).to.equal(repayedAmount.sub(fee));
      await expect(dTokenBalance).to.equal(0);
      await expect(underlyingBalance).to.equal(0);
      await expect(totalBorrowed).to.be.below(borrowAmount.mul(11));
    });

    it("should emit events when repay to reserve pool", async () => {});

    it("should execute repay at trigger", async () => {
      const { deployer, router, reservePool, token0, alice } =
        await loadFixture(ReservePoolTestFixture);

      let borrowAmount = ethers.utils.parseUnits("1", "ether");
      await supply(deployer, router, token0, borrowAmount.mul(30), true);
      await borrow(deployer, router, token0, borrowAmount.mul(10), true);

      await supply(alice, router, token0, borrowAmount.mul(2), true);
      await borrow(alice, router, token0, borrowAmount, true);

      await token0.mint(deployer.address, borrowAmount.mul(2));
      await token0.approve(router.address, borrowAmount.mul(2));

      let tx = await router.repay(
        {
          asset: token0.address,
          amount: borrowAmount.mul(2),
          to: alice.address,
        },
        false
      );

      await reservePool.executeRepayAndSupply(token0.address, 1);

      let pendingRepayAmount = await reservePool.pendingRepayAmounts(
        token0.address
      );

      await expect(pendingRepayAmount).to.equal(0);
    });
  });
});
