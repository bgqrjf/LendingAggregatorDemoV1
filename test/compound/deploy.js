const { ethers } = require("hardhat");

exports.deployContracts = async ({token0, usdt}) => {
  const [deployer] = await ethers.getSigners();

  let Comptroller = await ethers.getContractFactory("Comptroller");
  let comptroller = await Comptroller.deploy();

  let InterestModel = await ethers.getContractFactory("JumpRateModelV2");
  let interestModel = await InterestModel.deploy(
    ethers.BigNumber.from("0"), 
    ethers.BigNumber.from("40000000000000000"),  //23782343987 = x * 1e18 / blocksPerYear * kink
    ethers.BigNumber.from("1090000000000000000"),  // 518455098934 = x / blocksPerYear
    ethers.BigNumber.from("800000000000000000"), 
    deployer.address
  );
  
  let CErc20 = await ethers.getContractFactory("CErc20Delegate");
  let cERC20Implemention = await CErc20.deploy();
  let CErc20Delegator = await ethers.getContractFactory("CErc20Delegator");
  let cToken0 = await CErc20Delegator.deploy(
    token0.address, 
    comptroller.address, 
    interestModel.address, 
    ethers.BigNumber.from("1000000000000000000"), 
    "compound Token0", 
    "cToken0", 
    18, 
    deployer.address, 
    cERC20Implemention.address,
    "0x",
  );

  let cUSDT = await CErc20Delegator.deploy(
    usdt.address, 
    comptroller.address, 
    interestModel.address, 
    ethers.BigNumber.from("1000000"), 
    "compound USDT", 
    "cUSDT", 
    6, 
    deployer.address, 
    cERC20Implemention.address,
    "0x",
  );

  let CEther = await ethers.getContractFactory("CEther");
  let cETH = await CEther.deploy(
    comptroller.address,
    interestModel.address,
    ethers.BigNumber.from("1000000000000000000"), 
    "compound ETH",
    "cETH",
    18,
    deployer.address
  );

  await comptroller._supportMarket(cToken0.address);
  await comptroller._supportMarket(cUSDT.address);
  await comptroller._supportMarket(cETH.address);


  let PriceOracle = await ethers.getContractFactory("PriceOracle");
  let priceOracle = await PriceOracle.deploy();
  await comptroller._setPriceOracle(priceOracle.address)
  await priceOracle.setUnderlyingPrice(cToken0.address, ethers.BigNumber.from("100000000000000000000") );
  await priceOracle.setUnderlyingPrice(cUSDT.address, ethers.BigNumber.from("1000000000000000000000000000000") );
  await priceOracle.setUnderlyingPrice(cETH.address, ethers.BigNumber.from("2000000000000000000000") );
  await comptroller._setCollateralFactor(cToken0.address,  ethers.BigNumber.from("790000000000000000"));
  await comptroller._setCollateralFactor(cUSDT.address,  ethers.BigNumber.from("840000000000000000"));
  await comptroller._setCollateralFactor(cETH.address,  ethers.BigNumber.from("825000000000000000"));


  return{
    comptroller: comptroller,
    cToken0: cToken0,
    cUSDT: cUSDT,
    cETH: cETH,
  }
}
