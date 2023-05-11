const { ethers, waffle } = require("hardhat");
const m = require("mocha-logger");
const transparentProxy = require("./utils/transparentProxy.js");

async function main() {
  const [deployer] = await ethers.getSigners();

  let underlyings = process.env.underlyings.split(",");
  let decimals = process.env.decimals.split(",");
  let symbols = process.env.symbols.split(",");
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

  // strategy
  let Strategy = await ethers.getContractFactory("Strategy");
  let strategy = await Strategy.deploy();
  await strategy.deployed();
  m.log("strategy deployed:", strategy.address);

  let tx = await strategy.setMaxLTV(process.env.maxLTV);
  await tx.wait();
  m.log("strategy setMaxLTV:", tx.hash);

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
  await aaveHandler.deployed();
  m.log("aaveHandler deployed:", aaveHandler.address);

  let CompoundHandler = await ethers.getContractFactory("CompoundLogic");
  let compoundHandler = await CompoundHandler.deploy(
    protocolsHandler.address,
    comptroller.address,
    process.env.cETH,
    process.env.comp,
    rewards.address,
    { gasLimit: 5000000 }
  );
  await compoundHandler.deployed();
  m.log("compoundHandler deployed:", compoundHandler.address);

  // config
  let config = await transparentProxy.deployProxy({
    implementationFactory: "Config",
    proxyAdmin: proxyAdmin,
  });

  tx = await config.transferOwnership(deployer.address);
  await tx.wait();
  m.log("config transferOwnership:", tx.hash);

  // sToken
  let SToken = await ethers.getContractFactory("SToken");
  let sToken = await SToken.deploy();
  await sToken.deployed();
  m.log("sToken deployed:", sToken.address);

  // dToken
  let DToken = await ethers.getContractFactory("DToken");
  let dToken = await DToken.deploy();
  await dToken.deployed();
  m.log("dToken deployed:", dToken.address);

  // router
  let SupplyLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/SupplyLogic.sol:SupplyLogic"
  );
  let supplyLogic = await SupplyLogic.deploy();
  await supplyLogic.deployed();
  m.log("supplyLogic deployed:", supplyLogic.address);

  let RedeemLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/RedeemLogic.sol:RedeemLogic"
  );
  let redeemLogic = await RedeemLogic.deploy();
  await redeemLogic.deployed();
  m.log("redeemLogic deployed:", redeemLogic.address);

  let BorrowLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/BorrowLogic.sol:BorrowLogic"
  );
  let borrowLogic = await BorrowLogic.deploy();
  await borrowLogic.deployed();
  m.log("borrowLogic deployed:", borrowLogic.address);

  let RepayLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/RepayLogic.sol:RepayLogic"
  );
  let repayLogic = await RepayLogic.deploy();
  await repayLogic.deployed();
  m.log("repayLogic deployed:", repayLogic.address);

  let LiquidateLogic = await ethers.getContractFactory(
    "contracts/libraries/externals/LiquidateLogic.sol:LiquidateLogic"
  );
  let liquidateLogic = await LiquidateLogic.deploy();
  await liquidateLogic.deployed();
  m.log("liquidateLogic deployed:", liquidateLogic.address);

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
      process.env.priceOracle,
      config.address,
      rewards.address,
      sToken.address,
      dToken.address,
      ethers.constants.AddressZero,
      process.env.feeCollector,
    ],
    proxyAdmin: proxyAdmin,
  });

  tx = await config.setRouter(router.address);
  await tx.wait();
  m.log("config setRouter:", tx.hash);

  tx = await protocolsHandler.transferOwnership(router.address);
  await tx.wait();
  m.log("protocolsHandler transferOwnership:", tx.hash);

  tx = await rewards.transferOwnership(router.address);
  await tx.wait();
  m.log("rewards transferOwnership:", tx.hash);

  tx = await router.addProtocol(aaveHandler.address);
  await tx.wait();
  m.log("router addProtocol:", tx.hash);

  tx = await router.addProtocol(compoundHandler.address);
  await tx.wait();
  m.log("router addProtocol:", tx.hash);

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
      },
      feeRate: 10000,
      maxReserve: 0,
      executeSupplyThreshold: 0,
    });
    await tx.wait();
    m.log("router addAsset:", tx.hash);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
