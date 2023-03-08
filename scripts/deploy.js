const { ethers, waffle } = require("hardhat");
const m = require("mocha-logger");
const transparentProxy = require("./utils/transparentProxy.js");

async function main() {
  const [feeCollector] = await ethers.getSigners();

  let underlyings = process.env.underlyings.split(",");
  let decimals = process.env.decimals.split(",");
  let symbols = process.env.symbols.split(",");
  let maxLTVs = process.env.maxLTVs.split(",");
  let aPool = await ethers.getContractAt(
    "ILendingPool",
    process.env.AAVELendingPool
  );
  let comptroller = await ethers.getContractAt(
    "Comptroller",
    process.env.comptroller
  );
  let wETH = await ethers.getContractAt(
    "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
    process.env.wETH
  );
  let cTokens = process.env.cTokens.split(",");

  let Strategy = await ethers.getContractFactory("Strategy");
  let strategy = await Strategy.deploy();
  await strategy.deployed();
  m.log("strategy:", strategy.address);

  let tx = await strategy.setMaxLTVs(underlyings, maxLTVs);
  await tx.wait();

  // protocolsHandler
  const proxyAdmin = await transparentProxy.deployProxyAdmin();
  m.log("proxyAdmin:", proxyAdmin.address);

  let protocolsHandler = await transparentProxy.deployProxy({
    implementationFactory: "ProtocolsHandler",
    libraries: {},
    initializeParams: [[], strategy.address],
    proxyAdmin: proxyAdmin,
  });
  m.log("protocolsHandler(proxy):", protocolsHandler.address);

  let AAVEHandler = await ethers.getContractFactory("AAVEV2Logic");
  let aaveHandler = await AAVEHandler.deploy(
    protocolsHandler.address,
    aPool.address,
    wETH.address
  );
  await aaveHandler.deployed();

  m.log("aaveV2Logic:", aaveHandler.address);

  let CompoundHandler = await ethers.getContractFactory("CompoundLogic");
  let compoundHandler = await CompoundHandler.deploy(
    protocolsHandler.address,
    comptroller.address,
    process.env.cETH,
    process.env.comp,
    { gasLimit: 5000000 }
  );
  await compoundHandler.deployed();
  m.log("compoundLogic:", compoundHandler.address);

  for (let i = 0; i < cTokens.length; i++) {
    tx = await compoundHandler.updateCTokenList(cTokens[i]);
    await tx.wait();
  }

  // config
  let config = await transparentProxy.deployProxy({
    implementationFactory: "Config",
    proxyAdmin: proxyAdmin,
  });
  m.log("config(proxy):", config.address);

  // rewards
  let Rewards = await ethers.getContractFactory("Rewards");
  let rewards = await Rewards.deploy(protocolsHandler.address);
  await rewards.deployed();
  m.log("rewards:", rewards.address);

  // sToken
  let SToken = await ethers.getContractFactory("SToken");
  let sToken = await SToken.deploy();
  await sToken.deployed();
  m.log("sToken:", sToken.address);

  // dToken
  let DToken = await ethers.getContractFactory("DToken");
  let dToken = await DToken.deploy();
  await dToken.deployed();
  m.log("dToken:", dToken.address);

  // router
  let SupplyLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/SupplyLogic.sol:SupplyLogic"
  );
  let supplyLogic = await SupplyLogic.deploy();
  await supplyLogic.deployed();
  m.log("supplyLogic:", supplyLogic.address);

  let RedeemLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/RedeemLogic.sol:RedeemLogic"
  );
  let redeemLogic = await RedeemLogic.deploy();
  await redeemLogic.deployed();
  m.log("redeemLogic:", redeemLogic.address);

  let BorrowLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/BorrowLogic.sol:BorrowLogic"
  );
  let borrowLogic = await BorrowLogic.deploy();
  await borrowLogic.deployed();
  m.log("borrowLogic:", borrowLogic.address);

  let RepayLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/RepayLogic.sol:RepayLogic"
  );
  let repayLogic = await RepayLogic.deploy();
  await repayLogic.deployed();
  m.log("repayLogic:", repayLogic.address);

  let LiquidateLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/LiquidateLogic.sol:LiquidateLogic"
  );
  let liquidateLogic = await LiquidateLogic.deploy();
  await liquidateLogic.deployed();
  m.log("liquidateLogic:", liquidateLogic.address);

  let router = await transparentProxy.deployProxy({
    implementationFactory: "Router",
    libraries: {
      SupplyLogic: supplyLogic.address,
      RedeemLogic: redeemLogic.address,
      BorrowLogic: borrowLogic.address,
      RepayLogic: repayLogic.address,
      LiquidateLogic: liquidateLogic.address,
      RewardLogic: ethers.constants.AddressZero,
    },
    initializeParams: [
      protocolsHandler.address,
      process.env.priceOracle,
      config.address,
      rewards.address,
      sToken.address,
      dToken.address,
      ethers.constants.AddressZero,
      feeCollector.address,
    ],
    proxyAdmin: proxyAdmin,
  });
  m.log("router:", router.address);

  tx = await config.setRouter(router.address);
  await tx.wait();
  tx = await protocolsHandler.transferOwnership(router.address);
  await tx.wait();
  tx = await rewards.transferOwnership(router.address);
  await tx.wait();

  tx = await router.addProtocol(aaveHandler.address);
  await tx.wait();
  tx = await router.addProtocol(compoundHandler.address);
  await tx.wait();

  for (i = 0; i < underlyings.length; i++) {
    tx = await router.addAsset({
      underlying: underlyings[i],
      decimals: decimals[i],
      collateralable: true,
      sTokenName: "LendingAggregator supply" + symbols[i],
      sTokenSymbol: "s" + symbols[i],
      dTokenName: "LendingAggregator debt" + symbols[i],
      dTokenSymbol: "d" + symbols[i],
      config: {
        maxLTV: 700000,
        liquidateLTV: 750000,
        maxLiquidateRatio: 500000,
        liquidateRewardRatio: 1080000,
        feeRate: 10000,
      },
      maxReserve: 0,
      executeSupplyThreshold: 0,
    });
    await tx.wait();
  }

  let QueryHelper = await ethers.getContractFactory("QueryHelper");
  let queryHelper = await QueryHelper.deploy(
    router.address,
    aaveHandler.address,
    compoundHandler.address
  );
  await queryHelper.deployed();
  m.log("queryHelper:", queryHelper.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
