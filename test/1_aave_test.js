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
  let borrower0;
  let borrower1;

  let providerAAVE;
  let priceOracle;

  beforeEach(async () =>{
    const ERC20Token = await ethers.getContractFactory(`MockERC20`);
    token0 = await ERC20Token.deploy("Mock token0", "Token0", 18);
    usdt = await ERC20Token.deploy("Mock USDT", "USDT", 6);

    // deploy AAVE contracts
    let aaveContracts = await aave.deployContracts({token0: token0, usdt: usdt});
    deployer = aaveContracts.signer;
    aPool = aaveContracts.pool;
    wETH = aaveContracts.wETH;
    aOracle = aaveContracts.priceOracle;

    let ProviderAAVE = await ethers.getContractFactory("AAVELogic");
    providerAAVE = await ProviderAAVE.deploy(aPool.address, wETH.address);

    //////////////////////////// deploy aggregator contracts
    let PriceOracle = await ethers.getContractFactory("MockPriceOracle");
    priceOracle = await PriceOracle.deploy();
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
    
    [supplier0, supplier1, borrower0, borrower1] = await ethers.getSigners();
  })

  describe("AAVE tests", function (){
    describe("supply tests", function(){
      it("should supply ERC20 properly", async() =>{
        await token0.mint(supplier0.address, 1000000);
        await token0.connect(supplier0).approve(pool.address, 1000000);
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

    describe("withdraw tests", function(){
      it("should withdraw ERC20 properly", async() =>{
        let token0Amount =  ethers.BigNumber.from("1000000000000000000");
        await token0.mint(supplier0.address, token0Amount);
        await token0.connect(supplier0).approve(pool.address, token0Amount);
        await pool.supply(token0.address, supplier0.address, token0Amount, true);

        let asset = await router.assets(token0.address);
        let sToken = await ethers.getContractAt("SToken", asset.sToken);
        let tx = await sToken.withdraw(supplier1.address, (await sToken.balanceOf(supplier0.address)).div(10), false);
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
        await token0.connect(supplier0).approve(pool.address, token0Amount);
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

    describe("borrow tests", function(){
      it("should borrow ERC20 properly", async() =>{
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

        let routerBalance = await token0.balanceOf(router.address);
        expect(routerBalance).to.equal(0);

        let reserve = await aPool.getReserveData(token0.address);
        let aPoolBalance = await token0.balanceOf(reserve.aTokenAddress);
        expect(aPoolBalance).to.equal("9400000000000000000000");

        // check dToken
        let dTokenBalance = await dToken.balanceOf(borrower0.address)
        expect(dTokenBalance).to.equal(borrowAmount);

        let vToken0 = await ethers.getContractAt("VariableDebtToken", reserve.variableDebtTokenAddress)
        let routerVToken0Balance = await vToken0.balanceOf(router.address);
        expect(routerVToken0Balance).to.equal(borrowAmount);
      });

      it("should borrow ETH properly", async() =>{
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
        expect(balance1New.sub(balance1)).to.equal(borrowAmount);

        let routerBalance = await provider.getBalance(router.address);
        expect(routerBalance).to.equal(0);

        let reserve = await aPool.getReserveData(wETH.address);
        let aPoolBalance = await wETH.balanceOf(reserve.aTokenAddress);
        expect(aPoolBalance).to.equal("949000000000000000000");
        
        // check dToken
        let dTokenBalance = await dToken.balanceOf(borrower0.address)
        expect(dTokenBalance).to.equal(borrowAmount);

        let vToken0 = await ethers.getContractAt("VariableDebtToken", reserve.variableDebtTokenAddress)
        let routerVToken0Balance = await vToken0.balanceOf(router.address);
        expect(routerVToken0Balance).to.equal(borrowAmount);
      });

      it("should borrow ERC20 twice properly", async() =>{
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
        await dToken.connect(borrower0).borrow(borrower0.address, borrowAmount.div(2));
        let tx = await dToken.connect(borrower0).borrow(borrower0.address, borrowAmount.div(2));
        let receipt = await tx.wait();
        m.log("gas used:", receipt.gasUsed);

        let amountReceived0 = await token0.balanceOf(borrower0.address);
        expect(amountReceived0).to.equal(borrowAmount);

        let routerBalance = await token0.balanceOf(router.address);
        expect(routerBalance).to.equal(0);

        let reserve = await aPool.getReserveData(token0.address);
        let aPoolBalance = await token0.balanceOf(reserve.aTokenAddress);
        expect(aPoolBalance).to.equal("9400000000000000000000");

        // check dToken
        let dTokenBalance = await dToken.balanceOf(borrower0.address)
        expect(dTokenBalance).to.equal("99999999999629125241");

        let vToken0 = await ethers.getContractAt("VariableDebtToken", reserve.variableDebtTokenAddress)
        let routerVToken0Balance = await vToken0.balanceOf(router.address);
        expect(routerVToken0Balance).to.equal("100000000000370874760");
      });
    })
    
    describe("repay tests", function(){
      it("should repay ERC20 properly", async() =>{
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

        await token0.mint(borrower0.address, 5006809261);
        await token0.connect(borrower0).approve(pool.address, borrowAmount.add(5006809261));
        let tx = await pool.connect(borrower0).repay(token0.address, borrower0.address, borrowAmount);
        let receipt = await tx.wait();
        m.log("gas used:", receipt.gasUsed);

        let routerBalance = await token0.balanceOf(router.address);
        expect(routerBalance).to.equal(0);

        let reserve = await aPool.getReserveData(token0.address);
        let aPoolBalance = await token0.balanceOf(reserve.aTokenAddress);
        expect(aPoolBalance).to.equal("9500000000004450497121");

        // check dToken
        let dTokenBalance = await dToken.balanceOf(borrower0.address)
        expect(dTokenBalance).to.equal(0);

        let vToken0 = await ethers.getContractAt("VariableDebtToken", reserve.variableDebtTokenAddress)
        let routerVToken0Balance = await vToken0.balanceOf(router.address);
        expect(routerVToken0Balance).to.equal(0);
      });

      it("should repay ETH properly", async() =>{
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

        let routerBalance = await provider.getBalance(router.address);
        expect(routerBalance).to.equal(0);

        let reserve = await aPool.getReserveData(wETH.address);
        let aPoolBalance = await wETH.balanceOf(reserve.aTokenAddress);
        expect(aPoolBalance).to.equal("950000000000001483499");

        // check dToken
        let dTokenBalance = await dToken.balanceOf(borrower0.address)
        expect(dTokenBalance).to.equal(0);

        let vToken0 = await ethers.getContractAt("VariableDebtToken", reserve.variableDebtTokenAddress)
        let routerVToken0Balance = await vToken0.balanceOf(router.address);
        expect(routerVToken0Balance).to.equal(0);
      });

      it("should repay twice ERC20 properly", async() =>{
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

        await token0.mint(borrower0.address, 5424043365);
        await token0.connect(borrower0).approve(pool.address, borrowAmount.add(5424043365));
        await pool.connect(borrower0).repay(token0.address, borrower0.address, borrowAmount.div(2));
        let tx = await pool.connect(borrower0).repay(token0.address, borrower0.address, borrowAmount.div(2));
        let receipt = await tx.wait();
        m.log("gas used:", receipt.gasUsed);

        let routerBalance = await token0.balanceOf(router.address);
        expect(routerBalance).to.equal(0);

        let reserve = await aPool.getReserveData(token0.address);
        let aPoolBalance = await token0.balanceOf(reserve.aTokenAddress);
        expect(aPoolBalance).to.equal("9500000000004821371880");

        // check dToken
        let dTokenBalance = await dToken.balanceOf(borrower0.address)
        expect(dTokenBalance).to.equal(0);

        let vToken0 = await ethers.getContractAt("VariableDebtToken", reserve.variableDebtTokenAddress)
        let routerVToken0Balance = await vToken0.balanceOf(router.address);
        expect(routerVToken0Balance).to.equal(0);
      });
    });
  })
});