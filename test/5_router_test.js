const { expect } = require("chai");
const { ethers, waffle, upgrades } = require("hardhat");
const aave = require("./aave/deploy");
const compound = require("./compound/deploy");
const transparentProxy = require("./utils/transparentProxy");
const m = require("mocha-logger");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Router tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  async function RouterTestFixture() {
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
      initializeParams: [protocolsHandler.address],
      proxyAdmin: proxyAdmin,
    });

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
      feeCollector: feeCollector,
      router: router,
      config: config,
      priceOracle: priceOracle,
      protocolsHandler: protocolsHandler,
      rewards: rewards,
      sTokenImplement: sToken,
      dTokenImplement: dToken,

      token0: token0,
      usdt: usdt,
      wETH: wETH,
      cToken0: cToken0,
      cUSDT: cUSDT,
      cETH: cETH,
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

  it("should set data properly", async () => {
    const deploys = await loadFixture(RouterTestFixture);
    let router = deploys.router;
    let config = deploys.config;
    let priceOracle = deploys.priceOracle;
    let protocolsHandler = deploys.protocolsHandler;
    let rewards = deploys.rewards;
    let sTokenImplement = deploys.sTokenImplement;
    let dTokenImplement = deploys.dTokenImplement;
    let token0 = deploys.token0;
    let usdt = deploys.usdt;
    let feeCollector = deploys.feeCollector;
    expect(await router.config()).to.equal(config.address);
    expect(await router.priceOracle()).to.equal(priceOracle.address);
    expect(await router.protocols()).to.equal(protocolsHandler.address);
    expect(await router.rewards()).to.equal(rewards.address);
    expect(await router.sTokenImplement()).to.equal(sTokenImplement.address);
    expect(await router.dTokenImplement()).to.equal(dTokenImplement.address);
    expect(await router.feeCollector()).to.equal(feeCollector.address);
    expect(await router.getUnderlyings()).to.have.ordered.members([
      token0.address,
      usdt.address,
      ETHAddress,
    ]);
  });

  describe("router supply tests", function () {
    it("should not supply", async () => {
      const deploys = await loadFixture(RouterTestFixture);

      await deploys.router.setBlockActions(deploys.token0.address, 2 ** 0);
      let tx = deploys.router.supply(
        {
          asset: deploys.token0.address,
          amount: ethers.utils.parseUnits("0.2", "ether"),
          to: deploys.deployer.address,
        },
        true,
        true
      );
      await expect(tx).to.be.revertedWith("SupplyLogic: action paused");
      await deploys.router.setBlockActions(deploys.token0.address, 0);

      await deploys.router.setBlockActions(
        ethers.constants.AddressZero,
        2 ** 0
      );
      tx = deploys.router.supply(
        {
          asset: deploys.token0.address,
          amount: ethers.utils.parseUnits("0.2", "ether"),
          to: deploys.deployer.address,
        },
        true,
        true
      );
      await expect(tx).to.be.revertedWith("SupplyLogic: action paused");
      await deploys.router.setBlockActions(ethers.constants.AddressZero, 0);
    });

    describe("router supply Token0 tests", function () {
      async function supplyToken0ViaSupplyTestFixture() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;
        let token0 = deploys.token0;

        let supplyAmount = ethers.utils.parseUnits("0.2", "ether");

        await token0.mint(deployer.address, supplyAmount);
        await token0.approve(router.address, supplyAmount);

        let assetToken0 = await router.assets(token0.address);
        let sToken0 = await ethers.getContractAt("ISToken", assetToken0.sToken);
        let dToken0 = await ethers.getContractAt("IDToken", assetToken0.dToken);

        return {
          deployer: deployer,
          router: router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          token0: token0,
          sToken0: sToken0,
          dToken0: dToken0,
          cToken0: deploys.cToken0,
          supplyAmount: supplyAmount,
        };
      }

      async function supplyToken0ViaRepayTestFixture() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;
        let token0 = deploys.token0;
        let usdt = deploys.usdt;

        let supplyAmount = ethers.utils.parseUnits("0.2", "ether");

        await supply(deployer, router, usdt, supplyAmount);
        await borrow(deployer, router, token0, supplyAmount);

        await token0.mint(deployer.address, supplyAmount);
        await token0.approve(router.address, supplyAmount);

        let assetToken0 = await router.assets(token0.address);
        let sToken0 = await ethers.getContractAt("ISToken", assetToken0.sToken);
        let dToken0 = await ethers.getContractAt("IDToken", assetToken0.dToken);

        return {
          deployer: deployer,
          router: router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          token0: token0,
          sToken0: sToken0,
          dToken0: dToken0,
          supplyAmount: supplyAmount,
        };
      }

      it("should supply token0 via protocols supply", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          token0,
          sToken0,
          dToken0,
          supplyAmount,
        } = await loadFixture(supplyToken0ViaSupplyTestFixture);

        let accFeeBefore = await dToken0.accFee();
        let feeIndexBefore = await dToken0.feeIndex();
        let sToken0BalanceBefore = await sToken0.balanceOf(deployer.address);
        let userBalanceBefore = await token0.balanceOf(deployer.address);
        let collateralStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );

        let tx = await router.supply(
          { asset: token0.address, amount: supplyAmount, to: deployer.address },
          true,
          true
        );

        let accFeeAfter = await dToken0.accFee();
        let feeIndexAfter = await dToken0.feeIndex();
        let userBalanceAfter = await token0.balanceOf(deployer.address);
        let sToken0BalanceAfter = await sToken0.balanceOf(deployer.address);
        let collateralStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let sToken0MintAmount = sToken0BalanceAfter.sub(sToken0BalanceBefore);
        let userTokenSupplied = userBalanceBefore.sub(userBalanceAfter);
        let routerBalance = await token0.balanceOf(router.address);
        let protocolsHandlerBalance = await token0.balanceOf(
          protocolsHandler.address
        );

        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(sToken0MintAmount).to.equal(supplyAmount);
        expect(userTokenSupplied).to.equal(supplyAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(collateralStatusBefore).to.equal(0);
        expect(collateralStatusAfter).to.equal(2);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);
        sBalance = await sToken0.balanceOf(deployer.address);
        balance = await sToken0.scaledBalanceOf(deployer.address);

        expect(sBalance).to.equal(supplyAmount);
        expect(balance).to.equal("200000596832090476");
      });

      it("should emit events when supply token0 via protocols supply", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          token0,
          sToken0,
          dToken0,
          supplyAmount,
        } = await loadFixture(supplyToken0ViaSupplyTestFixture);

        let tx = await router.supply(
          { asset: token0.address, amount: supplyAmount, to: deployer.address },
          true,
          true
        );

        let receipt = await tx.wait();
        m.log("supply gas used:", receipt.gasUsed);

        await expect(tx)
          .to.emit(token0, "Transfer")
          .withArgs(deployer.address, protocolsHandler.address, supplyAmount);
        await expect(tx).to.not.emit(dToken0, "AccFeeUpdated");
        await expect(tx)
          .to.emit(sToken0, "Transfer")
          .withArgs(
            ethers.constants.AddressZero,
            deployer.address,
            supplyAmount
          );
        await expect(tx)
          .to.emit(router, "Supplied")
          .withArgs(deployer.address, token0.address, supplyAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(token0.address, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 0, 2);
      });

      it("should supply token0 via protocols repay", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          token0,
          sToken0,
          dToken0,
          supplyAmount,
        } = await loadFixture(supplyToken0ViaRepayTestFixture);
        let accFeeBefore = await dToken0.accFee();
        let feeIndexBefore = await dToken0.feeIndex();
        let sToken0BalanceBefore = await sToken0.balanceOf(deployer.address);
        let userBalanceBefore = await token0.balanceOf(deployer.address);
        let collateralStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsBefore = await router.totalLendings(token0.address);

        let tx = await router.supply(
          { asset: token0.address, amount: supplyAmount, to: deployer.address },
          true,
          true
        );
        let accFeeAfter = await dToken0.accFee();
        let feeIndexAfter = await dToken0.feeIndex();
        let userBalanceAfter = await token0.balanceOf(deployer.address);
        let sToken0BalanceAfter = await sToken0.balanceOf(deployer.address);
        let collateralStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsAfter = await router.totalLendings(token0.address);

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let sToken0MintAmount = sToken0BalanceAfter.sub(sToken0BalanceBefore);
        let userTokenSupplied = userBalanceBefore.sub(userBalanceAfter);
        let routerBalance = await token0.balanceOf(router.address);
        let protocolsHandlerBalance = await token0.balanceOf(
          protocolsHandler.address
        );

        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(sToken0MintAmount).to.equal(supplyAmount);
        expect(userTokenSupplied).to.equal(supplyAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(collateralStatusBefore).to.equal(9);
        expect(collateralStatusAfter).to.equal(11);
        expect(totalLendingsBefore).to.equal(0);
        expect(totalLendingsAfter).to.equal(supplyAmount);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);
        sBalance = await sToken0.balanceOf(deployer.address);
        balance = await sToken0.scaledBalanceOf(deployer.address);

        expect(sBalance).to.equal(supplyAmount);
        expect(balance).to.equal("200000602740156908");
      });

      it("should emit events when supply token0 via protocols repay", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          token0,
          sToken0,
          dToken0,
          supplyAmount,
        } = await loadFixture(supplyToken0ViaRepayTestFixture);

        let tx = await router.supply(
          { asset: token0.address, amount: supplyAmount, to: deployer.address },
          true,
          true
        );

        let receipt = await tx.wait();
        m.log("supply gas used:", receipt.gasUsed);

        await expect(tx)
          .to.emit(token0, "Transfer")
          .withArgs(deployer.address, protocolsHandler.address, supplyAmount);

        await expect(tx).to.not.emit(dToken0, "AccFeeUpdated");
        await expect(tx)
          .to.emit(sToken0, "Transfer")
          .withArgs(
            ethers.constants.AddressZero,
            deployer.address,
            supplyAmount
          );
        await expect(tx)
          .to.emit(router, "Supplied")
          .withArgs(deployer.address, token0.address, supplyAmount);
        await expect(tx)
          .emit(router, "TotalLendingsUpdated")
          .withArgs(token0.address, supplyAmount);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 9, 11);
      });
    });

    describe("router supply ETH tests", function () {
      async function supplyETHViaSupplyTestFixture() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;

        let supplyAmount = ethers.utils.parseUnits("0.2", "ether");

        let assetETH = await router.assets(ETHAddress);
        let sETH = await ethers.getContractAt("ISToken", assetETH.sToken);
        let dETH = await ethers.getContractAt("IDToken", assetETH.dToken);

        return {
          deployer: deployer,
          feeCollector: deploys.feeCollector,
          router: router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          sETH: sETH,
          dETH: dETH,
          supplyAmount: supplyAmount,
        };
      }

      async function supplyETHViaRepayTestFixture() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;
        let usdt = deploys.usdt;

        let supplyAmount = ethers.utils.parseUnits("0.2", "ether");

        await supply(deployer, router, usdt, supplyAmount);
        await borrow(deployer, router, null, supplyAmount);

        let assetETH = await router.assets(ETHAddress);
        let sETH = await ethers.getContractAt("ISToken", assetETH.sToken);
        let dETH = await ethers.getContractAt("IDToken", assetETH.dToken);

        return {
          deployer: deployer,
          router: router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          sETH: sETH,
          dETH: dETH,
          supplyAmount: supplyAmount,
        };
      }

      it("should supply ETH via protocols supply", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          sETH,
          dETH,
          supplyAmount,
        } = await loadFixture(supplyETHViaSupplyTestFixture);

        let accFeeBefore = await dETH.accFee();
        let feeIndexBefore = await dETH.feeIndex();
        let sETHBalanceBefore = await sETH.balanceOf(deployer.address);
        let userBalanceBefore = await provider.getBalance(deployer.address);
        let collateralStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );

        let tx = await router.supply(
          { asset: ETHAddress, amount: supplyAmount, to: deployer.address },
          true,
          true,
          { value: supplyAmount }
        );

        const receipt = await tx.wait();
        const gasFee = receipt.effectiveGasPrice.mul(receipt.gasUsed);

        let accFeeAfter = await dETH.accFee();
        let feeIndexAfter = await dETH.feeIndex();
        let sETHBalanceAfter = await sETH.balanceOf(deployer.address);
        let userBalanceAfter = await provider.getBalance(deployer.address);
        let collateralStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let sETHMintAmount = sETHBalanceAfter.sub(sETHBalanceBefore);
        let userTokenSupplied = userBalanceBefore
          .sub(userBalanceAfter)
          .sub(gasFee);
        let routerBalance = await provider.getBalance(router.address);
        let protocolsHandlerBalance = await provider.getBalance(
          protocolsHandler.address
        );

        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(sETHMintAmount).to.equal(supplyAmount);
        expect(userTokenSupplied).to.equal(supplyAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(collateralStatusBefore).to.equal(0);
        expect(collateralStatusAfter).to.equal(32);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);
        sBalance = await sETH.balanceOf(deployer.address);
        balance = await sETH.scaledBalanceOf(deployer.address);

        expect(sBalance).to.equal(supplyAmount);
        expect(balance).to.equal("200000596831982937");
      });

      it("should emit events when supply ETH via protocols supply", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          sETH,
          dETH,
          supplyAmount,
        } = await loadFixture(supplyETHViaSupplyTestFixture);

        let tx = await router.supply(
          { asset: ETHAddress, amount: supplyAmount, to: deployer.address },
          true,
          true,
          { value: supplyAmount }
        );

        let receipt = await tx.wait();
        m.log("supply gas used:", receipt.gasUsed);

        await expect(tx).to.not.emit(dETH, "AccFeeUpdated");
        await expect(tx)
          .to.emit(sETH, "Transfer")
          .withArgs(
            ethers.constants.AddressZero,
            deployer.address,
            supplyAmount
          );
        await expect(tx)
          .to.emit(router, "Supplied")
          .withArgs(deployer.address, ETHAddress, supplyAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(ETHAddress, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 0, 32);
      });

      it("should supply ETH via protocols repay", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          sETH,
          dETH,
          supplyAmount,
        } = await loadFixture(supplyETHViaRepayTestFixture);

        let accFeeBefore = await dETH.accFee();
        let feeIndexBefore = await dETH.feeIndex();
        let sETHBalanceBefore = await sETH.balanceOf(deployer.address);
        let userBalanceBefore = await provider.getBalance(deployer.address);
        let collateralStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsBefore = await router.totalLendings(ETHAddress);
        let tx = await router.supply(
          { asset: ETHAddress, amount: supplyAmount, to: deployer.address },
          true,
          true,
          { value: supplyAmount }
        );
        const receipt = await ethers.provider.getTransactionReceipt(tx.hash);
        const gasFee = receipt.effectiveGasPrice.mul(receipt.gasUsed);

        let accFeeAfter = await dETH.accFee();
        let feeIndexAfter = await dETH.feeIndex();
        let sETHBalanceAfter = await sETH.balanceOf(deployer.address);
        let userBalanceAfter = await provider.getBalance(deployer.address);
        let collateralStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsAfter = await router.totalLendings(ETHAddress);

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let sETHMintAmount = sETHBalanceAfter.sub(sETHBalanceBefore);
        let userTokenSupplied = userBalanceBefore
          .sub(userBalanceAfter)
          .sub(gasFee);
        let routerBalance = await provider.getBalance(router.address);
        let protocolsHandlerBalance = await provider.getBalance(
          protocolsHandler.address
        );

        let totalLendingsDelta = totalLendingsAfter.sub(totalLendingsBefore);

        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(sETHMintAmount).to.equal(supplyAmount);
        expect(userTokenSupplied).to.equal(supplyAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(totalLendingsDelta).to.equal(supplyAmount);
        expect(collateralStatusBefore).to.equal(24);
        expect(collateralStatusAfter).to.equal(56);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);
        sBalance = await sETH.balanceOf(deployer.address);
        balance = await sETH.scaledBalanceOf(deployer.address);

        expect(sBalance).to.equal(supplyAmount);
        expect(balance).to.equal("200000602740048780");
      });

      it("should emit events when supply ETH via protocols repay", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          sETH,
          dETH,
          supplyAmount,
        } = await loadFixture(supplyETHViaRepayTestFixture);

        let tx = await router.supply(
          { asset: ETHAddress, amount: supplyAmount, to: deployer.address },
          true,
          true,
          { value: supplyAmount }
        );

        let receipt = await tx.wait();
        m.log("supply gas used:", receipt.gasUsed);

        await expect(tx).to.not.emit(dETH, "AccFeeUpdated");
        await expect(tx)
          .to.emit(sETH, "Transfer")
          .withArgs(
            ethers.constants.AddressZero,
            deployer.address,
            supplyAmount
          );
        await expect(tx)
          .to.emit(router, "Supplied")
          .withArgs(deployer.address, ETHAddress, supplyAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(ETHAddress, supplyAmount);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 24, 56);
      });
    });
  });

  describe("router redeem tests", function () {
    it("should not redeem", async () => {
      const deploys = await loadFixture(RouterTestFixture);

      let supplyAmount = ethers.utils.parseUnits("0.2", "ether");

      await supply(
        deploys.deployer,
        deploys.router,
        deploys.token0,
        supplyAmount
      );

      await deploys.router.setBlockActions(deploys.token0.address, 2 ** 1);
      let tx = deploys.router.redeem(
        {
          asset: deploys.token0.address,
          amount: supplyAmount,
          to: deploys.deployer.address,
        },
        true,
        true
      );
      await expect(tx).to.be.revertedWith("RedeemLogic: action paused");
      await deploys.router.setBlockActions(deploys.token0.address, 0);

      await deploys.router.setBlockActions(
        ethers.constants.AddressZero,
        2 ** 1
      );
      tx = deploys.router.redeem(
        {
          asset: deploys.token0.address,
          amount: supplyAmount,
          to: deploys.deployer.address,
        },
        true,
        true
      );
      await expect(tx).to.be.revertedWith("RedeemLogic: action paused");
      await deploys.router.setBlockActions(ethers.constants.AddressZero, 0);
    });

    describe("router redeem Token0 tests", function () {
      async function redeemToken0ViaProtocolsRedeem() {
        const deploys = await loadFixture(RouterTestFixture);

        let supplyAmount = ethers.utils.parseUnits("0.2", "ether");

        let { sToken, dToken } = await supply(
          deploys.deployer,
          deploys.router,
          deploys.token0,
          supplyAmount
        );

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);

        return {
          deployer: deploys.deployer,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          token0: deploys.token0,
          sToken0: sToken,
          dToken0: dToken,
          supplyAmount: supplyAmount,
        };
      }

      async function redeemToken0ViaProtocolsBorrow() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;
        let usdt = deploys.usdt;
        let token0 = deploys.token0;
        let cToken0 = deploys.cToken0;

        let supplyAmount = ethers.utils.parseUnits("0.2", "ether");
        await supply(deployer, router, usdt, supplyAmount);
        let { sToken, dToken } = await supply(
          deployer,
          router,
          token0,
          supplyAmount
        );
        await borrow(deployer, router, token0, supplyAmount.mul(2));

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);

        return {
          deployer: deployer,
          router: router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          token0: token0,
          sToken0: sToken,
          dToken0: dToken,
          supplyAmount: supplyAmount,
        };
      }

      it("should redeem token0 via protocols redeem", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          token0,
          sToken0,
          dToken0,
          supplyAmount,
        } = await loadFixture(redeemToken0ViaProtocolsRedeem);

        let accFeeBefore = await dToken0.accFee();
        let feeIndexBefore = await dToken0.feeIndex();
        let sToken0BalanceBefore = await sToken0.balanceOf(deployer.address);
        let userBalanceBefore = await token0.balanceOf(deployer.address);
        let collateralStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );

        let tx = await router.redeem(
          {
            asset: token0.address,
            amount: supplyAmount.mul(2),
            to: deployer.address,
          },
          false,
          true
        );

        let accFeeAfter = await dToken0.accFee();
        let feeIndexAfter = await dToken0.feeIndex();
        let userBalanceAfter = await token0.balanceOf(deployer.address);
        let sToken0BalanceAfter = await sToken0.balanceOf(deployer.address);
        let collateralStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let sToken0BurntAmount = sToken0BalanceBefore.sub(sToken0BalanceAfter);
        let userTokenRedeemed = userBalanceAfter.sub(userBalanceBefore);
        let routerBalance = await token0.balanceOf(router.address);
        let protocolsHandlerBalance = await token0.balanceOf(
          protocolsHandler.address
        );

        let expectRedeemedAmount = "200000597997778153";

        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(sToken0BurntAmount).to.equal(supplyAmount);
        expect(userTokenRedeemed).to.equal(expectRedeemedAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(collateralStatusBefore).to.equal(2);
        expect(collateralStatusAfter).to.equal(0);
      });

      it("should emit events when redeem token0 via protocols redeem", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          token0,
          sToken0,
          dToken0,
          supplyAmount,
        } = await loadFixture(redeemToken0ViaProtocolsRedeem);

        let tx = await router.redeem(
          {
            asset: token0.address,
            amount: supplyAmount.mul(2),
            to: deployer.address,
          },
          true,
          true
        );

        let receipt = await tx.wait();
        m.log("redeem gas used:", receipt.gasUsed);

        let expectRedeemedAmount = "200000597997778153";

        await expect(tx)
          .to.emit(token0, "Transfer")
          .withArgs(
            protocolsHandler.address,
            deployer.address,
            expectRedeemedAmount
          );
        await expect(tx).to.not.emit(dToken0, "AccFeeUpdated");
        await expect(tx)
          .to.emit(sToken0, "Transfer")
          .withArgs(
            deployer.address,
            ethers.constants.AddressZero,
            supplyAmount
          );
        await expect(tx)
          .to.emit(router, "Redeemed")
          .withArgs(deployer.address, token0.address, expectRedeemedAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(token0.address, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 2, 0);
      });

      it("should redeem token0 via protocols borrow", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          token0,
          sToken0,
          dToken0,
          supplyAmount,
        } = await loadFixture(redeemToken0ViaProtocolsBorrow);

        let accFeeBefore = await dToken0.accFee();
        let feeIndexBefore = await dToken0.feeIndex();
        let sToken0BalanceBefore = await sToken0.balanceOf(deployer.address);
        let userBalanceBefore = await token0.balanceOf(deployer.address);
        let collateralStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsBefore = await router.totalLendings(token0.address);
        let tx = await router.redeem(
          {
            asset: token0.address,
            amount: supplyAmount.mul(2),
            to: deployer.address,
          },
          false,
          true
        );

        let accFeeAfter = await dToken0.accFee();
        let feeIndexAfter = await dToken0.feeIndex();
        let userBalanceAfter = await token0.balanceOf(deployer.address);
        let sToken0BalanceAfter = await sToken0.balanceOf(deployer.address);
        let collateralStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsAfter = await router.totalLendings(token0.address);

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let sToken0BurntAmount = sToken0BalanceBefore.sub(sToken0BalanceAfter);
        let userTokenRedeemed = userBalanceAfter.sub(userBalanceBefore);
        let routerBalance = await token0.balanceOf(router.address);
        let protocolsHandlerBalance = await token0.balanceOf(
          protocolsHandler.address
        );

        let expectRedeemedAmount = "200000629481318831";

        expect(sToken0BurntAmount).to.equal(supplyAmount);
        expect(userTokenRedeemed).to.equal(expectRedeemedAmount);
        expect(accFee).to.equal("6346622536");
        expect(feeIndex).to.equal("15866556340");
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(collateralStatusBefore).to.equal(11);
        expect(collateralStatusAfter).to.equal(9);
        expect(totalLendingsBefore).to.equal("200000001165687718");
        expect(totalLendingsAfter).to.equal("6346622536");
      });

      it("should emit events when redeem token0 via protocols borrow", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          token0,
          sToken0,
          dToken0,
          supplyAmount,
        } = await loadFixture(redeemToken0ViaProtocolsBorrow);

        let tx = await router.redeem(
          {
            asset: token0.address,
            amount: supplyAmount.mul(2),
            to: deployer.address,
          },
          false,
          true
        );

        let receipt = await tx.wait();
        m.log("redeem gas used:", receipt.gasUsed);

        let expectRedeemedAmount = "200000629481318831";

        await expect(tx)
          .to.emit(token0, "Transfer")
          .withArgs(
            protocolsHandler.address,
            deployer.address,
            expectRedeemedAmount
          );
        await expect(tx)
          .to.emit(dToken0, "AccFeeUpdated")
          .withArgs("6346622536", "15866556340");
        await expect(tx)
          .to.emit(sToken0, "Transfer")
          .withArgs(
            deployer.address,
            ethers.constants.AddressZero,
            supplyAmount
          );
        await expect(tx)
          .to.emit(router, "Redeemed")
          .withArgs(deployer.address, token0.address, expectRedeemedAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(token0.address, "6346622536");
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 11, 9);
      });
    });

    describe("router redeem ETH tests", function () {
      async function redeemETHViaProtocolsRedeem() {
        const deploys = await loadFixture(RouterTestFixture);

        let supplyAmount = ethers.utils.parseUnits("0.2", "ether");

        let { sToken, dToken } = await supply(
          deploys.deployer,
          deploys.router,
          null,
          supplyAmount
        );

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);

        return {
          deployer: deploys.deployer,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          sETH: sToken,
          dETH: dToken,
          supplyAmount: supplyAmount,
        };
      }

      async function redeemETHViaProtocolsBorrow() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;
        let usdt = deploys.usdt;

        let supplyAmount = ethers.utils.parseUnits("0.2", "ether");
        await supply(deployer, router, usdt, supplyAmount);
        let { sToken, dToken } = await supply(
          deployer,
          router,
          null,
          supplyAmount
        );
        await borrow(deployer, router, null, supplyAmount.mul(2));

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);

        return {
          deployer: deploys.deployer,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          sETH: sToken,
          dETH: dToken,
          supplyAmount: supplyAmount,
        };
      }

      it("should redeem ETH via protocols redeem", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          sETH,
          dETH,
          supplyAmount,
        } = await loadFixture(redeemETHViaProtocolsRedeem);

        let accFeeBefore = await dETH.accFee();
        let feeIndexBefore = await dETH.feeIndex();
        let sETHBalanceBefore = await sETH.balanceOf(deployer.address);
        let userBalanceBefore = await provider.getBalance(deployer.address);
        let collateralStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );

        let tx = await router.redeem(
          {
            asset: ETHAddress,
            amount: supplyAmount.mul(2),
            to: deployer.address,
          },
          false,
          true
        );

        const receipt = await tx.wait();
        const gasFee = receipt.effectiveGasPrice.mul(receipt.gasUsed);

        let accFeeAfter = await dETH.accFee();
        let feeIndexAfter = await dETH.feeIndex();
        let userBalanceAfter = await provider.getBalance(deployer.address);
        let sETHBalanceAfter = await sETH.balanceOf(deployer.address);
        let collateralStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let sETHBurntAmount = sETHBalanceBefore.sub(sETHBalanceAfter);
        let userTokenRedeemed = userBalanceAfter
          .sub(userBalanceBefore)
          .add(gasFee);
        let routerBalance = await provider.getBalance(router.address);
        let protocolsHandlerBalance = await provider.getBalance(
          protocolsHandler.address
        );

        let expectRedeemedAmount = "200000597997670403";

        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(sETHBurntAmount).to.equal(supplyAmount);
        expect(userTokenRedeemed).to.equal(expectRedeemedAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(collateralStatusBefore).to.equal(32);
        expect(collateralStatusAfter).to.equal(0);
      });

      it("should emit events when redeem ETH via protocols redeem", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          sETH,
          dETH,
          supplyAmount,
        } = await loadFixture(redeemETHViaProtocolsRedeem);

        let tx = await router.redeem(
          {
            asset: ETHAddress,
            amount: supplyAmount.mul(2),
            to: deployer.address,
          },
          true,
          true
        );

        let receipt = await tx.wait();
        m.log("redeem gas used:", receipt.gasUsed);

        let expectRedeemedAmount = "200000597997670403";

        await expect(tx).to.not.emit(dETH, "AccFeeUpdated");
        await expect(tx)
          .to.emit(sETH, "Transfer")
          .withArgs(
            deployer.address,
            ethers.constants.AddressZero,
            supplyAmount
          );
        await expect(tx)
          .to.emit(router, "Redeemed")
          .withArgs(deployer.address, ETHAddress, expectRedeemedAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(ETHAddress, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 32, 0);
      });

      it("should redeem ETH via protocols borrow", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          sETH,
          dETH,
          supplyAmount,
        } = await loadFixture(redeemETHViaProtocolsBorrow);

        let accFeeBefore = await dETH.accFee();
        let feeIndexBefore = await dETH.feeIndex();
        let sETHBalanceBefore = await sETH.balanceOf(deployer.address);
        let userBalanceBefore = await provider.getBalance(deployer.address);
        let collateralStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsBefore = await router.totalLendings(ETHAddress);
        let tx = await router.redeem(
          {
            asset: ETHAddress,
            amount: supplyAmount.mul(2),
            to: deployer.address,
          },
          false,
          true
        );
        const receipt = await tx.wait();
        const gasFee = receipt.effectiveGasPrice.mul(receipt.gasUsed);

        let accFeeAfter = await dETH.accFee();
        let feeIndexAfter = await dETH.feeIndex();
        let userBalanceAfter = await provider.getBalance(deployer.address);
        let sETHBalanceAfter = await sETH.balanceOf(deployer.address);
        let collateralStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsAfter = await router.totalLendings(ETHAddress);
        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let sETHBurntAmount = sETHBalanceBefore.sub(sETHBalanceAfter);
        let userTokenRedeemed = userBalanceAfter
          .sub(userBalanceBefore)
          .add(gasFee);
        let routerBalance = await provider.getBalance(router.address);
        let protocolsHandlerBalance = await provider.getBalance(
          protocolsHandler.address
        );

        let expectRedeemedAmount = "200000629481210908";

        expect(sETHBurntAmount).to.equal(supplyAmount);
        expect(userTokenRedeemed).to.equal(expectRedeemedAmount);
        expect(accFee).to.equal("6346621448");
        expect(feeIndex).to.equal("15866553620");
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(totalLendingsBefore).to.equal("200000001165687508");
        expect(totalLendingsAfter).to.equal("6346621448");
        expect(collateralStatusBefore).to.equal(56);
        expect(collateralStatusAfter).to.equal(24);
      });

      it("should emit events when redeem ETH via protocols borrow", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          sETH,
          dETH,
          supplyAmount,
        } = await loadFixture(redeemETHViaProtocolsBorrow);

        let tx = await router.redeem(
          {
            asset: ETHAddress,
            amount: supplyAmount.mul(2),
            to: deployer.address,
          },
          false,
          true
        );

        let receipt = await tx.wait();
        m.log("redeem gas used:", receipt.gasUsed);

        let expectRedeemedAmount = "200000629481210908";

        await expect(tx)
          .to.emit(dETH, "AccFeeUpdated")
          .withArgs("6346621448", "15866553620");
        await expect(tx)
          .to.emit(sETH, "Transfer")
          .withArgs(
            deployer.address,
            ethers.constants.AddressZero,
            supplyAmount
          );
        await expect(tx)
          .to.emit(router, "Redeemed")
          .withArgs(deployer.address, ETHAddress, expectRedeemedAmount);
        await expect(tx)
          .emit(router, "TotalLendingsUpdated")
          .withArgs(ETHAddress, "6346621448");
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 56, 24);
      });
    });
  });

  describe("router borrow tests", function () {
    it("should not borrow", async () => {
      const deploys = await loadFixture(RouterTestFixture);

      let supplyAmount = ethers.utils.parseUnits("0.2", "ether");
      let borrowAmount = ethers.utils.parseUnits("0.1", "ether");

      await supply(
        deploys.deployer,
        deploys.router,
        deploys.token0,
        supplyAmount
      );

      await deploys.router.setBlockActions(deploys.token0.address, 2 ** 2);
      let tx = deploys.router.borrow(
        {
          asset: deploys.token0.address,
          amount: borrowAmount,
          to: deploys.deployer.address,
        },
        true
      );
      await expect(tx).to.be.revertedWith("BorrowLogic: action paused");
      await deploys.router.setBlockActions(deploys.token0.address, 0);

      await deploys.router.setBlockActions(
        ethers.constants.AddressZero,
        2 ** 2
      );
      tx = deploys.router.borrow(
        {
          asset: deploys.token0.address,
          amount: borrowAmount,
          to: deploys.deployer.address,
        },
        true
      );
      await expect(tx).to.be.revertedWith("BorrowLogic: action paused");
      await deploys.router.setBlockActions(ethers.constants.AddressZero, 0);
    });

    describe("router borrow Token0 tests", function () {
      async function borrowToken0ViaProtocolsBorrow() {
        const deploys = await loadFixture(RouterTestFixture);

        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");
        await supply(
          deploys.deployer,
          deploys.router,
          deploys.usdt,
          borrowAmount
        );

        let asset = await deploys.router.assets(deploys.token0.address);
        let dToken0 = await ethers.getContractAt("IDToken", asset.dToken);

        return {
          deployer: deploys.deployer,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          token0: deploys.token0,
          dToken0: dToken0,
          borrowAmount: borrowAmount,
        };
      }

      async function borrowToken0ViaProtocolsRedeem() {
        const deploys = await loadFixture(RouterTestFixture);

        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");
        await supply(
          deploys.deployer,
          deploys.router,
          deploys.token0,
          borrowAmount.mul(2)
        );

        let asset = await deploys.router.assets(deploys.token0.address);
        let dToken0 = await ethers.getContractAt("IDToken", asset.dToken);

        return {
          deployer: deploys.deployer,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          token0: deploys.token0,
          dToken0: dToken0,
          borrowAmount: borrowAmount,
        };
      }

      it("should not borrow token0", async () => {
        const deploys = await loadFixture(RouterTestFixture);
        let deployer = deploys.deployer;
        let feeCollected = deploys.feeCollector;
        let router = deploys.router;
        let token0 = deploys.token0;

        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");

        await supply(feeCollected, router, token0, borrowAmount.mul(10));

        let tx = router.borrow(
          {
            asset: token0.address,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );

        await expect(tx).to.be.revertedWith(
          "BorrowLogic: Insufficient collateral"
        );
      });

      it("should borrow token0 via protocols borrow", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          token0,
          dToken0,
          borrowAmount,
        } = await loadFixture(borrowToken0ViaProtocolsBorrow);

        let accFeeBefore = await dToken0.accFee();
        let feeIndexBefore = await dToken0.feeIndex();
        let userFeeIndexBefore = await dToken0.feeIndexOf(deployer.address);
        let dToken0BalanceBefore = await dToken0.balanceOf(deployer.address);
        let userBalanceBefore = await token0.balanceOf(deployer.address);
        let userDebtStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let tx = await router.borrow(
          {
            asset: token0.address,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );
        let accFeeAfter = await dToken0.accFee();
        let feeIndexAfter = await dToken0.feeIndex();
        let userFeeIndexAfter = await dToken0.feeIndexOf(deployer.address);
        let userBalanceAfter = await token0.balanceOf(deployer.address);
        let dToken0BalanceAfter = await dToken0.balanceOf(deployer.address);
        let userDebtStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let userFeeIndex = userFeeIndexAfter.sub(userFeeIndexBefore);
        let dToken0MintAmount = dToken0BalanceAfter.sub(dToken0BalanceBefore);
        let userTokenBorrowed = userBalanceAfter.sub(userBalanceBefore);
        let routerBalance = await token0.balanceOf(router.address);
        let protocolsHandlerBalance = await token0.balanceOf(
          protocolsHandler.address
        );

        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(userFeeIndex).to.equal(0);
        expect(dToken0MintAmount).to.equal(borrowAmount);
        expect(userTokenBorrowed).to.equal(borrowAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(userDebtStatusBefore).to.equal(8);
        expect(userDebtStatusAfter).to.equal(9);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);
        dBalance = await dToken0.balanceOf(deployer.address);
        balance = await dToken0.scaledDebtOf(deployer.address);

        expect(dBalance).to.equal(borrowAmount);
        expect(balance).to.equal("100000614916490393");
      });

      it("should emit events when borrow token0 via protocols borrow", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          token0,
          dToken0,
          borrowAmount,
        } = await loadFixture(borrowToken0ViaProtocolsBorrow);

        let tx = await router.borrow(
          {
            asset: token0.address,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );

        let receipt = await tx.wait();
        m.log("borrow gas used:", receipt.gasUsed);

        await expect(tx)
          .to.emit(token0, "Transfer")
          .withArgs(protocolsHandler.address, deployer.address, borrowAmount);

        await expect(tx).to.not.emit(dToken0, "AccFeeUpdated");
        await expect(tx)
          .to.emit(dToken0, "UserFeeIndexUpdated")
          .withArgs(deployer.address, 0);
        await expect(tx)
          .to.emit(dToken0, "Transfer")
          .withArgs(
            ethers.constants.AddressZero,
            deployer.address,
            borrowAmount
          );
        await expect(tx)
          .to.emit(router, "Borrowed")
          .withArgs(deployer.address, token0.address, borrowAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(token0.address, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 8, 9);
      });

      it("should borrow token0 via protocols redeem", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          token0,
          dToken0,
          borrowAmount,
        } = await loadFixture(borrowToken0ViaProtocolsRedeem);

        let accFeeBefore = await dToken0.accFee();
        let feeIndexBefore = await dToken0.feeIndex();
        let userFeeIndexBefore = await dToken0.feeIndexOf(deployer.address);
        let dToken0BalanceBefore = await dToken0.balanceOf(deployer.address);
        let userBalanceBefore = await token0.balanceOf(deployer.address);
        let userDebtStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingBefore = await router.totalLendings(token0.address);

        let tx = await router.borrow(
          {
            asset: token0.address,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );
        let accFeeAfter = await dToken0.accFee();
        let feeIndexAfter = await dToken0.feeIndex();
        let userFeeIndexAfter = await dToken0.feeIndexOf(deployer.address);
        let userBalanceAfter = await token0.balanceOf(deployer.address);
        let dToken0BalanceAfter = await dToken0.balanceOf(deployer.address);
        let userDebtStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingAfter = await router.totalLendings(token0.address);

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let userFeeIndex = userFeeIndexAfter.sub(userFeeIndexBefore);
        let dToken0MintAmount = dToken0BalanceAfter.sub(dToken0BalanceBefore);
        let userTokenBorrowed = userBalanceAfter.sub(userBalanceBefore);
        let routerBalance = await token0.balanceOf(router.address);
        let protocolsHandlerBalance = await token0.balanceOf(
          protocolsHandler.address
        );
        let totalLending = totalLendingAfter.sub(totalLendingBefore);

        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(userFeeIndex).to.equal(0);
        expect(dToken0MintAmount).to.equal(borrowAmount);
        expect(userTokenBorrowed).to.equal(borrowAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(userDebtStatusBefore).to.equal(2);
        expect(userDebtStatusAfter).to.equal(3);
        expect(totalLending).to.equal(borrowAmount);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);
        dBalance = await dToken0.balanceOf(deployer.address);
        balance = await dToken0.scaledDebtOf(deployer.address);

        expect(dBalance).to.equal(borrowAmount);
        expect(balance).to.equal("100000301392748031");
      });

      it("should emit events when borrow token0 via protocols redeem", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          token0,
          dToken0,
          cToken0,
          borrowAmount,
        } = await loadFixture(borrowToken0ViaProtocolsRedeem);

        let tx = await router.borrow(
          {
            asset: token0.address,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );

        let receipt = await tx.wait();
        m.log("borrow gas used:", receipt.gasUsed);

        await expect(tx)
          .to.emit(token0, "Transfer")
          .withArgs(protocolsHandler.address, deployer.address, borrowAmount);

        await expect(tx).to.not.emit(dToken0, "AccFeeUpdated");
        await expect(tx)
          .to.emit(dToken0, "UserFeeIndexUpdated")
          .withArgs(deployer.address, 0);
        await expect(tx)
          .to.emit(dToken0, "Transfer")
          .withArgs(
            ethers.constants.AddressZero,
            deployer.address,
            borrowAmount
          );
        await expect(tx)
          .to.emit(router, "Borrowed")
          .withArgs(deployer.address, token0.address, borrowAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(token0.address, borrowAmount);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 2, 3);
      });
    });

    describe("router borrow ETH tests", function () {
      async function borrowETHViaProtocolsBorrow() {
        const deploys = await loadFixture(RouterTestFixture);
        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");
        await supply(
          deploys.deployer,
          deploys.router,
          deploys.usdt,
          borrowAmount
        );
        let asset = await deploys.router.assets(ETHAddress);
        let dETH = await ethers.getContractAt("IDToken", asset.dToken);
        return {
          deployer: deploys.deployer,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          dETH: dETH,
          borrowAmount: borrowAmount,
        };
      }

      async function borrowETHViaProtocolsRedeem() {
        const deploys = await loadFixture(RouterTestFixture);
        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");
        await supply(
          deploys.deployer,
          deploys.router,
          null,
          borrowAmount.mul(2)
        );
        let asset = await deploys.router.assets(ETHAddress);
        let dETH = await ethers.getContractAt("IDToken", asset.dToken);
        return {
          deployer: deploys.deployer,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          dETH: dETH,
          cETH: deploys.cETH,
          borrowAmount: borrowAmount,
        };
      }

      it("should not borrow ETH", async () => {
        const deploys = await loadFixture(RouterTestFixture);
        let deployer = deploys.deployer;
        let feeCollector = deploys.feeCollector;
        let router = deploys.router;

        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");

        await supply(feeCollector, router, null, borrowAmount.mul(10));

        let tx = router.borrow(
          {
            asset: ETHAddress,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );
        await expect(tx).to.be.revertedWith(
          "BorrowLogic: Insufficient collateral"
        );
      });

      it("should borrow ETH via protocols borrow", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          dETH,
          borrowAmount,
        } = await loadFixture(borrowETHViaProtocolsBorrow);

        let accFeeBefore = await dETH.accFee();
        let feeIndexBefore = await dETH.feeIndex();
        let userFeeIndexBefore = await dETH.feeIndexOf(deployer.address);
        let userBalanceBefore = await provider.getBalance(deployer.address);
        let dETHBalanceBefore = await dETH.balanceOf(deployer.address);
        let userDebtStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let tx = await router.borrow(
          {
            asset: ETHAddress,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );
        const receipt = await tx.wait();
        const gasFee = receipt.effectiveGasPrice.mul(receipt.gasUsed);

        let accFeeAfter = await dETH.accFee();
        let feeIndexAfter = await dETH.feeIndex();
        let userFeeIndexAfter = await dETH.feeIndexOf(deployer.address);
        let userBalanceAfter = await provider.getBalance(deployer.address);
        let dETHBalanceAfter = await dETH.balanceOf(deployer.address);
        let userDebtStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let userFeeIndex = userFeeIndexAfter.sub(userFeeIndexBefore);
        let dToken0MintAmount = dETHBalanceAfter.sub(dETHBalanceBefore);
        let userTokenBorrowed = userBalanceAfter
          .sub(userBalanceBefore)
          .add(gasFee);
        let routerBalance = await provider.getBalance(router.address);
        let protocolsHandlerBalance = await provider.getBalance(
          protocolsHandler.address
        );
        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(userFeeIndex).to.equal(0);
        expect(dToken0MintAmount).to.equal(borrowAmount);
        expect(userTokenBorrowed).to.equal(borrowAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(userDebtStatusBefore).to.equal(8);
        expect(userDebtStatusAfter).to.equal(24);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);
        dBalance = await dETH.balanceOf(deployer.address);
        balance = await dETH.scaledDebtOf(deployer.address);

        expect(dBalance).to.equal(borrowAmount);
        expect(balance).to.equal("100000614916443801");
      });

      it("should emit events when borrow ETH via protocols borrow", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          dETH,
          cETH,
          borrowAmount,
        } = await loadFixture(borrowETHViaProtocolsBorrow);
        let tx = await router.borrow(
          {
            asset: ETHAddress,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );

        let receipt = await tx.wait();
        m.log("borrow gas used:", receipt.gasUsed);

        await expect(tx).to.not.emit(dETH, "AccFeeUpdated");
        await expect(tx)
          .to.emit(dETH, "UserFeeIndexUpdated")
          .withArgs(deployer.address, 0);
        await expect(tx)
          .to.emit(dETH, "Transfer")
          .withArgs(
            ethers.constants.AddressZero,
            deployer.address,
            borrowAmount
          );
        await expect(tx)
          .to.emit(router, "Borrowed")
          .withArgs(deployer.address, ETHAddress, borrowAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(ETHAddress, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 8, 24);
      });

      it("should borrow ETH via protocols redeem", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          dETH,
          cETH,
          borrowAmount,
        } = await loadFixture(borrowETHViaProtocolsRedeem);

        let accFeeBefore = await dETH.accFee();
        let feeIndexBefore = await dETH.feeIndex();
        let userFeeIndexBefore = await dETH.feeIndexOf(deployer.address);
        let userBalanceBefore = await provider.getBalance(deployer.address);
        let dETHBalanceBefore = await dETH.balanceOf(deployer.address);
        let userDebtStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingBefore = await router.totalLendings(ETHAddress);

        let tx = await router.borrow(
          {
            asset: ETHAddress,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );
        const receipt = await tx.wait();
        const gasFee = receipt.effectiveGasPrice.mul(receipt.gasUsed);

        let accFeeAfter = await dETH.accFee();
        let feeIndexAfter = await dETH.feeIndex();
        let userFeeIndexAfter = await dETH.feeIndexOf(deployer.address);
        let userBalanceAfter = await provider.getBalance(deployer.address);
        let dETHBalanceAfter = await dETH.balanceOf(deployer.address);
        let userDebtStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingAfter = await router.totalLendings(ETHAddress);

        let accFee = accFeeAfter.sub(accFeeBefore);
        let feeIndex = feeIndexAfter.sub(feeIndexBefore);
        let userFeeIndex = userFeeIndexAfter.sub(userFeeIndexBefore);
        let dToken0MintAmount = dETHBalanceAfter.sub(dETHBalanceBefore);
        let userTokenBorrowed = userBalanceAfter
          .sub(userBalanceBefore)
          .add(gasFee);
        let routerBalance = await provider.getBalance(router.address);
        let protocolsHandlerBalance = await provider.getBalance(
          protocolsHandler.address
        );
        let totalLending = totalLendingAfter.sub(totalLendingBefore);

        expect(accFee).to.equal(0);
        expect(feeIndex).to.equal(0);
        expect(userFeeIndex).to.equal(0);
        expect(dToken0MintAmount).to.equal(borrowAmount);
        expect(userTokenBorrowed).to.equal(borrowAmount);
        expect(totalLending).to.equal("100000000000000000");
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(userDebtStatusBefore).to.equal(32);
        expect(userDebtStatusAfter).to.equal(48);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);
        dBalance = await dETH.balanceOf(deployer.address);
        balance = await dETH.scaledDebtOf(deployer.address);

        expect(dBalance).to.equal(borrowAmount);
        expect(balance).to.equal("100000301392694017");
      });

      it("should emit events when borrow ETH via protocols redeem", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          dETH,
          cETH,
          borrowAmount,
        } = await loadFixture(borrowETHViaProtocolsRedeem);

        let tx = await router.borrow(
          {
            asset: ETHAddress,
            amount: borrowAmount,
            to: deployer.address,
          },
          true
        );

        let receipt = await tx.wait();
        m.log("borrow gas used:", receipt.gasUsed);

        await expect(tx).to.not.emit(dETH, "AccFeeUpdated");
        await expect(tx)
          .to.emit(dETH, "UserFeeIndexUpdated")
          .withArgs(deployer.address, 0);
        await expect(tx)
          .to.emit(dETH, "Transfer")
          .withArgs(
            ethers.constants.AddressZero,
            deployer.address,
            borrowAmount
          );
        await expect(tx)
          .to.emit(router, "Borrowed")
          .withArgs(deployer.address, ETHAddress, borrowAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(ETHAddress, borrowAmount);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 32, 48);
      });
    });
  });

  describe("router repay tests", function () {
    it("should not repay", async () => {
      const deploys = await loadFixture(RouterTestFixture);

      let supplyAmount = ethers.utils.parseUnits("0.2", "ether");
      let borrowAmount = ethers.utils.parseUnits("0.1", "ether");

      await supply(
        deploys.deployer,
        deploys.router,
        deploys.token0,
        supplyAmount
      );

      await borrow(
        deploys.deployer,
        deploys.router,
        deploys.token0,
        borrowAmount
      );

      await deploys.router.setBlockActions(deploys.token0.address, 2 ** 3);

      let tx = deploys.router.repay(
        {
          asset: deploys.token0.address,
          amount: borrowAmount.mul(2),
          to: deploys.deployer.address,
        },
        true
      );
      await expect(tx).to.be.revertedWith("RepayLogic: action paused");
      await deploys.router.setBlockActions(deploys.token0.address, 0);

      await deploys.router.setBlockActions(
        ethers.constants.AddressZero,
        2 ** 3
      );
      tx = deploys.router.repay(
        {
          asset: deploys.token0.address,
          amount: borrowAmount.mul(2),
          to: deploys.deployer.address,
        },
        true
      );
      await expect(tx).to.be.revertedWith("RepayLogic: action paused");
      await deploys.router.setBlockActions(ethers.constants.AddressZero, 0);
    });

    describe("router repay Token0 tests", function () {
      async function repayToken0ViaProtocolsRepay() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;
        let token0 = deploys.token0;
        let usdt = deploys.usdt;

        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");
        await supply(deployer, router, usdt, borrowAmount);
        let dToken0 = await borrow(deployer, router, token0, borrowAmount);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);

        await token0.mint(deployer.address, borrowAmount);
        await token0.approve(router.address, borrowAmount.mul(2));

        return {
          deployer: deploys.deployer,
          feeCollector: deploys.feeCollector,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          token0: deploys.token0,
          dToken0: dToken0,
          borrowAmount: borrowAmount,
        };
      }

      async function repayToken0ViaProtocolsSupply() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;
        let token0 = deploys.token0;
        let usdt = deploys.usdt;

        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");

        await supply(deployer, router, token0, borrowAmount.mul(2));
        let dToken0 = await borrow(deployer, router, token0, borrowAmount);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);

        await token0.mint(deployer.address, borrowAmount);
        await token0.approve(router.address, borrowAmount.mul(2));

        return {
          deployer: deploys.deployer,
          feeCollector: deploys.feeCollector,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          token0: deploys.token0,
          dToken0: dToken0,
          borrowAmount: borrowAmount,
        };
      }

      it("should repay token0 via protocols repay", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          token0,
          dToken0,
          borrowAmount,
        } = await loadFixture(repayToken0ViaProtocolsRepay);

        let accFeeBefore = await dToken0.accFee();
        let collectedFeeBefore = await dToken0.collectedFee();
        let dToken0BalanceBefore = await dToken0.balanceOf(deployer.address);
        let userBalanceBefore = await token0.balanceOf(deployer.address);
        let userDebtStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let tx = await router.repay(
          {
            asset: token0.address,
            amount: borrowAmount.mul(2),
            to: deployer.address,
          },
          true
        );

        let accFeeAfter = await dToken0.accFee();
        let collectedFeeAfter = await dToken0.collectedFee();
        let dToken0BalanceAfter = await dToken0.balanceOf(deployer.address);
        let userBalanceAfter = await token0.balanceOf(deployer.address);
        let userDebtStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );

        let accFee = accFeeAfter.sub(accFeeBefore);
        let collectedFee = collectedFeeAfter.sub(collectedFeeBefore);
        let dToken0BurntAmount = dToken0BalanceBefore.sub(dToken0BalanceAfter);
        let userTokenRepaid = userBalanceBefore.sub(userBalanceAfter);
        let routerBalance = await token0.balanceOf(router.address);
        let protocolsHandlerBalance = await token0.balanceOf(
          protocolsHandler.address
        );

        let expectRepayAmount = ethers.BigNumber.from("100000618519516704");

        expect(accFee).to.equal(0);
        expect(collectedFee).to.equal(0);
        expect(dToken0BurntAmount).to.equal(borrowAmount);
        expect(userTokenRepaid).to.equal(expectRepayAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(userDebtStatusBefore).to.equal(9);
        expect(userDebtStatusAfter).to.equal(8);
      });

      it("should emit events when repay token0 via protocols repay", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          token0,
          dToken0,
          borrowAmount,
        } = await loadFixture(repayToken0ViaProtocolsRepay);

        let tx = await router.repay(
          {
            asset: token0.address,
            amount: borrowAmount.mul(2),
            to: deployer.address,
          },
          true
        );

        let receipt = await tx.wait();
        m.log("repay gas used:", receipt.gasUsed);

        let expectRepayAmount = ethers.BigNumber.from("100000618519516704");
        let collectedFeeExpected = 0;

        await expect(tx)
          .to.emit(token0, "Transfer")
          .withArgs(
            deployer.address,
            protocolsHandler.address,
            expectRepayAmount.sub(collectedFeeExpected)
          );

        await expect(tx).to.not.emit(dToken0, "AccFeeUpdated");
        await expect(tx).to.emit(dToken0, "CollectedFeeUpdated").withArgs(0);
        await expect(tx)
          .to.emit(dToken0, "Transfer")
          .withArgs(
            deployer.address,
            ethers.constants.AddressZero,
            borrowAmount
          );
        await expect(tx)
          .to.emit(router, "Repaid")
          .withArgs(deployer.address, token0.address, expectRepayAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(token0.address, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 9, 8);
      });

      it("should repay token0 via protocols supply", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          token0,
          dToken0,
          borrowAmount,
        } = await loadFixture(repayToken0ViaProtocolsSupply);

        let accFeeBefore = await dToken0.accFee();
        let collectedFeeBefore = await dToken0.collectedFee();
        let dToken0BalanceBefore = await dToken0.balanceOf(deployer.address);
        let userBalanceBefore = await token0.balanceOf(deployer.address);
        let userDebtStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsBefore = await router.totalLendings(token0.address);

        let tx = await router.repay(
          {
            asset: token0.address,
            amount: borrowAmount.mul(2),
            to: deployer.address,
          },
          true
        );

        let accFeeAfter = await dToken0.accFee();
        let collectedFeeAfter = await dToken0.collectedFee();
        let dToken0BalanceAfter = await dToken0.balanceOf(deployer.address);
        let userBalanceAfter = await token0.balanceOf(deployer.address);
        let userDebtStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsAfter = await router.totalLendings(token0.address);

        let accFee = accFeeAfter.sub(accFeeBefore);
        let collectedFee = collectedFeeAfter.sub(collectedFeeBefore);
        let dToken0BurntAmount = dToken0BalanceBefore.sub(dToken0BalanceAfter);
        let userTokenRepaid = userBalanceBefore.sub(userBalanceAfter);
        let routerBalance = await token0.balanceOf(router.address);
        let protocolsHandlerBalance = await token0.balanceOf(
          protocolsHandler.address
        );

        let expectRepayAmount = ethers.BigNumber.from("100000303158721164");
        let accFeeDeltaExpect = expectRepayAmount
          .sub(borrowAmount)
          .mul(await dToken0.feeRate())
          .div(ethers.BigNumber.from("1000000"));

        expect(dToken0BurntAmount).to.equal(borrowAmount);
        expect(userTokenRepaid).to.equal(expectRepayAmount);
        expect(accFee).to.equal(accFeeDeltaExpect);
        expect(collectedFee).to.equal(accFeeDeltaExpect);

        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(userDebtStatusBefore).to.equal(3);
        expect(userDebtStatusAfter).to.equal(2);
        expect(totalLendingsBefore).to.equal("100000000000000000");
        expect(totalLendingsAfter).to.equal("0");
      });

      it("should emit events when repay token0 via protocols supply", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          token0,
          dToken0,
          borrowAmount,
        } = await loadFixture(repayToken0ViaProtocolsSupply);

        let tx = await router.repay(
          {
            asset: token0.address,
            amount: borrowAmount.mul(2),
            to: deployer.address,
          },
          true
        );
        let receipt = await tx.wait();
        m.log("repay gas used:", receipt.gasUsed);

        let expectRepayAmount = ethers.BigNumber.from("100000303158721164");
        let collectedFeeExpected = expectRepayAmount
          .sub(borrowAmount)
          .mul(await dToken0.feeRate())
          .div(ethers.BigNumber.from("1000000"));

        await expect(tx)
          .to.emit(token0, "Transfer")
          .withArgs(
            deployer.address,
            protocolsHandler.address,
            expectRepayAmount.sub(collectedFeeExpected)
          );

        await expect(tx)
          .to.emit(token0, "Transfer")
          .withArgs(
            deployer.address,
            feeCollector.address,
            collectedFeeExpected
          );

        await expect(tx)
          .to.emit(dToken0, "AccFeeUpdated")
          .withArgs(collectedFeeExpected, collectedFeeExpected.mul(10));
        await expect(tx)
          .to.emit(dToken0, "CollectedFeeUpdated")
          .withArgs(collectedFeeExpected);
        await expect(tx)
          .to.emit(dToken0, "Transfer")
          .withArgs(
            deployer.address,
            ethers.constants.AddressZero,
            borrowAmount
          );
        await expect(tx)
          .to.emit(router, "Repaid")
          .withArgs(deployer.address, token0.address, expectRepayAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(token0.address, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 3, 2);
      });
    });

    describe("router repay ETH tests", function () {
      async function repayETHViaProtocolsRepay() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;
        let usdt = deploys.usdt;

        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");
        await supply(deployer, router, usdt, borrowAmount);
        let dETH = await borrow(deployer, router, null, borrowAmount);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);

        return {
          deployer: deploys.deployer,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          dETH: dETH,
          borrowAmount: borrowAmount,
        };
      }

      async function repayETHViaProtocolsSupply() {
        const deploys = await loadFixture(RouterTestFixture);

        let deployer = deploys.deployer;
        let router = deploys.router;
        let usdt = deploys.usdt;

        let borrowAmount = ethers.utils.parseUnits("0.1", "ether");

        await supply(deployer, router, null, borrowAmount.mul(2));
        let dETH = await borrow(deployer, router, null, borrowAmount);

        // forwoad 512 blocks
        await hre.network.provider.send("hardhat_mine", ["0x200"]);

        return {
          deployer: deploys.deployer,
          feeCollector: deploys.feeCollector,
          router: deploys.router,
          config: deploys.config,
          protocolsHandler: deploys.protocolsHandler,
          dETH: dETH,
          borrowAmount: borrowAmount,
        };
      }

      it("should repay ETH via protocols repay", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          dETH,
          cETH,
          borrowAmount,
        } = await loadFixture(repayETHViaProtocolsRepay);

        let accFeeBefore = await dETH.accFee();
        let collectedFeeBefore = await dETH.collectedFee();
        let dETHBalanceBefore = await dETH.balanceOf(deployer.address);
        let userBalanceBefore = await provider.getBalance(deployer.address);
        let userDebtStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let tx = await router.repay(
          {
            asset: ETHAddress,
            amount: borrowAmount.mul(2),
            to: deployer.address,
          },
          true,
          { value: borrowAmount.mul(2) }
        );

        const receipt = await tx.wait();
        const gasFee = receipt.effectiveGasPrice.mul(receipt.gasUsed);

        let accFeeAfter = await dETH.accFee();
        let collectedFeeAfter = await dETH.collectedFee();
        let dETHBalanceAfter = await dETH.balanceOf(deployer.address);
        let userBalanceAfter = await provider.getBalance(deployer.address);
        let userDebtStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );

        let accFee = accFeeAfter.sub(accFeeBefore);
        let collectedFee = collectedFeeAfter.sub(collectedFeeBefore);
        let dETHBurntAmount = dETHBalanceBefore.sub(dETHBalanceAfter);
        let userTokenRepaid = userBalanceBefore
          .sub(userBalanceAfter)
          .sub(gasFee);
        let routerBalance = await provider.getBalance(router.address);
        let protocolsHandlerBalance = await provider.getBalance(
          protocolsHandler.address
        );

        let expectRepayAmount = ethers.BigNumber.from("100000616117452480");

        expect(accFee).to.equal(0);
        expect(collectedFee).to.equal(0);
        expect(dETHBurntAmount).to.equal(borrowAmount);
        expect(userTokenRepaid).to.equal(expectRepayAmount);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(userDebtStatusBefore).to.equal(24);
        expect(userDebtStatusAfter).to.equal(8);
      });

      it("should emit events when repay ETH via protocols repay", async () => {
        const {
          deployer,
          router,
          config,
          protocolsHandler,
          dETH,
          cETH,
          borrowAmount,
        } = await loadFixture(repayETHViaProtocolsRepay);

        let tx = await router.repay(
          {
            asset: ETHAddress,
            amount: borrowAmount.mul(2),
            to: deployer.address,
          },
          true,
          { value: borrowAmount.mul(2) }
        );

        let receipt = await tx.wait();
        m.log("repay gas used:", receipt.gasUsed);

        let expectRepayAmount = ethers.BigNumber.from("100000616117452480");
        let collectedFeeExpected = 0;

        await expect(tx).to.not.emit(dETH, "AccFeeUpdated");
        await expect(tx).to.emit(dETH, "CollectedFeeUpdated").withArgs(0);
        await expect(tx)
          .to.emit(dETH, "Transfer")
          .withArgs(
            deployer.address,
            ethers.constants.AddressZero,
            borrowAmount
          );
        await expect(tx)
          .to.emit(router, "Repaid")
          .withArgs(deployer.address, ETHAddress, expectRepayAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(ETHAddress, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 24, 8);
      });

      it("should repay ETH via protocols supply", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          dETH,
          borrowAmount,
        } = await loadFixture(repayETHViaProtocolsSupply);

        let accFeeBefore = await dETH.accFee();
        let collectedFeeBefore = await dETH.collectedFee();
        let dETHBalanceBefore = await dETH.balanceOf(deployer.address);
        let userBalanceBefore = await provider.getBalance(deployer.address);
        let userDebtStatusBefore = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsBefore = await router.totalLendings(ETHAddress);

        let tx = await router.repay(
          {
            asset: ETHAddress,
            amount: borrowAmount.mul(2),
            to: deployer.address,
          },
          true,
          { value: borrowAmount.mul(2) }
        );

        const receipt = await tx.wait();
        const gasFee = receipt.effectiveGasPrice.mul(receipt.gasUsed);

        let accFeeAfter = await dETH.accFee();
        let collectedFeeAfter = await dETH.collectedFee();
        let dETHBalanceAfter = await dETH.balanceOf(deployer.address);
        let userBalanceAfter = await provider.getBalance(deployer.address);
        let userDebtStatusAfter = await config.userDebtAndCollateral(
          deployer.address
        );
        let totalLendingsAfter = await router.totalLendings(ETHAddress);

        let accFee = accFeeAfter.sub(accFeeBefore);
        let collectedFee = collectedFeeAfter.sub(collectedFeeBefore);
        let dETHBurntAmount = dETHBalanceBefore.sub(dETHBalanceAfter);
        let userTokenRepaid = userBalanceBefore
          .sub(userBalanceAfter)
          .sub(gasFee);
        let routerBalance = await provider.getBalance(router.address);
        let protocolsHandlerBalance = await provider.getBalance(
          protocolsHandler.address
        );

        let expectRepayAmount = ethers.BigNumber.from("100000301981351623");
        let accFeeDeltaExpect = expectRepayAmount
          .sub(borrowAmount)
          .mul(await dETH.feeRate())
          .div(ethers.BigNumber.from("1000000"));

        expect(dETHBurntAmount).to.equal(borrowAmount);
        expect(userTokenRepaid).to.equal(expectRepayAmount);
        expect(accFee).to.equal(accFeeDeltaExpect);
        expect(collectedFee).to.equal(accFeeDeltaExpect);
        expect(routerBalance).to.equal(0);
        expect(protocolsHandlerBalance).to.equal(0);
        expect(userDebtStatusBefore).to.equal(48);
        expect(userDebtStatusAfter).to.equal(32);
        expect(totalLendingsBefore).to.equal("100000000000000000");
        expect(totalLendingsAfter).to.equal("0");
      });

      it("should emit events when repay ETH via protocols supply", async () => {
        const {
          deployer,
          feeCollector,
          router,
          config,
          protocolsHandler,
          dETH,
          borrowAmount,
        } = await loadFixture(repayETHViaProtocolsSupply);

        let tx = await router.repay(
          {
            asset: ETHAddress,
            amount: borrowAmount.mul(2),
            to: deployer.address,
          },
          true,
          { value: borrowAmount.mul(2) }
        );
        let receipt = await tx.wait();
        m.log("repay gas used:", receipt.gasUsed);

        let expectRepayAmount = ethers.BigNumber.from("100000301981351623");
        let collectedFeeExpected = expectRepayAmount
          .sub(borrowAmount)
          .mul(await dETH.feeRate())
          .div(ethers.BigNumber.from("1000000"));

        await expect(tx)
          .to.emit(dETH, "AccFeeUpdated")
          .withArgs(collectedFeeExpected, collectedFeeExpected.mul(10));
        await expect(tx)
          .to.emit(dETH, "CollectedFeeUpdated")
          .withArgs(collectedFeeExpected);
        await expect(tx)
          .to.emit(dETH, "Transfer")
          .withArgs(
            deployer.address,
            ethers.constants.AddressZero,
            borrowAmount
          );
        await expect(tx)
          .to.emit(router, "Repaid")
          .withArgs(deployer.address, ETHAddress, expectRepayAmount);
        await expect(tx)
          .to.emit(router, "TotalLendingsUpdated")
          .withArgs(ETHAddress, 0);
        await expect(tx)
          .to.emit(config, "UserDebtAndCollateralSet")
          .withArgs(deployer.address, 48, 32);
      });
    });
  });

  describe("router liquidate tests", function () {
    async function liquidateToken0() {
      const deploys = await loadFixture(RouterTestFixture);

      // value of supply = 2 * value of borrow
      let borrowAmount = ethers.utils.parseUnits("0.1", "ether");
      let supplyAmount = ethers.BigNumber.from("20000000");

      let { sToken } = await supply(
        deploys.deployer,
        deploys.router,
        deploys.usdt,
        supplyAmount
      );

      let dToken0 = await borrow(
        deploys.deployer,
        deploys.router,
        deploys.token0,
        borrowAmount
      );

      return {
        deployer: deploys.deployer,
        router: deploys.router,
        config: deploys.config,
        priceOracle: deploys.priceOracle,
        token0: deploys.token0,
        dToken0: dToken0,
        usdt: deploys.usdt,
        sUSDT: sToken,
        borrowAmount: borrowAmount,
      };
    }

    it("should not liquidate token0", async () => {
      const {
        deployer,
        router,
        config,
        priceOracle,
        token0,
        dToken0,
        usdt,
        sUSDT,
        borrowAmount,
      } = await loadFixture(liquidateToken0);

      await router.setBlockActions(token0.address, 2 ** 4);
      let tx = router.liquidate(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        {
          asset: usdt.address,
          amount: 0,
          to: deployer.address,
        }
      );
      await expect(tx).to.be.revertedWith("LiquidateLogic: action paused");
      await router.setBlockActions(token0.address, 0);

      await router.setBlockActions(ethers.constants.AddressZero, 2 ** 4);
      tx = router.liquidate(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        {
          asset: usdt.address,
          amount: 0,
          to: deployer.address,
        }
      );
      await expect(tx).to.be.revertedWith("LiquidateLogic: action paused");
      await router.setBlockActions(ethers.constants.AddressZero, 0);

      tx = router.liquidate(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        {
          asset: usdt.address,
          amount: 0,
          to: deployer.address,
        }
      );
      await expect(tx).to.be.revertedWith(
        "LiquidateLogic: Liquidate not allowed"
      );

      tx = router.liquidate(
        {
          asset: usdt.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        {
          asset: usdt.address,
          amount: 0,
          to: deployer.address,
        }
      );
      await expect(tx).to.be.revertedWith(
        "LiquidateLogic: Token is not borrowing"
      );

      tx = router.liquidate(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        {
          asset: token0.address,
          amount: 0,
          to: deployer.address,
        }
      );
      await expect(tx).to.be.revertedWith(
        "LiquidateLogic: Token is not using as collateral"
      );

      await priceOracle.setAssetPrice(token0.address, 16000000000); // set price to 160.00
      await supply(deployer, router, token0, 1);
      await token0.approve(router.address, borrowAmount);

      await router.toggleToken(token0.address);
      tx = router.liquidate(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        {
          asset: usdt.address,
          amount: 0,
          to: deployer.address,
        }
      );
      await expect(tx).to.be.revertedWith(
        "LiquidateLogic: Paused token not liquidated"
      );
      await router.toggleToken(token0.address);

      tx = router.liquidate(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        {
          asset: usdt.address,
          amount: borrowAmount,
          to: deployer.address,
        }
      );

      await expect(tx).to.be.revertedWith(
        "LiquidateLogic: insufficient redeem amount"
      );
    });

    it("should liquidate properly", async () => {
      const {
        deployer,
        router,
        config,
        priceOracle,
        token0,
        dToken0,
        usdt,
        sUSDT,
        borrowAmount,
      } = await loadFixture(liquidateToken0);

      await priceOracle.setAssetPrice(token0.address, 16000000000); // set price to 160.00
      await token0.approve(router.address, borrowAmount);

      let dToken0BalanceBefore = await dToken0.balanceOf(deployer.address);
      let liquidatorBalanceBeforeRepay = await token0.balanceOf(
        deployer.address
      );
      let sUsdtBalanceBefore = await sUSDT.balanceOf(deployer.address);
      let usdtBalanceBeforeRedeem = await usdt.balanceOf(deployer.address);

      let tx = await router.liquidate(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        {
          asset: usdt.address,
          amount: 0,
          to: deployer.address,
        }
      );
      let dToken0BalanceAfter = await dToken0.balanceOf(deployer.address);
      let liquidatorBalanceAfterRepay = await token0.balanceOf(
        deployer.address
      );
      let sUsdtBalanceAfter = await sUSDT.balanceOf(deployer.address);
      let usdtBalanceAfterRedeem = await usdt.balanceOf(deployer.address);

      let dTokenRepaid = dToken0BalanceBefore.sub(dToken0BalanceAfter);
      let liquidatorRepaid = liquidatorBalanceBeforeRepay.sub(
        liquidatorBalanceAfterRepay
      );
      let debtsRemaining = await dToken0.scaledDebtOf(deployer.address);
      let sUsdtBurned = sUsdtBalanceBefore.sub(sUsdtBalanceAfter);
      let usdtReceived = usdtBalanceAfterRedeem.sub(usdtBalanceBeforeRedeem);

      let expectLiquidatorRepaidAmount = "62500018750000000";

      expect(liquidatorRepaid).to.equal(expectLiquidatorRepaidAmount);
      expect(dTokenRepaid).to.equal("62500016498107962");
      expect(debtsRemaining).to.equal("37499984853026310");
      expect(sUsdtBurned).to.equal("10800000");
      expect(usdtReceived).to.equal("10800003");
    });

    it("should emit events when liquidating", async () => {
      const {
        deployer,
        router,
        config,
        priceOracle,
        token0,
        dToken0,
        usdt,
        sUSDT,
        borrowAmount,
      } = await loadFixture(liquidateToken0);

      await priceOracle.setAssetPrice(token0.address, 16000000000); // set price to 160.00
      await token0.approve(router.address, borrowAmount);

      let tx = await router.liquidate(
        {
          asset: token0.address,
          amount: borrowAmount,
          to: deployer.address,
        },
        {
          asset: usdt.address,
          amount: 0,
          to: deployer.address,
        }
      );

      let receipt = await tx.wait();
      m.log("liquidate gas used:", receipt.gasUsed);

      let expectLiquidatorRepaidAmount = "62500018750000000";

      await expect(tx)
        .emit(router, "Repaid")
        .withArgs(
          deployer.address,
          token0.address,
          expectLiquidatorRepaidAmount
        );
      await expect(tx)
        .emit(router, "Redeemed")
        .withArgs(deployer.address, usdt.address, "10800003");
    });
  });
});
