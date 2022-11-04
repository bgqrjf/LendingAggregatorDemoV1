const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const aave = require("./aave/deploy");
const compound = require("./compound/deploy");
const m = require("mocha-logger");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("ProtocolsHandler tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  async function ProtocolsHandlerTestFixture() {
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

    let Strategy = await ethers.getContractFactory("Strategy");
    let strategy = await Strategy.deploy(700000);

    let ProtocolsHandler = await ethers.getContractFactory("ProtocolsHandler");
    let protocolsHandler = await ProtocolsHandler.deploy([], strategy.address);

    await protocolsHandler.setRouter(aaveContracts.signer.address);
    await protocolsHandler.addProtocol(aaveHandler.address);
    await protocolsHandler.addProtocol(compoundHandler.address);

    return {
      deployer: aaveContracts.signer,
      aPool: aPool,
      aaveHandler: aaveHandler,
      cToken0: cToken0,
      cUSDT: cUSDT,
      cETH: cETH,
      compoundHandler: compoundHandler,
      token0: token0,
      usdt: usdt,
      wETH: wETH,
      strategy: strategy,
      protocolsHandler: protocolsHandler,
    };
  }

  it("should read data properly", async () => {
    const deploys = await loadFixture(ProtocolsHandlerTestFixture);

    let protocolsHandler = deploys.protocolsHandler;
    let deployer = deploys.deployer;

    let strategy = deploys.strategy;
    let aaveHandler = deploys.aaveHandler;
    let compoundHandler = deploys.compoundHandler;

    expect(await protocolsHandler.router()).to.equal(deployer.address);
    expect(await protocolsHandler.strategy()).to.equal(strategy.address);
    expect(await protocolsHandler.getProtocols()).to.have.members([
      aaveHandler.address,
      compoundHandler.address,
    ]);
  });

  it("should supply properly", async () => {
    const deploys = await loadFixture(ProtocolsHandlerTestFixture);

    let protocolsHandler = deploys.protocolsHandler;
    let deployer = deploys.deployer;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;
    let aPool = deploys.aPool;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);

    await token0.mint(protocolsHandler.address, supplyAmount);
    await protocolsHandler.supply(token0.address, supplyAmount, [0, 0], 0);

    let [amounts, totalAmount] = await protocolsHandler.totalSupplied(
      token0.address
    );
    expect(totalAmount).to.within(supplyAmount.sub(1), supplyAmount);
  });

  it("should redeem properly", async () => {
    const deploys = await loadFixture(ProtocolsHandlerTestFixture);

    let protocolsHandler = deploys.protocolsHandler;
    let deployer = deploys.deployer;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;
    let aPool = deploys.aPool;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(2);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);

    await token0.mint(protocolsHandler.address, supplyAmount);
    await protocolsHandler.supply(token0.address, supplyAmount, [0, 0], 0);

    let [amounts, totalAmount] = await protocolsHandler.totalSupplied(
      token0.address
    );
    await protocolsHandler.redeem(
      token0.address,
      supplyAmount,
      amounts,
      totalAmount,
      deployer.address
    );

    [, totalAmount] = await protocolsHandler.totalSupplied(token0.address);
    expect(totalAmount).to.equal(0);
  });

  it("should borrow properly", async () => {
    const deploys = await loadFixture(ProtocolsHandlerTestFixture);

    let protocolsHandler = deploys.protocolsHandler;
    let deployer = deploys.deployer;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;
    let aPool = deploys.aPool;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(5);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    await token0.mint(protocolsHandler.address, supplyAmount);
    await protocolsHandler.supply(token0.address, supplyAmount, [0, 0], 0);

    await protocolsHandler.borrow([
      token0.address,
      borrowAmount,
      deployer.address,
    ]);

    let [, totalAmount] = await protocolsHandler.totalBorrowed(token0.address);
    expect(totalAmount).to.equal(borrowAmount);
  });

  it("should repay properly", async () => {
    const deploys = await loadFixture(ProtocolsHandlerTestFixture);

    let protocolsHandler = deploys.protocolsHandler;
    let deployer = deploys.deployer;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;
    let aPool = deploys.aPool;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(5);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    await token0.mint(protocolsHandler.address, supplyAmount.mul(2));
    await protocolsHandler.supply(token0.address, supplyAmount, [0, 0], 0);

    await protocolsHandler.borrow([
      token0.address,
      borrowAmount,
      deployer.address,
    ]);

    let aaveHandler = deploys.aaveHandler;
    let compoundHandler = deploys.compoundHandler;

    let debtAAVE = await aaveHandler.debtOf(
      token0.address,
      protocolsHandler.address
    );
    let debtCompound = await compoundHandler.debtOf(
      token0.address,
      protocolsHandler.address
    );

    let [, totalAmount] = await protocolsHandler.totalBorrowed(token0.address);

    await protocolsHandler.repay([
      token0.address,
      borrowAmount,
      deployer.address,
    ]);

    [, totalAmount] = await protocolsHandler.totalBorrowed(token0.address);

    expect(totalAmount).to.equal(237339448);
  });

  it("should simulateLendings properly", async () => {
    const deploys = await loadFixture(ProtocolsHandlerTestFixture);

    let protocolsHandler = deploys.protocolsHandler;
    let deployer = deploys.deployer;
    let token0 = deploys.token0;
    let cToken0 = deploys.cToken0;
    let aPool = deploys.aPool;

    let borrowAmount = ethers.BigNumber.from("100000000000000000");
    let supplyAmount = borrowAmount.mul(5);

    await token0.mint(deployer.address, supplyAmount.mul(4));
    await token0.approve(cToken0.address, supplyAmount.mul(2));
    await token0.approve(aPool.address, supplyAmount.mul(2));
    await cToken0.mint(supplyAmount);
    await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    await cToken0.borrow(borrowAmount);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

    await token0.mint(protocolsHandler.address, supplyAmount);
    await protocolsHandler.supply(token0.address, supplyAmount, [0, 0], 0);

    await protocolsHandler.borrow([
      token0.address,
      borrowAmount,
      deployer.address,
    ]);

    await protocolsHandler.simulateSupply(token0.address, supplyAmount);
    await protocolsHandler.simulateBorrow(token0.address, supplyAmount);

    let lendings = await protocolsHandler.simulateLendings(
      token0.address,
      supplyAmount
    );

    await hre.network.provider.send("hardhat_mine", ["0x200"]);

    lendings = await protocolsHandler.simulateLendings(
      token0.address,
      supplyAmount
    );

    expect(lendings).to.equal(ethers.BigNumber.from("500000205306291327"));
  });

  it("should addProtocol properly", async () => {
    const deploys = await loadFixture(ProtocolsHandlerTestFixture);

    let protocolsHandler = deploys.protocolsHandler;
    let deployer = deploys.deployer;

    await protocolsHandler.addProtocol(deployer.address);

    let protocols = await protocolsHandler.getProtocols();

    expect(protocols.length).to.equal(3);
    expect(protocols[2]).to.equal(deployer.address);
  });
});
