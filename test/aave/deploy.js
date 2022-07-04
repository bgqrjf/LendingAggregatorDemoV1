const { ethers } = require("hardhat");

exports.deployContracts = async ({token0, usdt}) => {
  const [deployer] = await ethers.getSigners();

  // deploy libraries
  const BorrowLogic = await ethers.getContractFactory(`BorrowLogic`);
  const borrowLogic = await BorrowLogic.deploy();
  const BridgeLogic = await ethers.getContractFactory(`BridgeLogic`);
  const bridgeLogic = await BridgeLogic.deploy();
  const CalldataLogic = await ethers.getContractFactory(`CalldataLogic`);
  const calldataLogic = await CalldataLogic.deploy();
  const ConfiguratorLogic = await ethers.getContractFactory(`ConfiguratorLogic`);
  const configuratorLogic = await ConfiguratorLogic.deploy();
  const EModeLogic = await ethers.getContractFactory(`EModeLogic`);
  const eModeLogic = await EModeLogic.deploy();
  const FlashLoanLogic = await ethers.getContractFactory(`FlashLoanLogic`,{
    libraries: {
      BorrowLogic: borrowLogic.address,
    },
  });
  const flashLoanLogic = await FlashLoanLogic.deploy();
  const GenericLogic = await ethers.getContractFactory(`GenericLogic`);
  const genericLogic = await GenericLogic.deploy();
  const IsolationModeLogic = await ethers.getContractFactory(`IsolationModeLogic`);
  const isolationModeLogic = await IsolationModeLogic.deploy();
  const LiquidationLogic = await ethers.getContractFactory(`LiquidationLogic`);
  const liquidationLogic = await LiquidationLogic.deploy();
  const PoolLogic = await ethers.getContractFactory(`PoolLogic`);
  const poolLogic = await PoolLogic.deploy();
  const ReserveLogic = await ethers.getContractFactory(`ReserveLogic`);
  const reserveLogic = await ReserveLogic.deploy();
  const SupplyLogic = await ethers.getContractFactory(`SupplyLogic`);
  const supplyLogic = await SupplyLogic.deploy();
  const ValidationLogic = await ethers.getContractFactory(`ValidationLogic`);
  const validationLogic = await ValidationLogic.deploy();

  // deploy poolAddressProvider
  const PoolAddressesProvider = await ethers.getContractFactory(`PoolAddressesProvider`);
  const poolAddressesProvider = await PoolAddressesProvider.deploy(0, deployer.address);

  // deploy ACLManager
  await poolAddressesProvider.setACLAdmin(deployer.address);
  const ACLMANAGER = await ethers.getContractFactory(`ACLManager`);
  const ACLManager = await ACLMANAGER.deploy(poolAddressesProvider.address, {gasLimit: 5000000});
  await poolAddressesProvider.setACLManager(ACLManager.address);
  await ACLManager.addPoolAdmin(deployer.address);

  // deploy pool Implementation
  const Pool = await ethers.getContractFactory(`contracts/AAVE/core/protocol/pool/Pool.sol:Pool`,{
    libraries:{
      BorrowLogic: borrowLogic.address,
      BridgeLogic: bridgeLogic.address,
      EModeLogic: eModeLogic.address,
      FlashLoanLogic: flashLoanLogic.address,
      LiquidationLogic: liquidationLogic.address,
      PoolLogic: poolLogic.address,
      SupplyLogic: supplyLogic.address,
    },
  });
  const poolImplement = await Pool.deploy(poolAddressesProvider.address);
  

  // deploy pool proxy
  let txsetPool = await poolAddressesProvider.setPoolImpl(poolImplement.address);
  let txsetPoolReceipt = await txsetPool.wait();
  // const InitializableImmutableAdminUpgradeabilityProxy = await ethers.getContractFactory(`InitializableImmutableAdminUpgradeabilityProxy`);
  const pool = poolImplement.attach("0x" + JSON.stringify(txsetPoolReceipt.logs[0].topics[2]).substring(27,67))

  // deploy pool Configurator Implementation
  const PoolConfigurator = await ethers.getContractFactory(`PoolConfigurator`,{
    libraries:{
      ConfiguratorLogic: configuratorLogic.address,
    },
  });
  const poolConfiguratorImplement = await PoolConfigurator.deploy();

  // deploy pool Implementation
  let txSetPoolImpl = await poolAddressesProvider.setPoolConfiguratorImpl(poolConfiguratorImplement.address);
  let txSetPoolImplReceipt = await txSetPoolImpl.wait();
  const poolConfigurator = PoolConfigurator.attach("0x" + JSON.stringify(txSetPoolImplReceipt.logs[0].topics[2]).substring(27,67))

  // deploy poolDataProvider
  const AaveProtocolDataProvider = await ethers.getContractFactory(`AaveProtocolDataProvider`);
  const aaveProtocolDataProvider = await AaveProtocolDataProvider.deploy(poolAddressesProvider.address);

  // deploy AaveOracle
  const PriceOracle = await ethers.getContractFactory(`MockAAVEPriceOracle`);
  const priceOracle = await PriceOracle.deploy(poolAddressesProvider.address, "0x0000000000000000000000000000000000000000", 100000000);
  await poolAddressesProvider.setPriceOracle(priceOracle.address);

  // deploy Atoken implementation
  const AToken = await ethers.getContractFactory(`AToken`);
  const aTokenImplementation = await AToken.deploy(pool.address);

  // deploy Stoken implementation
  const StableDebtToken = await ethers.getContractFactory(`StableDebtToken`);
  const stableDebtTokenImplementation = await StableDebtToken.deploy(pool.address);

  // deploy Vtoken implementation
  const VariableDebtToken = await ethers.getContractFactory(`VariableDebtToken`);
  const variableDebtTokenImplementation = await VariableDebtToken.deploy(pool.address);
  
  // deploy ERC20
  const WETH = await ethers.getContractFactory(`MockWETH`);
  const wETH = await WETH.deploy();
  await priceOracle.setAssetPrice(token0.address, 10000000000); // set price to 100.00
  await priceOracle.setAssetPrice(usdt.address, 100000000); // set price to 1.00
  await priceOracle.setAssetPrice(wETH.address, 200000000000); // set price to 2000.00

  const DefaultReserveInterestRateStrategy = await ethers.getContractFactory(`DefaultReserveInterestRateStrategy`);
  const defaultReserveInterestRateStrategy = await DefaultReserveInterestRateStrategy.deploy(
    poolAddressesProvider.address,                            // provider
    ethers.BigNumber.from("900000000000000000000000000"),     // optimalUsageRatio
    0,                                                        // baseVariableBorrowRate
    ethers.BigNumber.from("40000000000000000000000000"),      // variableRateSlope1
    ethers.BigNumber.from("600000000000000000000000000"),     // variableRateSlope2
    ethers.BigNumber.from("5000000000000000000000000"),       // stableRateSlope1
    ethers.BigNumber.from("600000000000000000000000000"),     // stableRateSlope2
    ethers.BigNumber.from("50000000000000000000000000"),      // baseStableRateOffset 
    ethers.BigNumber.from("800000000000000000000000000"),     // stableRateExcessOffset 
    ethers.BigNumber.from("200000000000000000000000000"),     // optimalStableToTotalDebtRatio
  );

  // init reserve
  await poolConfigurator.initReserves([
    {
      aTokenImpl: aTokenImplementation.address,
      stableDebtTokenImpl: stableDebtTokenImplementation.address,
      variableDebtTokenImpl: variableDebtTokenImplementation.address,
      underlyingAssetDecimals: 18,
      interestRateStrategyAddress: defaultReserveInterestRateStrategy.address,
      underlyingAsset: token0.address,
      treasury: "0x0ADf66Db5FCBa819c4360187C1c14C04a20ec7d4",  
      incentivesController: "0x0000000000000000000000000000000000000000",
      aTokenName: "AAVE-V3 token0",
      aTokenSymbol: "aToken0",
      variableDebtTokenName: "vToken0",
      variableDebtTokenSymbol: "vToken0",
      stableDebtTokenName: "sToken0",
      stableDebtTokenSymbol: "sToken0",
      params: "0x",
    },
    {
      aTokenImpl: aTokenImplementation.address,
      stableDebtTokenImpl: stableDebtTokenImplementation.address,
      variableDebtTokenImpl: variableDebtTokenImplementation.address,
      underlyingAssetDecimals: 6,
      interestRateStrategyAddress: defaultReserveInterestRateStrategy.address,
      underlyingAsset: usdt.address,
      treasury: "0x0ADf66Db5FCBa819c4360187C1c14C04a20ec7d4",  
      incentivesController: "0x0000000000000000000000000000000000000000",
      aTokenName: "AAVE-V3 USDT",
      aTokenSymbol: "aUSDT",
      variableDebtTokenName: "vUSDT",
      variableDebtTokenSymbol: "vUSDT",
      stableDebtTokenName: "sUSDT",
      stableDebtTokenSymbol: "sUSDT",
      params: "0x",
    },
    {
      aTokenImpl: aTokenImplementation.address,
      stableDebtTokenImpl: stableDebtTokenImplementation.address,
      variableDebtTokenImpl: variableDebtTokenImplementation.address,
      underlyingAssetDecimals: 18,
      interestRateStrategyAddress: defaultReserveInterestRateStrategy.address,
      underlyingAsset: wETH.address,
      treasury: "0x0ADf66Db5FCBa819c4360187C1c14C04a20ec7d4",  
      incentivesController: "0x0000000000000000000000000000000000000000",
      aTokenName: "AAVE-V3 WETH",
      aTokenSymbol: "aWETH",
      variableDebtTokenName: "vWETH",
      variableDebtTokenSymbol: "vWETH",
      stableDebtTokenName: "sWETH",
      stableDebtTokenSymbol: "sWETH",
      params: "0x",
    },
  ])

  let ReservesSetupHelper = await ethers.getContractFactory("ReservesSetupHelper");
  let reservesSetupHelper = await ReservesSetupHelper.deploy();

  await ACLManager.addRiskAdmin(reservesSetupHelper.address)
  
  await reservesSetupHelper.configureReserves(
    poolConfigurator.address, 
    [
      {
        asset: token0.address,
        baseLTV: 7500,
        liquidationThreshold: 8000,
        liquidationBonus: 10500,
        reserveFactor: 1000,
        borrowCap: 0,
        supplyCap: 0,
        stableBorrowingEnabled: 1,
        borrowingEnabled: 1
      },
      {
        asset: wETH.address,
        baseLTV: 7500,
        liquidationThreshold: 8000,
        liquidationBonus: 10500,
        reserveFactor: 1000,
        borrowCap: 0,
        supplyCap: 0,
        stableBorrowingEnabled: 1,
        borrowingEnabled: 1
      },
      {
        asset: usdt.address,
        baseLTV: 7500,
        liquidationThreshold: 8000,
        liquidationBonus: 10500,
        reserveFactor: 1000,
        borrowCap: 0,
        supplyCap: 0,
        stableBorrowingEnabled: 1,
        borrowingEnabled: 1
      },
    ]
  )

  await ACLManager.removeRiskAdmin(reservesSetupHelper.address);

  // await poolConfigurator.configureReserveAsCollateral(token0.address, 7500, 8000, 10500);
  // await poolConfigurator.configureReserveAsCollateral(wETH.address, 7500, 8000, 10500);
  // await poolConfigurator.configureReserveAsCollateral(usdt.address, 7500, 8000, 10500);
  // await poolConfigurator.setReserveBorrowing(token0.address, true);
  // await poolConfigurator.setReserveBorrowing(wETH.address, true);
  // await poolConfigurator.setReserveBorrowing(usdt.address, true);

  return {
    signer: deployer,
    queryHelper: aaveProtocolDataProvider,
    token0: token0,
    usdt: usdt,
    wETH: wETH,
    pool: pool, 
    priceOracle: priceOracle
  }
}