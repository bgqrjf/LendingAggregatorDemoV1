const { expect } = require("chai");
const { ethers, waffle, upgrades } = require("hardhat");
const aave = require("./aave/deploy");
const compound = require("./compound/deploy");
const m = require("mocha-logger");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const ProxyAdmin = require("@openzeppelin/contracts/build/contracts/ProxyAdmin.json");
const TransparentUpgradeableProxy = require("@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json");

describe("Router tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  async function RouterTestFixture() {
    const [deployer] = await ethers.getSigners();

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

    let AAVEHandler = await ethers.getContractFactory("AAVELogic");
    // _aaveTokenAddress
    let aaveHandler = await AAVEHandler.deploy(
      aPool.address,
      wETH.address,
      wETH.address
    );

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

    let CompoundHandler = await ethers.getContractFactory("CompoundLogic");
    let compoundHandler = await CompoundHandler.deploy(
      comptroller.address,
      cETH.address,
      comp.address,
      { gasLimit: 5000000 }
    );

    await compoundHandler.updateCTokenList(cToken0.address);
    await compoundHandler.updateCTokenList(cUSDT.address);

    let borrowAmount = ethers.BigNumber.from("10000000000000000000");
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

    // deploy aggregator contracts
    // strategy
    let Strategy = await ethers.getContractFactory("Strategy");
    let strategy = await Strategy.deploy();
    await strategy.setMaxLTVs(
      [token0.address, ETHAddress, usdt.address],
      [700000, 700000, 700000]
    );

    // protocolsHandler
    let ProtocolsHandler = await ethers.getContractFactory("ProtocolsHandler");
    let protocolsHandlerImplementation = await ProtocolsHandler.deploy();

    let Admin = await ethers.getContractFactory(
      ProxyAdmin.abi,
      ProxyAdmin.bytecode
    );

    let proxyAdmin = await Admin.deploy();

    const Proxy = await ethers.getContractFactory(
      TransparentUpgradeableProxy.abi,
      TransparentUpgradeableProxy.bytecode
    );

    let protocolsHandlerInitializeData =
      protocolsHandlerImplementation.interface.encodeFunctionData(
        "initialize",
        [[], strategy.address]
      );

    let protocolsHandlerProxy = await Proxy.deploy(
      protocolsHandlerImplementation.address,
      proxyAdmin.address,
      protocolsHandlerInitializeData
    );

    let protocolsHandler = await ethers.getContractAt(
      "ProtocolsHandler",
      protocolsHandlerProxy.address
    );

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

    // router
    let Router = await ethers.getContractFactory("Router");
    let routerImplementation = await Router.deploy();

    let initializeData = routerImplementation.interface.encodeFunctionData(
      "initialize",
      [
        protocolsHandler.address,
        priceOracle.address,
        config.address,
        rewards.address,
        sToken.address,
        dToken.address,
        deployer.address,
      ]
    );

    let proxy = await Proxy.deploy(
      routerImplementation.address,
      proxyAdmin.address,
      initializeData
    );

    let router = await ethers.getContractAt("Router", proxy.address);

    await config.setRouter(router.address);
    await protocolsHandler.setRouter(router.address);
    await rewards.transferOwnership(router.address);

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
      borrowConfig: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
        feeRate: 10000,
      },
    });

    await router.addAsset({
      underlying: usdt.address,
      decimals: 6,
      collateralable: true,
      sTokenName: "s-USDT",
      sTokenSymbol: "sUSDT",
      dTokenName: "d-USDT",
      dTokenSymbol: "dUSDT",
      borrowConfig: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
        feeRate: 10000,
      },
    });

    await router.addAsset({
      underlying: ETHAddress,
      decimals: 18,
      collateralable: true,
      sTokenName: "s-ETH",
      sTokenSymbol: "sETH",
      dTokenName: "d-ETH",
      dTokenSymbol: "dETH",
      borrowConfig: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
        feeRate: 10000,
      },
    });

    return {
      deployer: deployer,
      feeCollector: deployer,
      router: router,
      config: config,
      priceOracle: priceOracle,
      protocolsHandler: protocolsHandler,
      rewards: rewards,
      sTokenImplement: sToken,
      dTokenImplement: dToken,

      token0: token0,
      usdt: usdt,
      wETH: wETH,
      cToken0: cToken0,
    };
  }

  it("should read data properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;
    let feeCollector = deploys.feeCollector;

    expect(await router.config()).to.equal(config.address);
    expect(await router.priceOracle()).to.equal(priceOracle.address);
    expect(await router.protocols()).to.equal(protocolsHandler.address);
    expect(await router.rewards()).to.equal(rewards.address);
    expect(await router.sTokenImplement()).to.equal(sTokenImplement.address);
    expect(await router.dTokenImplement()).to.equal(dTokenImplement.address);
    expect(await router.feeCollector()).to.equal(feeCollector.address);
    expect(await router.getUnderlyings()).to.have.ordered.members([
      token0.address,
      usdt.address,
      ETHAddress,
    ]);
  });

  it("should supply properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let deployer = deploys.deployer;
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount);
    await token0.approve(router.address, supplyAmount);

    let tx = await router.supply(
      { asset: token0.address, amount: supplyAmount, to: deployer.address },
      true
    );

    let assetToken0 = await router.assets(token0.address);
    let sToken = await ethers.getContractAt("ISToken", assetToken0.sToken);

    let sBalance = await sToken.balanceOf(deployer.address);
    let balance = await sToken.scaledBalanceOf(deployer.address);

    expect(sBalance).to.equal(supplyAmount);
    expect(balance).to.within(supplyAmount.sub(1), supplyAmount);
    expect(await config.userDebtAndCollateral(deployer.address)).to.equal(2);

    await expect(tx)
      .to.emit(token0, "Transfer")
      .withArgs(deployer.address, protocolsHandler.address, supplyAmount);
    await expect(tx)
      .to.emit(sToken, "Transfer")
      .withArgs(ethers.constants.AddressZero, deployer.address, supplyAmount);
    await expect(tx)
      .to.emit(protocolsHandler, "Supplied")
      .withArgs(token0.address, supplyAmount);
    await expect(tx).to.not.emit(router, "TotalLendingsUpdated");
    await expect(tx)
      .to.emit(router, "Supplied")
      .withArgs(deployer.address, token0.address, supplyAmount);
    await expect(tx).to.not.emit(protocolsHandler, "Repayed");

    // forwoad 512 blocks
    await hre.network.provider.send("hardhat_mine", ["0x200"]);

    sBalance = await sToken.balanceOf(deployer.address);
    balance = await sToken.scaledBalanceOf(deployer.address);

    expect(sBalance).to.equal(supplyAmount);
    expect(balance).to.be.above(supplyAmount);
  });

  it("should redeem properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let deployer = deploys.deployer;
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount);
    await token0.approve(router.address, supplyAmount);

    await router.supply(
      { asset: token0.address, amount: supplyAmount, to: deployer.address },
      true
    );

    let balanceBefore = await token0.balanceOf(deployer.address);
    let tx = await router.redeem(
      {
        asset: token0.address,
        amount: supplyAmount,
        to: deployer.address,
      },
      false
    );
    let balanceAfter = await token0.balanceOf(deployer.address);

    expect(balanceAfter.sub(balanceBefore)).to.equal("200000001165687410");

    let assetToken0 = await router.assets(token0.address);
    let sToken = await ethers.getContractAt("ISToken", assetToken0.sToken);
    let sBalance = await sToken.balanceOf(deployer.address);
    let balance = await sToken.scaledBalanceOf(deployer.address);

    expect(sBalance).to.equal(0);
    expect(balance).to.equal(0);
    expect(await config.userDebtAndCollateral(deployer.address)).to.equal(0);

    await expect(tx)
      .to.emit(sToken, "Transfer")
      .withArgs(deployer.address, ethers.constants.AddressZero, supplyAmount);
    await expect(tx)
      .to.emit(protocolsHandler, "Redeemed")
      .withArgs(token0.address, "200000001165687410");
    await expect(tx).to.not.emit(router, "TotalLendingsUpdated");
    await expect(tx)
      .to.emit(router, "Redeemed")
      .withArgs(deployer.address, token0.address, "200000001165687410");
    await expect(tx).to.not.emit(protocolsHandler, "Borrowed");
  });

  it("should borrow properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let deployer = deploys.deployer;
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount;

    await usdt.mint(deployer.address, supplyAmount);
    await usdt.approve(router.address, supplyAmount);

    await router.supply(
      { asset: usdt.address, amount: supplyAmount, to: deployer.address },
      true
    );

    let tx = await router.borrow({
      asset: token0.address,
      amount: borrowAmount,
      to: deployer.address,
    });

    let assetToken0 = await router.assets(token0.address);
    let dToken = await ethers.getContractAt("IDToken", assetToken0.dToken);
    let dBalance = await dToken.balanceOf(deployer.address);
    let balance = await dToken.scaledDebtOf(deployer.address);

    expect(dBalance).to.equal(borrowAmount);
    expect(balance).to.equal(borrowAmount);

    await expect(tx)
      .to.emit(dToken, "Mint")
      .withArgs(deployer.address, borrowAmount);
    await expect(tx)
      .to.emit(protocolsHandler, "Borrowed")
      .withArgs(token0.address, borrowAmount);
    await expect(tx).to.not.emit(router, "TotalLendingsUpdated");
    await expect(tx)
      .to.emit(router, "Borrowed")
      .withArgs(deployer.address, token0.address, borrowAmount);
    await expect(tx).to.not.emit(protocolsHandler, "Redeemed");
  });

  it("should repay properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let deployer = deploys.deployer;
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount;

    await usdt.mint(deployer.address, supplyAmount);
    await usdt.approve(router.address, supplyAmount);

    await router.supply(
      { asset: usdt.address, amount: supplyAmount, to: deployer.address },
      true
    );

    await router.borrow({
      asset: token0.address,
      amount: borrowAmount,
      to: deployer.address,
    });

    await token0.approve(router.address, borrowAmount.mul(2));

    let tx = await router.repay({
      asset: token0.address,
      amount: borrowAmount.mul(2),
      to: deployer.address,
    });

    let assetToken0 = await router.assets(token0.address);
    let dToken = await ethers.getContractAt("IDToken", assetToken0.dToken);
    let dBalance = await dToken.balanceOf(deployer.address);
    let balance = await dToken.scaledDebtOf(deployer.address);

    expect(dBalance).to.equal(0);
    expect(balance).to.equal(0);

    await expect(tx)
      .to.emit(dToken, "Burn")
      .withArgs(deployer.address, borrowAmount);
    await expect(tx)
      .to.emit(protocolsHandler, "Repayed")
      .withArgs(token0.address, "100000002402017274");
    await expect(tx).to.not.emit(router, "TotalLendingsUpdated");
    await expect(tx)
      .to.emit(router, "Repayed")
      .withArgs(deployer.address, token0.address, "100000002402017274");
    await expect(tx).to.not.emit(protocolsHandler, "Supplied");
  });

  it("should supply by repay properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let deployer = deploys.deployer;
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount;

    await usdt.mint(deployer.address, supplyAmount);
    await usdt.approve(router.address, supplyAmount);

    await router.supply(
      { asset: usdt.address, amount: supplyAmount, to: deployer.address },
      true
    );

    await router.borrow({
      asset: token0.address,
      amount: borrowAmount,
      to: deployer.address,
    });

    await token0.approve(router.address, borrowAmount);

    let tx = await router.supply(
      {
        asset: token0.address,
        amount: borrowAmount,
        to: deployer.address,
      },
      true
    );

    let assetToken0 = await router.assets(token0.address);
    let sToken = await ethers.getContractAt("ISToken", assetToken0.sToken);
    let sBalance = await sToken.balanceOf(deployer.address);
    let balance = await sToken.scaledBalanceOf(deployer.address);

    expect(sBalance).to.equal(borrowAmount);
    expect(balance).to.equal(borrowAmount);

    await expect(tx)
      .to.emit(sToken, "Transfer")
      .withArgs(ethers.constants.AddressZero, deployer.address, borrowAmount);
    await expect(tx)
      .to.emit(protocolsHandler, "Repayed")
      .withArgs(token0.address, borrowAmount);
    await expect(tx)
      .to.emit(router, "TotalLendingsUpdated")
      .withArgs(token0.address, borrowAmount);
    await expect(tx)
      .to.emit(router, "Supplied")
      .withArgs(deployer.address, token0.address, borrowAmount);
    await expect(tx).to.not.emit(protocolsHandler, "Supplied");
  });

  it("should redeem by borrow properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let deployer = deploys.deployer;
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount;

    await usdt.mint(deployer.address, supplyAmount);
    await usdt.approve(router.address, supplyAmount);

    await router.supply(
      { asset: usdt.address, amount: supplyAmount, to: deployer.address },
      true
    );

    await token0.mint(deployer.address, borrowAmount);
    await token0.approve(router.address, borrowAmount);
    await router.supply(
      { asset: token0.address, amount: borrowAmount, to: deployer.address },
      true
    );

    await router.borrow({
      asset: token0.address,
      amount: borrowAmount.mul(2),
      to: deployer.address,
    });

    let tx = await router.redeem(
      {
        asset: token0.address,
        amount: borrowAmount,
        to: deployer.address,
      },
      true
    );

    let assetToken0 = await router.assets(token0.address);
    let sToken = await ethers.getContractAt("ISToken", assetToken0.sToken);
    let sBalance = await sToken.balanceOf(deployer.address);
    let balance = await sToken.scaledBalanceOf(deployer.address);
    let protocolsHandlerBalance = await token0.balanceOf(
      protocolsHandler.address
    );

    expect(sBalance).to.equal(0);
    expect(balance).to.equal(0);
    expect(protocolsHandlerBalance).to.equal(0);

    await expect(tx)
      .to.emit(sToken, "Transfer")
      .withArgs(deployer.address, ethers.constants.AddressZero, borrowAmount);
    await expect(tx)
      .to.emit(protocolsHandler, "Borrowed")
      .withArgs(token0.address, "100000000728180674");
    await expect(tx)
      .to.emit(router, "TotalLendingsUpdated")
      .withArgs(token0.address, 0);
    await expect(tx)
      .to.emit(router, "Redeemed")
      .withArgs(deployer.address, token0.address, "100000000728180674");
    await expect(tx).to.not.emit(protocolsHandler, "Redeemed");
  });

  it("should borrow by redeem properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let deployer = deploys.deployer;
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount);
    await token0.approve(router.address, supplyAmount);

    await router.supply(
      { asset: token0.address, amount: supplyAmount, to: deployer.address },
      true
    );

    let balanceBefore = await token0.balanceOf(deployer.address);
    let tx = await router.borrow({
      asset: token0.address,
      amount: borrowAmount,
      to: deployer.address,
    });

    let balanceAfter = await token0.balanceOf(deployer.address);

    let assetToken0 = await router.assets(token0.address);
    let dToken = await ethers.getContractAt("IDToken", assetToken0.dToken);
    let dBalance = await dToken.balanceOf(deployer.address);
    let balance = await dToken.scaledDebtOf(deployer.address);

    expect(dBalance).to.equal(borrowAmount);
    expect(balanceAfter.sub(balanceBefore)).to.equal(borrowAmount);

    await expect(tx)
      .to.emit(dToken, "Mint")
      .withArgs(deployer.address, borrowAmount);
    await expect(tx)
      .to.emit(protocolsHandler, "Redeemed")
      .withArgs(token0.address, borrowAmount);
    await expect(tx)
      .to.emit(router, "TotalLendingsUpdated")
      .withArgs(token0.address, borrowAmount);
    await expect(tx)
      .to.emit(router, "Borrowed")
      .withArgs(deployer.address, token0.address, borrowAmount);
    await expect(tx).to.not.emit(protocolsHandler, "Borrowed");
  });

  it("should repay by supply properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let deployer = deploys.deployer;
    let feeCollector = deploys.feeCollector;
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount);
    await token0.approve(router.address, supplyAmount);

    await router.supply(
      { asset: token0.address, amount: supplyAmount, to: deployer.address },
      true
    );

    await router.borrow({
      asset: token0.address,
      amount: borrowAmount,
      to: deployer.address,
    });

    await token0.mint(deployer.address, supplyAmount);
    await token0.approve(router.address, supplyAmount);

    let tx = await router.repay({
      asset: token0.address,
      amount: supplyAmount.mul(2),
      to: deployer.address,
    });

    let assetToken0 = await router.assets(token0.address);
    let dToken = await ethers.getContractAt("IDToken", assetToken0.dToken);
    let dBalance = await dToken.balanceOf(deployer.address);
    let balance = await dToken.scaledDebtOf(deployer.address);

    expect(dBalance).to.equal(0);
    expect(balance).to.equal(0);

    await expect(tx)
      .to.emit(dToken, "Burn")
      .withArgs(deployer.address, borrowAmount);
    await expect(tx)
      .to.emit(protocolsHandler, "Supplied")
      .withArgs(token0.address, "100000000104642312");
    await expect(tx)
      .to.emit(router, "FeeCollected")
      .withArgs(token0.address, feeCollector.address, "1056993");
    await expect(tx)
      .to.emit(router, "TotalLendingsUpdated")
      .withArgs(token0.address, 0);
    await expect(tx)
      .to.emit(router, "Repayed")
      .withArgs(deployer.address, token0.address, "100000000105699305");
    await expect(tx).to.not.emit(protocolsHandler, "Borrowed");
  });

  it("should liquidate properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);

    let deployer = deploys.deployer;
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;

    // value of supply = 2 * value of borrow
    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = ethers.BigNumber.from("20000000");

    await usdt.mint(deployer.address, supplyAmount);
    await usdt.approve(router.address, supplyAmount);

    await router.supply(
      { asset: usdt.address, amount: supplyAmount, to: deployer.address },
      true
    );

    await router.borrow({
      asset: token0.address,
      amount: borrowAmount,
      to: deployer.address,
    });

    await expect(
      router.liquidate(
        {
          asset: usdt.address,
          amount: supplyAmount,
          to: deployer.address,
        },
        {
          asset: token0.address,
          amount: 0,
          to: deployer.address,
        }
      )
    ).to.be.revertedWith("Router: Liquidate not allowed");

    await priceOracle.setAssetPrice(token0.address, 16000000000); // set price to 160.00

    await token0.approve(router.address, borrowAmount);
    let balanceBefore = await usdt.balanceOf(deployer.address);
    let tx = await router.liquidate(
      {
        asset: token0.address,
        amount: borrowAmount,
        to: deployer.address,
      },
      {
        asset: usdt.address,
        amount: 0,
        to: deployer.address,
      }
    );
    let balanceAfter = await usdt.balanceOf(deployer.address);

    // console.log(await usdt.balanceOf(protocolsHandler.address));

    expect(balanceAfter.sub(balanceBefore)).to.equal("8639999");

    let assetToken0 = await router.assets(token0.address);
    let dToken = await ethers.getContractAt("IDToken", assetToken0.dToken);
    let dBalance = await dToken.balanceOf(deployer.address);
    let debt = await dToken.scaledDebtOf(deployer.address);
    expect(dBalance.sub(borrowAmount.div(2))).to.within(0, 1);
    expect(debt).to.equal("50000002402017275");

    let assetUSDT = await router.assets(usdt.address);
    let sToken = await ethers.getContractAt("ISToken", assetUSDT.sToken);
    let sBalance = await sToken.balanceOf(deployer.address);
    let balance = await sToken.scaledBalanceOf(deployer.address);

    expect(sBalance).to.equal("11360003");
    expect(balance).to.equal("11360004");

    await expect(tx)
      .to.emit(dToken, "Burn")
      .withArgs(deployer.address, borrowAmount.div(2));
    await expect(tx)
      .to.emit(sToken, "Transfer")
      .withArgs(deployer.address, ethers.constants.AddressZero, "8639997");
    await expect(tx)
      .to.emit(router, "Repayed")
      .withArgs(deployer.address, token0.address, "50000002402017274");
    await expect(tx)
      .to.emit(protocolsHandler, "Redeemed")
      .withArgs(usdt.address, "8639999");
    await expect(tx)
      .to.emit(router, "Redeemed")
      .withArgs(deployer.address, usdt.address, "8639999");
  });
});
