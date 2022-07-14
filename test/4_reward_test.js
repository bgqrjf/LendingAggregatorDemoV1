const { expect } = require("chai");
const { ethers, waffle, config} = require("hardhat");
const compound = require("./compound/deploy");
const m = require('mocha-logger');

describe("reward tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  let token0;
  let usdt;
  let comptroller;
  let providerCompound;
  let cToken0;
  let cUSDT;
  let cETH;
  let comp;
  let priceOracle;

  let router;
  let pool;

  beforeEach(async () =>{
    const ERC20Token = await ethers.getContractFactory(`MockERC20`);
    token0 = await ERC20Token.deploy("Mock token0", "Token0", 18);
    usdt = await ERC20Token.deploy("Mock USDT", "USDT", 6);

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
    router = await Router.deploy([providerCompound.address], priceOracle.address, strategy.address, factory.address);
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

    let token0SupplyAmount = new ethers.BigNumber.from("1000000000000000000000000");
    await token0.mint(supplier0.address, token0SupplyAmount.mul(3));

    let borrowAmount = token0SupplyAmount.div(10).mul(5);

    await token0.approve(cToken0.address, token0SupplyAmount);
    await cToken0.mint(token0SupplyAmount);
    m.log(`supplied ${token0SupplyAmount} token0 to Compound directly`)

    await comptroller.enterMarkets([token0.address]);
    await cToken0.borrow(borrowAmount);
    m.log(`borrow ${borrowAmount} token0 from Compound directly`);
  })

  it("should claim comp properly", async() => {
    await token0.connect(supplier0).approve(pool.address, "1000000000000000000000000");
    
    m.log("index:", await comptroller.compSupplyState(cToken0.address));
    m.log("rewardData", await router.rewardData(supplier0.address, providerCompound.address, token0.address));
    await pool.supply(token0.address, supplier0.address, "500000000000000000000000", true);
    await pool.supply(token0.address, borrower0.address, "500000000000000000000000", true);

    m.log("index:", await comptroller.compSupplyState(cToken0.address));
    m.log("rewardData", await router.rewardData(supplier0.address, providerCompound.address, token0.address));
    
    await router.connect(borrower0).borrow(token0.address, borrower0.address, "100000000000000000000000");
    await router.withdraw(token0.address, supplier1.address, "300000000000000000000000", false);
    m.log("index:", await comptroller.compSupplyState(cToken0.address));
    m.log("rewardData", await router.rewardData(supplier0.address, providerCompound.address, token0.address));


    await hre.network.provider.send("hardhat_mine", ["0x" + (2102400).toString(16)]);

    await comptroller["claimComp(address)"](router.address);
    m.log("comp Debts is: ", await comp.balanceOf(router.address));

    // withdraw from comp

    await router.claimRewardToken(providerCompound.address, supplier0.address, token0.address);
    // await router.connect(supplier1).claimRewardToken(providerCompound.address, supplier1.address, token0.address);
    await router.connect(borrower0).claimRewardToken(providerCompound.address, borrower0.address, token0.address);

    m.log("user received", await comp.balanceOf(supplier0.address));
    m.log("comp Debts: ", await comp.balanceOf(router.address));
    m.log("rewardData", await router.rewardData(supplier0.address, providerCompound.address, token0.address));

  })
})