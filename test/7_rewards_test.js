const { expect } = require("chai");
const { ethers, waffle, upgrades } = require("hardhat");
const aave = require("./aave/deploy");
const compound = require("./compound/deploy");
const transparentProxy = require("./utils/transparentProxy");
const m = require("mocha-logger");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Rewards tests", function () {
    const provider = waffle.provider;
    const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

    async function RewardsTestFixture() {
        const [deployer, Alice,Bob,Caro] = await ethers.getSigners();
    
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
    
        let borrowAmount = ethers.utils.parseUnits("10", "ether");
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
    
        await wETH.deposit({ value: supplyAmount });
        await wETH.approve(aPool.address, supplyAmount);
    
        await cETH.mint({ value: supplyAmount });
        await aPool.supply(wETH.address, supplyAmount, deployer.address, 0);
        await cETH.borrow(borrowAmount);
        await aPool.borrow(wETH.address, borrowAmount, 2, 0, deployer.address);
        await wETH.withdraw(borrowAmount);
    
        // deploy aggregator contracts
        // strategy
        let Strategy = await ethers.getContractFactory("Strategy");
        let strategy = await Strategy.deploy();
        await strategy.setMaxLTV(700000);
    
        // protocolsHandler
        const proxyAdmin = await transparentProxy.deployProxyAdmin();
        let protocolsHandler = await transparentProxy.deployProxy({
          implementationFactory: "ProtocolsHandler",
          initializeParams: [[], strategy.address, true],
          proxyAdmin: proxyAdmin,
        });
    
        let AAVEHandler = await ethers.getContractFactory("AAVELogic");
        let aaveHandler = await AAVEHandler.deploy(
          protocolsHandler.address,
          aPool.address,
          wETH.address
        );
    
        let CompoundHandler = await ethers.getContractFactory("CompoundLogic");
        let compoundHandler = await CompoundHandler.deploy(
          protocolsHandler.address,
          comptroller.address,
          cETH.address,
          comp.address,
          { gasLimit: 5000000 }
        );
    
        await compoundHandler.updateCTokenList(cToken0.address);
        await compoundHandler.updateCTokenList(cUSDT.address);
    
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
        let config = await transparentProxy.deployProxy({
          implementationFactory: "Config",
          proxyAdmin: proxyAdmin,
        });
    
        await config.transferOwnership(deployer.address);
    
        // rewards
        let rewards = await transparentProxy.deployProxy({
          implementationFactory: "Rewards",
          initializeParams: [deployer.address],
          proxyAdmin: proxyAdmin,
        });
    
  
        // sToken Proxy
        let sTokenProxy = await transparentProxy.deployProxy({
            implementationFactory: "SToken",
            initializeParams: [usdt.address, rewards.address,"sUSDT","sUSDT" ],
            proxyAdmin: proxyAdmin,
          });
    
        // dToken Proxy
        let dTokenProxy = await transparentProxy.deployProxy({
            implementationFactory: "DToken",
            initializeParams: [usdt.address, rewards.address,"dUSDT","dUSDT","10000" ],
            proxyAdmin: proxyAdmin,
          });
    
        
        await rewards.connect(deployer).addRewardAdmin(sTokenProxy.address);
        await rewards.connect(deployer).addRewardAdmin(dTokenProxy.address);
        await rewards.connect(deployer).addProtocol(aaveHandler.address)
        await rewards.connect(deployer).addProtocol(compoundHandler.address)
        await usdt.mint(compoundHandler.address, supplyAmount.mul(2));   //40 USDT  直接去cToken mint

        await usdt.mint(Alice.address, supplyAmount.mul(2));  
        await usdt.mint(Bob.address, supplyAmount.mul(2));  
    
        await compoundHandler.connect(deployer).supply(usdt.address,ethers.utils.parseEther('40'))
        
    



        return {
          deployer: deployer,
          alice: Alice,
          bob:Bob,
          config: config,
          priceOracle: priceOracle,
          protocolsHandler: protocolsHandler,
          rewards: rewards,
          sTokenProxy :sTokenProxy,
          dTokenProxy:dTokenProxy,
          token0: token0,
          usdt: usdt,
          wETH: wETH,
          cToken0: cToken0,
          cUSDT: cUSDT,
          cETH: cETH,
        };
      }

    



    describe("rewards SToken  tests", function () {

 
        it("should start farm token0 via SToken mint", async () => {
          const {
              deployer,
              alice,
              bob,
            sTokenProxy,
            dTokenProxy,
              rewards,
            usdt
          } = await loadFixture(RewardsTestFixture);
  
            await sTokenProxy.connect(deployer).mint(alice.address, ethers.utils.parseUnits("1", "ether"), ethers.utils.parseUnits("0", "ether"));
            let aliceSTokenbalance = await sTokenProxy.balanceOf(alice.address)
            m.log(aliceSTokenbalance.toString())
            await hre.network.provider.send("hardhat_mine", ["0x200"]);
            await rewards.getUserRewards(usdt.address,)

            await sTokenProxy.connect(deployer).mint(bob.address, ethers.utils.parseUnits("1", "ether"), ethers.utils.parseUnits("1.1", "ether"));
            let bobSTokenbalance = await sTokenProxy.balanceOf(bob.address)
            m.log(bobSTokenbalance.toString())
            
        });
  

      });
});