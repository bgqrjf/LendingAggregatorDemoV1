const { ethers } = require("hardhat");
const m = require("mocha-logger");
const ProxyAdmin = require("@openzeppelin/contracts/build/contracts/ProxyAdmin.json");
const TransparentUpgradeableProxy = require("@openzeppelin/contracts/build/contracts/TransparentUpgradeableProxy.json");

exports.deployProxy = async ({
  implementationFactory,
  libraries,
  initializeParams,
  proxyAdmin,
}) => {
  let Implementation = await ethers.getContractFactory(implementationFactory, {
    libraries: libraries,
  });
  let implementation = await Implementation.deploy();
  await implementation.deployed();
  m.log(
    implementationFactory,
    "implementation deployed:",
    implementation.address
  );

  let Proxy = await ethers.getContractFactory(
    TransparentUpgradeableProxy.abi,
    TransparentUpgradeableProxy.bytecode
  );

  let initializeData = implementation.interface.encodeFunctionData(
    "initialize",
    initializeParams
  );

  let proxy = await Proxy.deploy(
    implementation.address,
    proxyAdmin.address,
    initializeData
  );
  await proxy.deployed();
  m.log(implementationFactory, "proxy deployed:", proxy.address);

  return await ethers.getContractAt(implementationFactory, proxy.address);
};

exports.deployProxyAdmin = async () => {
  let Admin = await ethers.getContractFactory(
    ProxyAdmin.abi,
    ProxyAdmin.bytecode
  );

  let admin = await Admin.deploy();
  await admin.deployed();
  m.log("proxyAdmin deployed:", admin.address);

  return admin;
};
