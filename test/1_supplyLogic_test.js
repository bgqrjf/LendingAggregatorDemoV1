const { expect } = require("chai");
const { ethers, waffle} = require("hardhat");
const aave = require("./aave/deploy");

describe("DepositLogic Tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  let token0;
  let wETH;
  let router;
  let pool;

  let aPool
  let deployer;
  let supplier;
  let borrower;

  beforeEach(async () =>{
    // deploy AAVE contracts
    let aaveContracts = await aave.deployContracts();
    deployer = aaveContracts.signer;
    token0 = aaveContracts.token0;
    aPool = await ethers.getContractAt("IAAVEPool", aaveContracts.poolAddress);
    wETH = aaveContracts.wETH;

    let ProviderAAVE = await ethers.getContractFactory("AAVELogic");
    let providerAAVE = await ProviderAAVE.deploy(aPool.address, wETH.address);

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
    
    [supplier, borrower] = await ethers.getSigners();
  })

  describe("supply test", function(){
    it("should supply ERC20 properly", async() =>{
      await token0.mint(supplier.address, 1000000);
      await token0.approve(pool.address, 1000000, {from: supplier.address});
      let tx = await pool.supply(token0.address, supplier.address, 1000000, true);
      let receipt = await tx.wait();

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
      let sTokenBalance = await sToken.balanceOf(supplier.address)
      expect(sTokenBalance).to.equal(1000000);
    })

    it("should supply ETH properly", async() =>{
      let tx = await pool.supplyETH(supplier.address, true, {value: 1000000});
      let receipt = await tx.wait();

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
      let sTokenBalance = await sToken.balanceOf(supplier.address)
      expect(sTokenBalance).to.equal(1000000);
    })
  })
});