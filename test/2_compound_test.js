const { expect } = require("chai");
const { ethers, waffle} = require("hardhat");
const compound = require("./compound/deploy");
const m = require('mocha-logger');

describe("DepositLogic Tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  let token0;
  let usdt;
  let comptroller;
  let providerCompound;
  let cToken0;
  let cUSDT;
  let cETH;

  let router;
  let pool;

  beforeEach(async () =>{
    const ERC20Token = await ethers.getContractFactory(`MockERC20`);
    token0 = await ERC20Token.deploy("Mock token0", "Token0", 18);
    usdt = await ERC20Token.deploy("Mock USDT", "USDT", 6);

    // deploy Compound contracts
    let compContracts = await compound.deployContracts({token0: token0, usdt: usdt});
    comptrollerLens = compContracts.comptrollerLens;
    comptroller = compContracts.comptroller;
    cToken0 = compContracts.cToken0;
    cUSDT = compContracts.cUSDT;
    cETH = compContracts.cETH;

    let ProviderCompound = await ethers.getContractFactory("CompoundLogic");
    providerCompound = await ProviderCompound.deploy(comptroller.address, cETH.address, {gasLimit: 5000000});

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
    let strategy = await Strategy.deploy(800000); // set MaxLTV ratio to 70%

    let Factory = await ethers.getContractFactory("Factory");
    let factory = await Factory.deploy();


    let Router = await ethers.getContractFactory("Router");
    router = await Router.deploy([providerCompound.address], priceOracle.address, strategy.address, factory.address, 50000); // set TreasuryRatio to 5%
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
  })

  describe("compound tests", function(){
    describe("supply tests", function(){
      it("should supply ERC20 to compound properly", async() =>{
        await token0.mint(supplier0.address, 1000000);
        await token0.connect(supplier0).approve(pool.address, 1000000);
        let tx = await pool.supply(token0.address, supplier0.address, 1000000, true);
        let receipt = await tx.wait();
        m.log("gas used:",receipt.gasUsed);

        let cTokenBalance = await token0.balanceOf(cToken0.address);
        expect(cTokenBalance).to.equal(950000);

        let routercToken0Balance = await cToken0.balanceOf(router.address);
        expect(routercToken0Balance).to.equal(950000);
      });

      it("should supply ETH to compound properly", async() =>{
        let tx = await pool.supplyETH(supplier0.address, true, {value: 1000000});
        let receipt = await tx.wait();
        m.log("gas used:",receipt.gasUsed);

        let cTokenBalance = await provider.getBalance(cETH.address);
        expect(cTokenBalance).to.equal(950000);

        let routercToken0Balance = await cETH.balanceOf(router.address);
        expect(routercToken0Balance).to.equal(950000);
      });
    });

    describe("withdraw tests", function(){
      it("should withdraw ERC20 from compound properly", async() =>{
        await token0.mint(supplier0.address, 1000000);
        await token0.connect(supplier0).approve(pool.address, 1000000);
        await pool.supply(token0.address, supplier0.address, 1000000, true);

        let asset = await router.assets(token0.address);
        let sToken = await ethers.getContractAt("SToken", asset.sToken);
        let tx = await sToken.withdraw(supplier1.address, 1000000, false);
        let receipt = await tx.wait();
        m.log("gas used:",receipt.gasUsed);

        let cTokenBalance = await token0.balanceOf(cToken0.address);
        expect(cTokenBalance).to.equal(0);

        let routercToken0Balance = await cToken0.balanceOf(router.address);
        expect(routercToken0Balance).to.equal(0);
      });

      it("should withdraw ETH from compound properly", async() =>{
        await pool.supplyETH(supplier0.address, true, {value: 1000000});

        let asset = await router.assets(ETHAddress);
        let sToken = await ethers.getContractAt("SToken", asset.sToken);
        let tx = await sToken.withdraw(supplier1.address, 1000000, false);
        let receipt = await tx.wait();
        m.log("gas used:",receipt.gasUsed);

        let cTokenBalance = await provider.getBalance(cToken0.address);
        expect(cTokenBalance).to.equal(0);

        let routercETHBalance = await cETH.balanceOf(router.address);
        expect(routercETHBalance).to.equal(0);
      });
    });

    describe("borrow tests", function(){
      it ("should borrow ERC20 from compound properly", async() => {
        let token0SupplyAmount = new ethers.BigNumber.from("10000000000000000000000"); // 10000 token0
        await token0.mint(supplier0.address, token0SupplyAmount);
        await token0.connect(supplier0).approve(pool.address, token0SupplyAmount);
        await pool.supply(token0.address, supplier0.address, token0SupplyAmount, false);

        let usdtColletralAmount = 10000000000 // 10000 usdt
        await usdt.mint(borrower0.address, usdtColletralAmount);
        await usdt.connect(borrower0).approve(pool.address, usdtColletralAmount);
        await pool.connect(borrower0).supply(usdt.address, borrower0.address, usdtColletralAmount, true);     
        
        let assetToBorrow = await router.assets(token0.address);
        let dToken = await ethers.getContractAt("DToken", assetToBorrow.dToken);
        let borrowAmount = new ethers.BigNumber.from("100000000000000000000");

        let tx = await dToken.connect(borrower0).borrow(borrower0.address, borrowAmount);
        let receipt = await tx.wait();
        m.log("gas used:", receipt.gasUsed);

        let amountReceived0 = await token0.balanceOf(borrower0.address);
        expect(amountReceived0).to.equal(borrowAmount);

        let cTokenBalance = await token0.balanceOf(cToken0.address);
        expect(cTokenBalance).to.equal("9400000000000000000000");
      });
     
      it ("should borrow ETH from compound properly", async() => {
        await pool.connect(supplier0).supplyETH(supplier0.address, true, {value: ethers.BigNumber.from("1000000000000000000000")});

        let usdtColletralAmount = 20000000000 // 20000 usdt
        await usdt.mint(borrower0.address, usdtColletralAmount);
        await usdt.connect(borrower0).approve(pool.address, usdtColletralAmount);
        await pool.connect(borrower0).supply(usdt.address, borrower0.address, usdtColletralAmount, true);     
        let assetToBorrow = await router.assets(ETHAddress);
        let dToken = await ethers.getContractAt("DToken", assetToBorrow.dToken);

        let borrowAmount = ethers.BigNumber.from("1000000000000000000");
        let balance1 = await provider.getBalance(borrower1.address);
        let tx = await dToken.connect(borrower0).borrow(borrower1.address, borrowAmount);
        let receipt = await tx.wait();
        m.log("gas used:", receipt.gasUsed);
        
        let balance1New = await provider.getBalance(borrower1.address);
        expect(balance1New).to.equal(balance1.add(borrowAmount));

        let cTokenBalance = await provider.getBalance(cETH.address);
        expect(cTokenBalance).to.equal("949000000000000000000");
      });
    })

    describe("repay tests", function(){
      it ("should repay ERC20 to compound properly", async() => {
        let token0SupplyAmount = new ethers.BigNumber.from("10000000000000000000000"); // 10000 token0
        await token0.mint(supplier0.address, token0SupplyAmount);
        await token0.connect(supplier0).approve(pool.address, token0SupplyAmount);
        await pool.supply(token0.address, supplier0.address, token0SupplyAmount, false);

        let usdtColletralAmount = 10000000000 // 10000 usdt
        await usdt.mint(borrower0.address, usdtColletralAmount);
        await usdt.connect(borrower0).approve(pool.address, usdtColletralAmount);
        await pool.connect(borrower0).supply(usdt.address, borrower0.address, usdtColletralAmount, true);     
        
        let assetToBorrow = await router.assets(token0.address);
        let dToken = await ethers.getContractAt("DToken", assetToBorrow.dToken);

        let borrowAmount = new ethers.BigNumber.from("100000000000000000000");
        await dToken.connect(borrower0).borrow(borrower0.address, borrowAmount);

        await token0.mint(borrower0.address, 3191840903339);
        await token0.connect(borrower0).approve(pool.address, borrowAmount.add(3191840903339));
        let tx = await pool.connect(borrower0).repay(token0.address, borrower0.address, borrowAmount);
        let receipt = await tx.wait();
        m.log("gas used:", receipt.gasUsed);

        let cTokenBalance = await token0.balanceOf(cToken0.address);
        expect(cTokenBalance).to.equal("9500000003191840903339");
      });

      it ("should repay ETH to compound properly", async() => {
        await pool.connect(supplier0).supplyETH(supplier0.address, true, {value: ethers.BigNumber.from("1000000000000000000000")});

        let usdtColletralAmount = 20000000000 // 20000 usdt
        await usdt.mint(borrower0.address, usdtColletralAmount);
        await usdt.connect(borrower0).approve(pool.address, usdtColletralAmount);
        await pool.connect(borrower0).supply(usdt.address, borrower0.address, usdtColletralAmount, true);     
        let assetToBorrow = await router.assets(ETHAddress);
        let dToken = await ethers.getContractAt("DToken", assetToBorrow.dToken);

        let borrowAmount = ethers.BigNumber.from("1000000000000000000");
        await dToken.connect(borrower0).borrow(borrower1.address, borrowAmount);

        let tx = await pool.connect(borrower0).repayETH(borrower0.address, borrowAmount, {value: ethers.BigNumber.from("11000000000000000000")});
        let receipt = await tx.wait();
        m.log("gas used:", receipt.gasUsed);

        let cTokenBalance = await provider.getBalance(cETH.address);
        expect(cTokenBalance).to.equal("950000000009625590802");
      })
    })
  });
});
