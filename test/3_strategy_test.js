const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const aave = require("./aave/deploy");
const compound = require("./compound/deploy");
const m = require("mocha-logger");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Strategy tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  async function StrategyTestFixture() {
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
      ethers.constants.AddressZero,
      aPool.address,
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
      ethers.constants.AddressZero,
      comptroller.address,
      cETH.address,
      comp.address,
      ethers.constants.AddressZero,
      { gasLimit: 5000000 }
    );

    await compoundHandler.updateCTokenList(cToken0.address);
    await compoundHandler.updateCTokenList(cUSDT.address);

    let Strategy = await ethers.getContractFactory("Strategy");
    let strategy = await Strategy.deploy();
    await strategy.setMaxLTV(700000);

    return {
      deployer: aaveContracts.signer,
      aPool: aPool,
      aOracle: aOracle,
      aaveHandler: aaveHandler,
      comptroller: comptroller,
      cToken0: cToken0,
      cUSDT: cUSDT,
      cETH: cETH,
      comp: comp,
      compoundHandler: compoundHandler,
      token0: token0,
      usdt: usdt,
      wETH: wETH,
      strategy: strategy,
    };
  }

  it("should read data properly", async () => {
    const deploys = await loadFixture(StrategyTestFixture);

    let strategy = deploys.strategy;

    expect(await strategy.maxLTV()).to.equal(700000);
  });

  it("should getSupplyStrategy properly", async () => {
    const deploys = await loadFixture(StrategyTestFixture);

    let deployer = deploys.deployer;
    let strategy = deploys.strategy;
    let aaveHandler = deploys.aaveHandler;
    let compoundHandler = deploys.compoundHandler;
    let aPool = deploys.aPool;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    let supplyAmounts = await strategy.getSupplyStrategy(
      [aaveHandler.address, compoundHandler.address],
      token0.address,
      supplyAmount
    );

    let aaveSupplyRate = await aaveHandler.getCurrentSupplyRate(token0.address);
    let compoundSupplyRate = await compoundHandler.getCurrentSupplyRate(
      token0.address
    );

    expect(aaveSupplyRate).to.be.below(compoundSupplyRate);
    expect(supplyAmounts[0]).to.equal(0);
    expect(supplyAmounts[1]).to.equal(supplyAmount);
  });

  it("should getSimulateSupplyStrategy properly", async () => {
    const deploys = await loadFixture(StrategyTestFixture);

    let deployer = deploys.deployer;
    let strategy = deploys.strategy;
    let aaveHandler = deploys.aaveHandler;
    let compoundHandler = deploys.compoundHandler;
    let aPool = deploys.aPool;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    let supplyAmounts = await strategy.getSimulateSupplyStrategy(
      [aaveHandler.address, compoundHandler.address],
      token0.address,
      supplyAmount
    );

    let aaveSupplyRate = await aaveHandler.getCurrentSupplyRate(token0.address);
    let compoundSupplyRate = await compoundHandler.getCurrentSupplyRate(
      token0.address
    );

    expect(aaveSupplyRate).to.be.below(compoundSupplyRate);
    expect(supplyAmounts[0]).to.equal(0);
    expect(supplyAmounts[1]).to.equal(supplyAmount);
  });

  it("should getRedeemStrategy properly", async () => {
    const deploys = await loadFixture(StrategyTestFixture);

    let deployer = deploys.deployer;
    let strategy = deploys.strategy;
    let aaveHandler = deploys.aaveHandler;
    let compoundHandler = deploys.compoundHandler;
    let aPool = deploys.aPool;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount.mul(2));
    await aPool.supply(
      token0.address,
      supplyAmount.mul(2),
      deployer.address,
      0
    );
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    let redeemAmounts = await strategy.getRedeemStrategy(
      [aaveHandler.address, compoundHandler.address],
      token0.address,
      supplyAmount
    );

    let aaveSupplyRate = await aaveHandler.getCurrentSupplyRate(token0.address);
    let compoundSupplyRate = await compoundHandler.getCurrentSupplyRate(
      token0.address
    );

    expect(aaveSupplyRate).to.be.below(compoundSupplyRate);
    expect(redeemAmounts[0]).to.equal(supplyAmount);
    expect(redeemAmounts[1]).to.equal(0);
  });

  it("should getBorrowStrategy properly", async () => {
    const deploys = await loadFixture(StrategyTestFixture);

    let deployer = deploys.deployer;
    let strategy = deploys.strategy;
    let aaveHandler = deploys.aaveHandler;
    let compoundHandler = deploys.compoundHandler;
    let aPool = deploys.aPool;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(5);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    let borrowAmounts = await strategy.getBorrowStrategy(
      [aaveHandler.address, compoundHandler.address],
      token0.address,
      borrowAmount
    );
    let aaveBorrowRate = await aaveHandler.getCurrentBorrowRate(token0.address);
    let compoundBorrowRate = await compoundHandler.getCurrentBorrowRate(
      token0.address
    );

    expect(aaveBorrowRate).to.be.below(compoundBorrowRate);
    expect(borrowAmounts[0]).to.equal(borrowAmount);
    expect(borrowAmounts[1]).to.equal(0);
  });

  it("should getSimulateBorrowStrategy properly", async () => {
    const deploys = await loadFixture(StrategyTestFixture);

    let deployer = deploys.deployer;
    let strategy = deploys.strategy;
    let aaveHandler = deploys.aaveHandler;
    let compoundHandler = deploys.compoundHandler;
    let aPool = deploys.aPool;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(5);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    let borrowAmounts = await strategy.getSimulateBorrowStrategy(
      [aaveHandler.address, compoundHandler.address],
      token0.address,
      borrowAmount
    );
    let aaveBorrowRate = await aaveHandler.getCurrentBorrowRate(token0.address);
    let compoundBorrowRate = await compoundHandler.getCurrentBorrowRate(
      token0.address
    );

    expect(aaveBorrowRate).to.be.below(compoundBorrowRate);
    expect(borrowAmounts[0]).to.equal(borrowAmount);
    expect(borrowAmounts[1]).to.equal(0);
  });

  it("should getRepayStrategy properly", async () => {
    const deploys = await loadFixture(StrategyTestFixture);

    let deployer = deploys.deployer;
    let strategy = deploys.strategy;
    let aaveHandler = deploys.aaveHandler;
    let compoundHandler = deploys.compoundHandler;
    let aPool = deploys.aPool;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(5);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    let repayAmounts = await strategy.getRepayStrategy(
      [aaveHandler.address, compoundHandler.address],
      token0.address,
      borrowAmount
    );

    let aaveBorrowRate = await aaveHandler.getCurrentBorrowRate(token0.address);
    let compoundBorrowRate = await compoundHandler.getCurrentBorrowRate(
      token0.address
    );

    expect(aaveBorrowRate).to.be.below(compoundBorrowRate);
    expect(repayAmounts[0]).to.equal(0);
    expect(repayAmounts[1]).to.equal(borrowAmount);
  });

  it("should getRebalanceStrategy properly", async () => {
    const deploys = await loadFixture(StrategyTestFixture);

    let deployer = deploys.deployer;
    let strategy = deploys.strategy;
    let aaveHandler = deploys.aaveHandler;
    let compoundHandler = deploys.compoundHandler;
    let aPool = deploys.aPool;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(5);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);
    await cToken0.borrow(borrowAmount);

    let result = await strategy.getRebalanceStrategy(
      [aaveHandler.address, compoundHandler.address],
      token0.address
    );

    let aaveSupplyRate = await aaveHandler.getCurrentSupplyRate(token0.address);
    let compoundSupplyRate = await compoundHandler.getCurrentSupplyRate(
      token0.address
    );

    if (result.redeemAmounts[0] > 0) {
      await aPool.withdraw(
        token0.address,
        result.redeemAmounts[0],
        deployer.address
      );
    }
    if (result.redeemAmounts[1] > 0) {
      await cToken0.redeem(result.redeemAmounts[1]);
    }
    if (result.supplyAmounts[0] > 0) {
      await token0.approve(aPool.address, result.supplyAmounts[0]);
      await aPool.supply(
        token0.address,
        result.supplyAmounts[0],
        deployer.address,
        0
      );
    }
    if (result.supplyAmounts[1] > 0) {
      await token0.approve(cToken0.address, result.supplyAmounts[1]);
      await cToken0.mint(result.supplyAmounts[1]);
    }

    aaveSupplyRate = await aaveHandler.getCurrentSupplyRate(token0.address);
    compoundSupplyRate = await compoundHandler.getCurrentSupplyRate(
      token0.address
    );

    expect(aaveSupplyRate).to.be.within(
      compoundSupplyRate.sub(1),
      compoundSupplyRate.add(1)
    );
  });
});
