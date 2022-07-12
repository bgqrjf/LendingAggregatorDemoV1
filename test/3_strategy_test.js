const { expect } = require("chai");
const { ethers, waffle} = require("hardhat");
const aave = require("./aave/deploy");
const compound = require("./compound/deploy");
const m = require('mocha-logger');

describe("Strategy Tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  let token0;
  let usdt;
  let wETH;
  let router;
  let pool;
  let strategy;
  let providers

  let aPool
  let deployer;
  let providerAAVE;

  let comptroller;
  let providerCompound;
  let cToken0;
  let cUSDT;
  let cETH;
  let comp;

  let supplier0;
  let supplier1;
  let borrower0;
  let borrower1;

  let token0SupplyAmount

  beforeEach(async () =>{
    const ERC20Token = await ethers.getContractFactory(`MockERC20`);
    token0 = await ERC20Token.deploy("Mock token0", "Token0", 18);
    usdt = await ERC20Token.deploy("Mock USDT", "USDT", 6);

    // deploy AAVE contracts
    let aaveContracts = await aave.deployContracts({token0: token0, usdt: usdt});
    deployer = aaveContracts.signer;
    aPool = aaveContracts.pool;
    wETH = aaveContracts.wETH;

    let ProviderAAVE = await ethers.getContractFactory("AAVELogic");
    providerAAVE = await ProviderAAVE.deploy(aPool.address, wETH.address, wETH.address);

    // deploy Compound contracts
    let compContracts = await compound.deployContracts({token0: token0, usdt: usdt});
    comptroller = compContracts.comptroller;
    cToken0 = compContracts.cToken0;
    cUSDT = compContracts.cUSDT;
    cETH = compContracts.cETH;
    comp = compContracts.comp;

    let ProviderCompound = await ethers.getContractFactory("CompoundLogic");
    providerCompound = await ProviderCompound.deploy(comptroller.address, cETH.address, comp.address, {gasLimit: 5000000});

    await providerCompound.updateCTokenList(cToken0.address, 18);
    await providerCompound.updateCTokenList(cUSDT.address, 6);

    //////////////////////////// deploy aggregator contracts
    let PriceOracle = await ethers.getContractFactory("MockPriceOracle");
    let priceOracle = await PriceOracle.deploy();
    await priceOracle.addAsset(token0.address, 18);
    await priceOracle.addAsset(usdt.address, 6);
    await priceOracle.addAsset(ETHAddress, 18);
    await priceOracle.setAssetPrice(token0.address, 10000000000); // set price to 100.00
    await priceOracle.setAssetPrice(usdt.address, 100000000); // set price to 1.00
    await priceOracle.setAssetPrice(ETHAddress, 200000000000); // set price to 2000.00
    
    let Strategy = await ethers.getContractFactory("Strategy");
    strategy = await Strategy.deploy(700000); // set MaxLTV ratio to 70%

    let Factory = await ethers.getContractFactory("Factory");
    let factory = await Factory.deploy();

    providers = [providerAAVE.address, providerCompound.address];

    let Router = await ethers.getContractFactory("Router");
    router = await Router.deploy(providers, priceOracle.address, strategy.address, factory.address); 
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
    
    [supplier0, supplier1, borrower0, borrower1] = await ethers.getSigners();

    token0SupplyAmount = new ethers.BigNumber.from("1000000000000000000000000"); // 1000000 
      
    await token0.mint(supplier0.address, token0SupplyAmount.mul(3));

    await token0.approve(aPool.address, token0SupplyAmount);
    await aPool.supply(token0.address, token0SupplyAmount, supplier0.address, 0);
    m.log(`supplied ${token0SupplyAmount} token0 to AAVE directly`)

    await aPool.setUserUseReserveAsCollateral(token0.address, true);
    m.log(`set token0 as collateral asset`)

    let borrowAmount = token0SupplyAmount.div(10).mul(5);
    await aPool.borrow(token0.address, borrowAmount, 2, 0, supplier0.address);
    m.log(`borrow ${borrowAmount} token0 from AAVE directly`);

    await token0.approve(cToken0.address, token0SupplyAmount);
    await cToken0.mint(token0SupplyAmount);
    m.log(`supplied ${token0SupplyAmount} token0 to Compound directly`)

    await comptroller.enterMarkets([token0.address]);
    await cToken0.borrow(borrowAmount);
    m.log(`borrow ${borrowAmount} token0 from Compound directly`);
  });

  describe("strategy tests", function (){
    it("should supply with strategy properly", async() =>{
      let aaveSupplyRate = await providerAAVE.getCurrentSupplyRate(token0.address);
      m.log("aaveSupplyRate:", aaveSupplyRate);
      let compoundSupplyRate = await providerCompound.getCurrentSupplyRate(token0.address);
      m.log("compoundSupplyRate:", compoundSupplyRate);

      await token0.connect(supplier0).approve(pool.address, token0SupplyAmount);
      let supplyAmount = token0SupplyAmount.div(2)
      let strategyForSupply = await strategy.getSupplyStrategy([providerAAVE.address, providerCompound.address], token0.address, supplyAmount.div(100).mul(95), router.address);
      m.log(`preview strategy for supply ${supplyAmount} token0 via Lending Aggregator`)
      m.log("aave Supply:", strategyForSupply[0]);
      m.log("compound Supply:", strategyForSupply[1]);

      let tx = await pool.supply(token0.address, supplier0.address, token0SupplyAmount.div(2), true);
      let receipt = await tx.wait();
      m.log(`supply ${supplyAmount} via Lending Aggregator`)
      m.log("gas Used:", receipt.gasUsed);

      aaveSupplyRate = await providerAAVE.getCurrentSupplyRate(token0.address);
      m.log("aaveSupplyRate:", aaveSupplyRate);
      compoundSupplyRate = await providerCompound.getCurrentSupplyRate(token0.address);
      m.log("compoundSupplyRate:", compoundSupplyRate);
    });

    it("should withdraw with strategy properly", async() =>{
      await token0.connect(supplier0).approve(pool.address, token0SupplyAmount);
      await pool.supply(token0.address, supplier0.address, token0SupplyAmount, true);
      m.log(`supply ${token0SupplyAmount} via Lending Aggregator`)

      // to change interest rate on cToken
      await cToken0.borrow(token0SupplyAmount.div(10).mul(1));
      m.log(`borrow ${token0SupplyAmount.div(10)} from cToken0 again to alter compound interest rate`)

      let aaveSupplyRate = await providerAAVE.getCurrentSupplyRate(token0.address);
      m.log("aaveSupplyRate:", aaveSupplyRate);
      let compoundSupplyRate = await providerCompound.getCurrentSupplyRate(token0.address);
      m.log("compoundSupplyRate:", compoundSupplyRate);

      let asset = await router.assets(token0.address);
      let sToken = await ethers.getContractAt("SToken", asset.sToken);
      let sBalance = await sToken.balanceOf(supplier0.address);
      m.log("sBalance:", sBalance);

      let withdrawAmount = sBalance.div(2)
      let tx = await router.withdraw(token0.address, supplier1.address, withdrawAmount, false);
      let receipt = await tx.wait();
      m.log(`withdraw ${withdrawAmount} via Lending Aggregator to supplier1`)
      let log = router.interface.parseLog(receipt.logs[receipt.logs.length - 1]);
      m.log("gas used:",receipt.gasUsed);
      m.log("total withdrawed:", log.args.amount);
      m.log("aave amount:", log.args.amounts[0]);
      m.log("compound amount:", log.args.amounts[1]);

      aaveSupplyRate = await providerAAVE.getCurrentSupplyRate(token0.address);
      m.log("aaveSupplyRate:", aaveSupplyRate);
      compoundSupplyRate = await providerCompound.getCurrentSupplyRate(token0.address);
      m.log("compoundSupplyRate:", compoundSupplyRate);

      let amountReceived  = await token0.balanceOf(supplier1.address);
      m.log("amountReceived:", amountReceived)
    });

    it("should borrow with strategy properly", async() => {
      await token0.connect(supplier0).approve(pool.address, token0SupplyAmount);
      await pool.supply(token0.address, borrower0.address, token0SupplyAmount, true);
      m.log(`supply ${token0SupplyAmount} via Lending Aggregator`)

      let asset = await router.assets(token0.address);
      let dToken = await ethers.getContractAt("DToken", asset.dToken);

      let aaveBorrowRate = await providerAAVE.getCurrentBorrowRate(token0.address);
      m.log("aaveBorrowRate:", aaveBorrowRate);
      let compoundBorrowRate = await providerCompound.getCurrentBorrowRate(token0.address);
      m.log("compoundBorrowRate:", compoundBorrowRate);

      let borrowAmount = token0SupplyAmount.div(2)
      let tx = await router.connect(borrower0).borrow(token0.address, borrower0.address, borrowAmount);
      let receipt = await tx.wait();
      m.log(`borrow ${borrowAmount} via Lending Aggregator to borrow0`)
      m.log("gas used:",receipt.gasUsed);

      aaveBorrowRate = await providerAAVE.getCurrentBorrowRate(token0.address);
      m.log("aaveBorrowRate:", aaveBorrowRate);
      compoundBorrowRate = await providerCompound.getCurrentBorrowRate(token0.address);
      m.log("compoundBorrowRate:", compoundBorrowRate);

    });

    it("should repay with strategy properly", async() => {
      await token0.connect(supplier0).approve(pool.address, token0SupplyAmount);
      await pool.supply(token0.address, borrower0.address, token0SupplyAmount, true);
      m.log(`supply ${token0SupplyAmount} via Lending Aggregator`)

      let asset = await router.assets(token0.address);
      let dToken = await ethers.getContractAt("DToken", asset.dToken);

      let borrowAmount = token0SupplyAmount.div(2)
      await router.connect(borrower0).borrow(token0.address, borrower0.address, borrowAmount);

      m.log(`borrow ${borrowAmount} via Lending Aggregator to borrow0`)

      await cToken0.borrow(token0SupplyAmount.div(10).mul(1));
      m.log(`borrow ${token0SupplyAmount.div(10)} from cToken0 again to alter compound interest rate`)

      aaveBorrowRate = await providerAAVE.getCurrentBorrowRate(token0.address);
      m.log("aaveBorrowRate:", aaveBorrowRate);
      compoundBorrowRate = await providerCompound.getCurrentBorrowRate(token0.address);
      m.log("compoundBorrowRate:", compoundBorrowRate);

      let dBalance = await dToken.balanceOf(borrower0.address);
      m.log("dBalance:", dBalance);

      await token0.mint(borrower0.address, dBalance)
      await token0.connect(borrower0).approve(pool.address, dBalance.mul(2))

      let repayAmount = dBalance.div(2);
      let tx = await pool.connect(borrower0).repay(token0.address, borrower0.address, repayAmount);
      m.log(`repay ${repayAmount} via Lending Aggregator to borrow0`)
      let receipt = await tx.wait();
      m.log("gas used:",receipt.gasUsed);
      let log = router.interface.parseLog(receipt.logs[receipt.logs.length - 1]);
      m.log("aave repayed:", log.args.amounts[0]);
      m.log("compound repayed:", log.args.amounts[1]);

      aaveBorrowRate = await providerAAVE.getCurrentBorrowRate(token0.address);
      m.log("aaveBorrowRate:", aaveBorrowRate);
      compoundBorrowRate = await providerCompound.getCurrentBorrowRate(token0.address);
      m.log("compoundBorrowRate:", compoundBorrowRate);
    });
  });
});