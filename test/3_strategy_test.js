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

    await compoundHandler.updateCTokenList(cToken0.address, 18);
    await compoundHandler.updateCTokenList(cUSDT.address, 6);

    let Strategy = await ethers.getContractFactory("Strategy");
    let strategy = await Strategy.deploy(700000);

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

  it("should call minSupplyNeeded correctly", async () => {});

  it("should call maxRedeemAllowed correctly", async () => {});

  it("should call maxBorrowAllowed correctly", async () => {});

  it("should call minRepayNeeded correctly", async () => {});

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

    let supplyStrategy = await strategy.getSupplyStrategy(
      [aaveHandler.address, compoundHandler.address],
      token0.address,
      [supplyAmount, supplyAmount],
      supplyAmount.mul(2).add(1000)
    );

    // redeem and supply
    if (supplyStrategy.redeemAmounts[0] > 0) {
      await aPool.withdraw(
        token0.address,
        supplyStrategy.redeemAmounts[0],
        deployer.address
      );
    }
    if (supplyStrategy.redeemAmounts[1] > 0) {
      await cToken0.redeem(supplyStrategy.redeemAmounts[1]);
    }

    if (supplyStrategy.supplyAmounts[0] > 0) {
      await aPool.supply(
        token0.address,
        supplyStrategy.supplyAmounts[0],
        deployer.address,
        0
      );
    }

    if (supplyStrategy.supplyAmounts[1] > 0) {
      await cToken0.mint(supplyStrategy.supplyAmounts[1]);
    }

    let aaveSupplyRate = await aaveHandler.getCurrentSupplyRate(token0.address);
    let compoundSupplyRate = await compoundHandler.getCurrentSupplyRate(
      token0.address
    );

    expect(aaveSupplyRate.sub(compoundSupplyRate)).to.be.within(-2, +2);
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

    // assume aave and compound supply > 0
    await aPool.supply(token0.address, supplyAmounts[0], deployer.address, 0);
    await cToken0.mint(supplyAmounts[1]);

    let aaveSupplyRate = await aaveHandler.getCurrentSupplyRate(token0.address);
    let compoundSupplyRate = await compoundHandler.getCurrentSupplyRate(
      token0.address
    );

    expect(aaveSupplyRate.sub(compoundSupplyRate)).to.be.within(-2, +2);
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
    await aPool.borrow(
      token0.address,
      borrowAmounts[0],
      2,
      0,
      deployer.address
    );
    await cToken0.borrow(borrowAmounts[1]);

    let aaveBorrowRate = await aaveHandler.getCurrentBorrowRate(token0.address);
    let compoundBorrowRate = await compoundHandler.getCurrentBorrowRate(
      token0.address
    );

    expect(aaveBorrowRate.sub(compoundBorrowRate)).to.be.within(-2, +2);
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
    await aPool.borrow(
      token0.address,
      borrowAmounts[0],
      2,
      0,
      deployer.address
    );
    await cToken0.borrow(borrowAmounts[1]);

    let aaveBorrowRate = await aaveHandler.getCurrentBorrowRate(token0.address);
    let compoundBorrowRate = await compoundHandler.getCurrentBorrowRate(
      token0.address
    );

    // m.log(aaveBorrowRate, compoundBorrowRate);
    expect(aaveBorrowRate.sub(compoundBorrowRate)).to.be.within(-2, +2);
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

    expect(repayAmounts[0].add(repayAmounts[1])).to.equal(borrowAmount);

    await aPool.repay(token0.address, repayAmounts[0], 2, deployer.address);
    await cToken0.repayBorrow(repayAmounts[1]);

    let aaveBorrowRate = await aaveHandler.getCurrentBorrowRate(token0.address);
    let compoundBorrowRate = await compoundHandler.getCurrentBorrowRate(
      token0.address
    );

    expect(aaveBorrowRate.sub(compoundBorrowRate)).to.be.within(-2, +2);
  });
});
