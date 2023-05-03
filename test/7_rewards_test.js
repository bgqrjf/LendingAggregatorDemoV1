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
    const [deployer, feeCollector] = await ethers.getSigners();

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

    // rewards
    let rewards = await transparentProxy.deployProxy({
      implementationFactory: "Rewards",
      initializeParams: [protocolsHandler.address],
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
      rewards.address,
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

    // sToken
    let SToken = await ethers.getContractFactory("SToken");
    let sToken = await SToken.deploy();

    // dToken
    let DToken = await ethers.getContractFactory("DToken");
    let dToken = await DToken.deploy();

    // router
    let SupplyLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/SupplyLogic.sol:SupplyLogic"
    );
    let supplyLogic = await SupplyLogic.deploy();

    let RedeemLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/RedeemLogic.sol:RedeemLogic"
    );
    let redeemLogic = await RedeemLogic.deploy();

    let BorrowLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/BorrowLogic.sol:BorrowLogic"
    );
    let borrowLogic = await BorrowLogic.deploy();

    let RepayLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/RepayLogic.sol:RepayLogic"
    );
    let repayLogic = await RepayLogic.deploy();

    let LiquidateLogic = await ethers.getContractFactory(
      "contracts/libraries/externals/LiquidateLogic.sol:LiquidateLogic"
    );
    let liquidateLogic = await LiquidateLogic.deploy();

    let router = await transparentProxy.deployProxy({
      implementationFactory: "Router",
      libraries: {
        SupplyLogic: supplyLogic.address,
        RedeemLogic: redeemLogic.address,
        BorrowLogic: borrowLogic.address,
        RepayLogic: repayLogic.address,
        LiquidateLogic: liquidateLogic.address,
      },
      initializeParams: [
        protocolsHandler.address,
        priceOracle.address,
        config.address,
        rewards.address,
        sToken.address,
        dToken.address,
        ethers.constants.AddressZero,
        feeCollector.address,
      ],
      proxyAdmin: proxyAdmin,
    });

    await config.setRouter(router.address);
    await protocolsHandler.transferOwnership(router.address);
    await rewards.transferOwnership(router.address);

    await router.addProtocol(aaveHandler.address);
    await router.addProtocol(compoundHandler.address);

    await router.addAsset({
      underlying: token0.address,
      decimals: 18,
      collateralable: true,
      sTokenName: "s-token0",
      sTokenSymbol: "sT0",
      dTokenName: "d-token0",
      dTokenSymbol: "dT0",
      config: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
      },
      feeRate: 10000,
      maxReserve: 0,
      executeSupplyThreshold: 0,
    });

    await router.addAsset({
      underlying: usdt.address,
      decimals: 6,
      collateralable: true,
      sTokenName: "s-USDT",
      sTokenSymbol: "sUSDT",
      dTokenName: "d-USDT",
      dTokenSymbol: "dUSDT",
      config: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
      },
      feeRate: 10000,
      maxReserve: 0,
      executeSupplyThreshold: 0,
    });

    await router.addAsset({
      underlying: ETHAddress,
      decimals: 18,
      collateralable: true,
      sTokenName: "s-ETH",
      sTokenSymbol: "sETH",
      dTokenName: "d-ETH",
      dTokenSymbol: "dETH",
      config: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
      },
      feeRate: 10000,
      maxReserve: 0,
      executeSupplyThreshold: 0,
    });

    return {
      deployer: deployer,
      router: router,

      protocolsHandler: protocolsHandler,
      rewards: rewards,
      sTokenImplement: sToken,
      dTokenImplement: dToken,
      aaveLogic: aaveHandler,
      compoundLogic: compoundHandler,
      comp: comp,

      token0: token0,
      usdt: usdt,
      cToken0: cToken0,
      cUSDT: cUSDT,
    };
  }

  async function supply(deployer, router, token, supplyAmount) {
    let sToken;
    let dToken;
    if (token == null) {
      let asset = await router.assets(ETHAddress);
      sToken = await ethers.getContractAt("ISToken", asset.sToken);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.supply(
        { asset: ETHAddress, amount: supplyAmount, to: deployer.address },
        true,
        true,
        { value: supplyAmount }
      );
    } else {
      await token.mint(deployer.address, supplyAmount);
      await token.approve(router.address, supplyAmount);

      let asset = await router.assets(token.address);
      sToken = await ethers.getContractAt("ISToken", asset.sToken);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.supply(
        { asset: token.address, amount: supplyAmount, to: deployer.address },
        true,
        true
      );
    }

    return { sToken: sToken, dToken: dToken };
  }

  async function redeem(deployer, router, token, supplyAmount) {
    let sToken;
    let dToken;
    if (token == null) {
      let asset = await router.assets(ETHAddress);
      sToken = await ethers.getContractAt("ISToken", asset.sToken);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.redeem(
        { asset: ETHAddress, amount: supplyAmount, to: deployer.address },
        true,
        true
      );
    } else {
      let asset = await router.assets(token.address);
      sToken = await ethers.getContractAt("ISToken", asset.sToken);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.redeem(
        { asset: token.address, amount: supplyAmount, to: deployer.address },
        true,
        true
      );
    }

    return { sToken: sToken, dToken: dToken };
  }

  async function borrow(deployer, router, token, borrowAmount) {
    let dToken;
    if (token == null) {
      let asset = await router.assets(ETHAddress);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.borrow(
        {
          asset: ETHAddress,
          amount: borrowAmount,
          to: deployer.address,
        },
        true
      );
    } else {
      let asset = await router.assets(token.address);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.borrow(
        {
          asset: token.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        true
      );
    }

    return dToken;
  }

  async function repay(deployer, router, token, borrowAmount) {
    let sToken;
    let dToken;
    if (token == null) {
      let asset = await router.assets(ETHAddress);
      sToken = await ethers.getContractAt("ISToken", asset.sToken);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.repay(
        { asset: ETHAddress, amount: borrowAmount, to: deployer.address },
        true,
        { value: borrowAmount }
      );
    } else {
      await token.mint(deployer.address, borrowAmount);
      await token.approve(router.address, borrowAmount);

      let asset = await router.assets(token.address);
      sToken = await ethers.getContractAt("ISToken", asset.sToken);
      dToken = await ethers.getContractAt("IDToken", asset.dToken);

      let tx = await router.repay(
        { asset: token.address, amount: borrowAmount, to: deployer.address },
        true
      );
    }

    return { sToken: sToken, dToken: dToken };
  }

  it("should set data properly", async () => {
    const deploys = await loadFixture(RewardsTestFixture);

    let protocolsHandler = await deploys.rewards.protocolsHandler();
    let aaveLogic = await deploys.rewards.protocols(0);
    let compoundLogic = await deploys.rewards.protocols(1);

    expect(protocolsHandler).to.equal(deploys.protocolsHandler.address);
    expect(aaveLogic).to.equal(deploys.aaveLogic.address);
    expect(compoundLogic).to.equal(deploys.compoundLogic.address);
  });

  describe("rewards tests on supply", function () {
    it("should start farm token0 via sToken", async () => {
      const {
        deployer,
        router,
        token0,
        cToken0,
        rewards,
        comp,
        protocolsHandler,
        compoundLogic,
      } = await loadFixture(RewardsTestFixture);
      let supplyAmount = ethers.utils.parseUnits("0.2", "ether");

      // before supply
      let uncollectedRewards0 = await rewards.uncollectedRewards(
        token0.address,
        0,
        deployer.address
      );
      let currentIndex0 = await rewards.currentIndexes(token0.address, 0);
      let userIndex0 = await rewards.userIndexes(
        token0.address,
        0,
        deployer.address
      );

      // 1st supply
      await supply(deployer, router, token0, supplyAmount);

      let uncollectedRewards1 = await rewards.uncollectedRewards(
        token0.address,
        0,
        deployer.address
      );
      let currentIndex1 = await rewards.currentIndexes(token0.address, 0);
      let userIndex1 = await rewards.userIndexes(
        token0.address,
        0,
        deployer.address
      );

      await expect(uncollectedRewards1.sub(uncollectedRewards0)).to.equal(0);
      await expect(currentIndex1.sub(currentIndex0)).to.equal(0);
      await expect(userIndex1.sub(userIndex0)).to.equal(0);

      // 2nd supply
      await supply(deployer, router, token0, supplyAmount);

      let uncollectedRewards2 = await rewards.uncollectedRewards(
        token0.address,
        0,
        deployer.address
      );
      let currentIndex2 = await rewards.currentIndexes(token0.address, 0);
      let userIndex2 = await rewards.userIndexes(
        token0.address,
        0,
        deployer.address
      );

      await expect(uncollectedRewards2.sub(uncollectedRewards1)).to.equal(0);
      await expect(currentIndex2.sub(currentIndex1)).to.equal(
        "4975245884631555"
      );
      await expect(userIndex2.sub(userIndex1)).to.equal("2487622920567342");

      // claim rewards
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards0 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards0).to.equal("1651911701978316");

      // claim rewards again
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards1 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards1).to.equal("2308774227030321");

      // 1st redeem
      await redeem(deployer, router, token0, supplyAmount);

      // claim rewards
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards2 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards2).to.equal("3297319816687884");

      // 2nd redeem
      await redeem(deployer, router, token0, supplyAmount.mul(2));
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards3 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards3).to.equal("3629002881293441");

      // claim rewards again with no token left
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards4 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards4).to.equal("3629002881293441");
    });

    it("should start farm token0 via dToken", async () => {
      const {
        deployer,
        router,
        usdt,
        token0,
        cToken0,
        rewards,
        comp,
        protocolsHandler,
        compoundLogic,
      } = await loadFixture(RewardsTestFixture);
      let borrowAmount = ethers.utils.parseUnits("0.2", "ether");
      // let borrowAmount = 1000;

      // before borrow
      await supply(deployer, router, usdt, borrowAmount);
      let uncollectedRewards0 = await rewards.uncollectedRewards(
        token0.address,
        1,
        deployer.address
      );
      let currentIndex0 = await rewards.currentIndexes(token0.address, 1);
      let userIndex0 = await rewards.userIndexes(
        token0.address,
        1,
        deployer.address
      );

      // 1st borrow
      await borrow(deployer, router, token0, borrowAmount);

      let uncollectedRewards1 = await rewards.uncollectedRewards(
        token0.address,
        1,
        deployer.address
      );
      let currentIndex1 = await rewards.currentIndexes(token0.address, 1);
      let userIndex1 = await rewards.userIndexes(
        token0.address,
        1,
        deployer.address
      );

      await expect(uncollectedRewards1.sub(uncollectedRewards0)).to.equal(0);
      await expect(currentIndex1.sub(currentIndex0)).to.equal(0);
      await expect(userIndex1.sub(userIndex0)).to.equal(0);

      // 2nd borrow
      await borrow(deployer, router, token0, borrowAmount);

      let uncollectedRewards2 = await rewards.uncollectedRewards(
        token0.address,
        1,
        deployer.address
      );
      let currentIndex2 = await rewards.currentIndexes(token0.address, 1);
      let userIndex2 = await rewards.userIndexes(
        token0.address,
        1,
        deployer.address
      );

      await expect(uncollectedRewards2.sub(uncollectedRewards1)).to.equal(0);
      await expect(currentIndex2.sub(currentIndex1)).to.equal(
        "3284311543043265"
      );
      await expect(userIndex2.sub(userIndex1)).to.equal("1642155761562779");

      // claim rewards
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards0 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards0).to.equal("1945322999831332");

      // claim rewards again
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards1 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards1).to.equal("3233783691054011");

      // 1st redeem
      await repay(deployer, router, token0, borrowAmount);

      // claim rewards
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards2 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards2).to.equal("7756028113150797");

      // 2nd redeem
      await repay(deployer, router, token0, borrowAmount.mul(2));
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards3 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards3).to.equal("9726615158437040");

      // claim rewards again with no token left
      await router.claimRewards(deployer.address, [token0.address]);
      let receivedRewards4 = await comp.balanceOf(deployer.address);
      await expect(receivedRewards4).to.equal("9726615158437040");
    });
  });
});
