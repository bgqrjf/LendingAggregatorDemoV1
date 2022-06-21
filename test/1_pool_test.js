const { expect } = require("chai");
const { ethers, waffle} = require("hardhat");
const aave = require("./aave/deploy");
const m = require('mocha-logger');

describe("DepositLogic Tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  let token0;
  let usdt;
  let wETH;
  let router;
  let pool;
  let aOracle;

  let aPool
  let deployer;
  let supplier0;
  let supplier1;

  let providerAAVE;

  beforeEach(async () =>{
    // deploy AAVE contracts
    let aaveContracts = await aave.deployContracts();
    deployer = aaveContracts.signer;
    token0 = aaveContracts.token0;
    usdt = aaveContracts.usdt;
    aPool = aaveContracts.pool;
    wETH = aaveContracts.wETH;
    aOracle = aaveContracts.priceOracle;

    let ProviderAAVE = await ethers.getContractFactory("AAVELogic");
    providerAAVE = await ProviderAAVE.deploy(aPool.address, wETH.address);

    //////////////////////////// deploy aggregator contracts
    let PriceOracle = await ethers.getContractFactory("PriceOracle");
    let priceOracle = await PriceOracle.deploy();
    await priceOracle.setAssetPrice(token0.address, 10000000000); // set price to 100.00
    
    let Strategy = await ethers.getContractFactory("Strategy");
    let strategy = await Strategy.deploy(800000); // set MaxLTV ratio to 70%

    let Factory = await ethers.getContractFactory("Factory");
    let factory = await Factory.deploy();


    let Router = await ethers.getContractFactory("Router");
    router = await Router.deploy([providerAAVE.address], priceOracle.address, strategy.address, factory.address, 50000); // set TreasuryRatio to 5%
    await router.addAsset({
      underlying: token0.address, 
      decimals: 18, 
      collateralable: true, 
      sTokenName: "supply Token0", 
      sTokenSymbol: "sToken0", 
      dTokenName: "debt Token0", 
      dTokenSymbol: "dToken0",
      borrowConfig: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 80000, 
      }
    });
    await router.addAsset({
      underlying: usdt.address, 
      decimals: 18, 
      collateralable: true, 
      sTokenName: "supply USDT", 
      sTokenSymbol: "sUSDT", 
      dTokenName: "debt USDT", 
      dTokenSymbol: "dUSDT",
      borrowConfig: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 80000, 
      }
    });
    await router.addAsset({
      underlying: ETHAddress, 
      decimals: 18, 
      collateralable: true, 
      sTokenName: "supply weth", 
      sTokenSymbol: "sWETH", 
      dTokenName: "debt weth", 
      dTokenSymbol: "dWETH",
      borrowConfig: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 80000, 
      }
    });

    let Pool = await ethers.getContractFactory("contracts/Pool.sol:Pool");
    pool = await Pool.deploy(router.address);
    
    [supplier0, supplier1] = await ethers.getSigners();
  })

  describe("supply test", function(){
    it("should supply ERC20 properly", async() =>{
      await token0.mint(supplier0.address, 1000000);
      await token0.approve(pool.address, 1000000, {from: supplier0.address});
      let tx = await pool.supply(token0.address, supplier0.address, 1000000, true);
      let receipt = await tx.wait();
      m.log("gas used:",receipt.gasUsed);

      // check underlying flow
      let routerBalance = await token0.balanceOf(router.address);
      expect(routerBalance).to.equal(0);

      let treasury = await router.treasury();
      let treasuryBalance = await token0.balanceOf(treasury);
      expect(treasuryBalance).to.equal(50000);

      let reserve = await aPool.getReserveData(token0.address);
      let aPoolBalance = await token0.balanceOf(reserve.aTokenAddress);
      expect(aPoolBalance).to.equal(950000);

      // check sToken
      let asset = await router.assets(token0.address);
      let sToken = await ethers.getContractAt("SToken", asset.sToken);
      let sTokenBalance = await sToken.balanceOf(supplier0.address)
      expect(sTokenBalance).to.equal(1000000);

      let aToken0 = await ethers.getContractAt("AToken", reserve.aTokenAddress)
      let routerAToken0Balance = await aToken0.balanceOf(router.address);
      expect(routerAToken0Balance).to.equal(950000);
    });

    it("should supply ETH properly", async() =>{
      let tx = await pool.supplyETH(supplier0.address, true, {value: 1000000});
      let receipt = await tx.wait();
      m.log("gas used:",receipt.gasUsed);

      let routerBalance = await provider.getBalance(router.address)
      expect(routerBalance).to.equal(0);

      let treasury = await router.treasury();
      let treasuryBalance = await provider.getBalance(treasury);
      expect(treasuryBalance).to.equal(50000);

      let reserve = await aPool.getReserveData(wETH.address);
      let aPoolBalance = await wETH.balanceOf(reserve.aTokenAddress);
      expect(aPoolBalance).to.equal(950000);

      let asset = await router.assets(ETHAddress);
      let sToken = await ethers.getContractAt("SToken", asset.sToken);
      let sTokenBalance = await sToken.balanceOf(supplier0.address)
      expect(sTokenBalance).to.equal(1000000);

      let aWETH = await ethers.getContractAt("AToken", reserve.aTokenAddress)
      let routerAWETHBalance = await aWETH.balanceOf(router.address);
      expect(routerAWETHBalance).to.equal(950000);
    });

    it("should supply twice properly", async() =>{
      await token0.mint(supplier0.address, 2000000);
      await token0.connect(supplier0).approve(pool.address, 2000000);
      await pool.supply(token0.address, supplier0.address, 1000000, true);
      let tx = await pool.supply(token0.address, supplier1.address, 1000000, false);
      let receipt = await tx.wait();
      m.log("gas used:",receipt.gasUsed);

      // check underlying flow
      let routerBalance = await token0.balanceOf(router.address);
      expect(routerBalance).to.equal(0);

      let treasury = await router.treasury();
      let treasuryBalance = await token0.balanceOf(treasury);
      expect(treasuryBalance).to.equal(100000);

      let reserve = await aPool.getReserveData(token0.address);
      let aPoolBalance = await token0.balanceOf(reserve.aTokenAddress);
      expect(aPoolBalance).to.equal(1900000);

      // check sToken
      let asset = await router.assets(token0.address);
      let sToken = await ethers.getContractAt("SToken", asset.sToken);
      let sTokenBalance0 = await sToken.balanceOf(supplier0.address)
      let sTokenBalance1 = await sToken.balanceOf(supplier1.address)
      expect(sTokenBalance0).to.equal(1000000);
      expect(sTokenBalance1).to.equal(1000000);

      let aToken0 = await ethers.getContractAt("AToken", reserve.aTokenAddress)
      let routerAToken0Balance = await aToken0.balanceOf(router.address);
      expect(routerAToken0Balance).to.equal(1900000);


      let MockLibraryTest = await ethers.getContractFactory("MockLibraryTest");
      let mockLibraryTest = await MockLibraryTest.deploy();
      let config = await ethers.getContractAt("Config", await router.config());

      let bitMap0 = await config.userDebtAndCollateral(supplier0.address);
      let collateralable0 = await mockLibraryTest.isUsingAsCollateral(bitMap0, asset.index);
      expect(collateralable0).to.equal(true);

      let bitMap1 = await config.userDebtAndCollateral(supplier1.address);
      let collateralable1 = await mockLibraryTest.isUsingAsCollateral(bitMap1, asset.index);
      expect(collateralable1).to.equal(false);
    });
  });

  describe("withdraw test", function(){
    it("should withdraw ERC20 properly", async() =>{
      let token0Amount =  ethers.BigNumber.from("1000000000000000000");
      await token0.mint(supplier0.address, token0Amount);
      await token0.approve(pool.address, token0Amount, {from: supplier0.address});
      await pool.supply(token0.address, supplier0.address, token0Amount, true);

      let asset = await router.assets(token0.address);
      let sToken = await ethers.getContractAt("SToken", asset.sToken);
      let tx = await sToken.withdraw(supplier1.address, token0Amount.div(10), false);
      let receipt = await tx.wait();
      m.log("gas used:",receipt.gasUsed);

      let amountReceived = await token0.balanceOf(supplier1.address);
      expect(amountReceived).to.equal("100000000000000000")

      // check underlying flow
      let routerBalance = await token0.balanceOf(router.address);
      expect(routerBalance).to.equal(0);

      let treasury = await router.treasury();
      let treasuryBalance = await token0.balanceOf(treasury);
      expect(treasuryBalance).to.equal(0);

      let reserve = await aPool.getReserveData(token0.address);
      let aPoolBalance = await token0.balanceOf(reserve.aTokenAddress);
      expect(aPoolBalance).to.equal("900000000000000000");

      // check sToken
      let sTokenBalance = await sToken.balanceOf(supplier0.address)
      expect(sTokenBalance).to.equal("900000000000000000");

      let aToken0 = await ethers.getContractAt("AToken", reserve.aTokenAddress)
      let routerAToken0Balance = await aToken0.balanceOf(router.address);
      expect(routerAToken0Balance).to.equal("900000000000000000");
    });

    it("should withdraw ETH properly", async() =>{
      let wethAmount =  ethers.BigNumber.from("1000000000000000000");
      await pool.supplyETH(supplier0.address, true, {value: wethAmount});

      let asset = await router.assets(ETHAddress);
      let sToken = await ethers.getContractAt("SToken", asset.sToken);
      let supplier1balance0 = await provider.getBalance(supplier1.address);
      let tx = await sToken.withdraw(supplier1.address, wethAmount.div(10), false);
      let receipt = await tx.wait();
      m.log("gas used:",receipt.gasUsed);

      let supplier1balance1 = await provider.getBalance(supplier1.address);
      expect(supplier1balance1.sub(supplier1balance0)).to.equal("100000000000000000")

      // check underlying flow
      let routerBalance = await provider.getBalance(router.address);
      expect(routerBalance).to.equal(0);

      let treasury = await router.treasury();
      let treasuryBalance = await provider.getBalance(treasury);
      expect(treasuryBalance).to.equal(0);

      let reserve = await aPool.getReserveData(wETH.address);
      let aPoolBalance = await wETH.balanceOf(reserve.aTokenAddress);
      expect(aPoolBalance).to.equal("900000000000000000");

      // check sToken
      let sTokenBalance = await sToken.balanceOf(supplier0.address)
      expect(sTokenBalance).to.equal("900000000000000000");

      let aWETH = await ethers.getContractAt("AToken", reserve.aTokenAddress)
      let routeraWETHBalance = await aWETH.balanceOf(router.address);
      expect(routeraWETHBalance).to.equal("900000000000000000");
    });

    it("should withdraw twice properly", async() =>{
      let token0Amount =  ethers.BigNumber.from("1000000000000000000");
      await token0.mint(supplier0.address, token0Amount);
      await token0.approve(pool.address, token0Amount, {from: supplier0.address});
      await pool.supply(token0.address, supplier0.address, token0Amount, true);

      let asset = await router.assets(token0.address);
      let sToken = await ethers.getContractAt("SToken", asset.sToken);
      await sToken.withdraw(supplier1.address, token0Amount.div(10), false);
      let tx = await sToken.withdraw(supplier0.address, token0Amount.div(10), false);
      let receipt = await tx.wait();
      m.log("gas used:",receipt.gasUsed);

      let amountReceived0 = await token0.balanceOf(supplier0.address);
      expect(amountReceived0).to.equal("100000000000000000")
      let amountReceived1 = await token0.balanceOf(supplier1.address);
      expect(amountReceived1).to.equal("100000000000000000")

      // check underlying flow
      let routerBalance = await token0.balanceOf(router.address);
      expect(routerBalance).to.equal(0);

      let treasury = await router.treasury();
      let treasuryBalance = await token0.balanceOf(treasury);
      expect(treasuryBalance).to.equal(0);

      let reserve = await aPool.getReserveData(token0.address);
      let aPoolBalance = await token0.balanceOf(reserve.aTokenAddress);
      expect(aPoolBalance).to.equal("800000000000000000");

      // check sToken
      let sTokenBalance = await sToken.balanceOf(supplier0.address)
      expect(sTokenBalance).to.equal("800000000000000000");

      let aToken0 = await ethers.getContractAt("AToken", reserve.aTokenAddress)
      let routerAToken0Balance = await aToken0.balanceOf(router.address);
      expect(routerAToken0Balance).to.equal("800000000000000000");
    });
  });
});