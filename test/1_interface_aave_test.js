const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const aave = require("./aave/deploy");
const m = require("mocha-logger");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Protocol Interfaces tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  async function aaveInterfaceTestFixture() {
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

    let AAVEHandler = await ethers.getContractFactory("AAVELogic");
    // _aaveTokenAddress
    let aaveHandler = await AAVEHandler.deploy(
      aPool.address,
      wETH.address,
      wETH.address
    );

    return {
      deployer: aaveContracts.signer,
      aPool: aPool,
      aOracle: aOracle,
      aaveHandler: aaveHandler,
      token0: token0,
      usdt: usdt,
      wETH: wETH,
    };
  }

  describe("AAVE interface tests", function () {
    it("should read data properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let wETH = deploys.wETH;
      let aPool = deploys.aPool;

      let aaveHandler = deploys.aaveHandler;
      expect(await aaveHandler.RAY()).to.equal("1000000000000000000000000000");
      expect(await aaveHandler.BASE()).to.equal("1000000000000000000000");
      expect((await aaveHandler.wrappedNative()).toLowerCase()).to.equal(
        wETH.address.toLowerCase()
      );
      expect((await aaveHandler.pool()).toLowerCase()).to.equal(
        aPool.address.toLowerCase()
      );
    });

    it("should updateSupplyShare properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let simulateSupplyData = await aaveHandler.lastSimulatedSupply(
        token0.address,
        deployer.address
      );

      expect(simulateSupplyData.index).to.equal(0);
      expect(simulateSupplyData.amount).to.equal(0);

      await aaveHandler.updateSupplyShare(token0.address, 1234567);

      simulateSupplyData = await aaveHandler.lastSimulatedSupply(
        token0.address,
        deployer.address
      );

      expect(simulateSupplyData.index).to.equal(await aaveHandler.RAY());
      expect(simulateSupplyData.amount).to.equal(1234567);
    });

    it("should updateBorrowShare properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let simulateBorrowData = await aaveHandler.lastSimulatedBorrow(
        token0.address,
        deployer.address
      );

      expect(simulateBorrowData.index).to.equal(0);
      expect(simulateBorrowData.amount).to.equal(0);

      await aaveHandler.updateBorrowShare(token0.address, 1234567);

      simulateBorrowData = await aaveHandler.lastSimulatedBorrow(
        token0.address,
        deployer.address
      );

      expect(simulateBorrowData.index).to.equal(await aaveHandler.RAY());
      expect(simulateBorrowData.amount).to.equal(1234567);
    });

    it("should calculate supply Interest properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);
      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(aPool.address, supplyAmount);

      // await aPool.setUserUseReserveAsCollateral(token0.address, true);
      await aaveHandler.updateSupplyShare(token0.address, supplyAmount);

      // deposit aave
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);

      // borrow from aave
      await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

      // forward blocks
      await hre.network.provider.send("hardhat_mine", [
        "0x" + (2102400).toString(16),
      ]);

      let simulateInterest = await aaveHandler.lastSupplyInterest(
        token0.address,
        deployer.address
      );

      let reserveData = await aPool.getReserveData(token0.address);
      let aToken = await ethers.getContractAt(
        "AToken",
        reserveData.aTokenAddress
      );
      let balance = await aToken.balanceOf(deployer.address);

      expect(simulateInterest).to.equal(balance.sub(supplyAmount));
    });

    it("should calculate borrow Interest properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);
      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(aPool.address, supplyAmount);

      // deposit aave
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
      // await aPool.setUserUseReserveAsCollateral(token0.address, true);
      await aaveHandler.updateBorrowShare(token0.address, borrowAmount);

      // borrow from aave
      await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

      // forward blocks
      await hre.network.provider.send("hardhat_mine", [
        "0x" + (2102400).toString(16),
      ]);

      let simulateInterest = await aaveHandler.lastBorrowInterest(
        token0.address,
        deployer.address
      );

      let reserveData = await aPool.getReserveData(token0.address);
      let vToken0 = await ethers.getContractAt(
        "VariableDebtToken",
        reserveData.variableDebtTokenAddress
      );
      let routerVToken0Balance = await vToken0.balanceOf(deployer.address);

      expect(simulateInterest).to.equal(routerVToken0Balance.sub(borrowAmount));
    });

    // it("should getAddAssetData correctly", async () => {
    //   const deploys = await loadFixture(aaveInterfaceTestFixture);

    //   let aaveHandler = deploys.aaveHandler;
    //   let token0 = deploys.token0;
    //   let deployer = deploys.deployer;

    //   let borrowAmount = ethers.BigNumber.from("100000000000000000");
    //   let supplyAmount = borrowAmount.mul(2);
    //   await token0.mint(deployer.address, supplyAmount);
    //   await token0.approve(aPool.address, supplyAmount);

    //   // deposit aave
    //   await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
    //   let data = await aaveHandler.getAddAssetData(token0.address);
    //   m.log("data.target:", data.target);
    //   m.log("data.encodedData:", data.encodedData);

    //   // let tx = {
    //   //   from: deployer.address,
    //   //   to: data.target,
    //   //   value: 0,
    //   //   gasLimit: ethers.utils.hexlify(1000000), // 100000
    //   //   data: data.encodedData,
    //   // };

    //   // await deployer.sendTransaction(tx);
    //   let newConfig = await aPool.getUserConfiguration(deployer.address);
    //   m.log("newConfig:", newConfig);
    // });

    it("should getSupplyData correctly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);
      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(aPool.address, supplyAmount);

      // deposit aave
      let data = await aaveHandler.getSupplyData(token0.address, supplyAmount);

      let tx = {
        from: deployer.address,
        to: data.target,
        value: 0,
        gasLimit: ethers.utils.hexlify(1000000),
        data: data.encodedData,
      };

      await deployer.sendTransaction(tx);

      let reserveData = await aPool.getReserveData(token0.address);
      let aToken0 = await ethers.getContractAt(
        "AToken",
        reserveData.aTokenAddress
      );
      let balance = await aToken0.balanceOf(deployer.address);
      expect(balance).to.equal(supplyAmount);
    });

    it("should getRedeemData correctly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);
      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(aPool.address, supplyAmount);
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);

      let data = await aaveHandler.getRedeemData(token0.address, supplyAmount);

      let tx = {
        from: deployer.address,
        to: data.target,
        value: 0,
        gasLimit: ethers.utils.hexlify(1000000),
        data: data.encodedData,
      };

      await deployer.sendTransaction(tx);

      let reserveData = await aPool.getReserveData(token0.address);
      let aToken0 = await ethers.getContractAt(
        "AToken",
        reserveData.aTokenAddress
      );

      let balance = await aToken0.balanceOf(deployer.address);
      expect(balance).to.equal(0);
    });

    it("should getBorrowData correctly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);
      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(aPool.address, supplyAmount);
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);

      let data = await aaveHandler.getBorrowData(token0.address, borrowAmount);

      let tx = {
        from: deployer.address,
        to: data.target,
        value: 0,
        gasLimit: ethers.utils.hexlify(1000000),
        data: data.encodedData,
      };

      await deployer.sendTransaction(tx);

      let reserveData = await aPool.getReserveData(token0.address);
      let vToken0 = await ethers.getContractAt(
        "VariableDebtToken",
        reserveData.variableDebtTokenAddress
      );
      let routerVToken0Balance = await vToken0.balanceOf(deployer.address);
      expect(routerVToken0Balance).to.equal(borrowAmount);
    });

    it("should getRepayData correctly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);
      await token0.mint(deployer.address, supplyAmount.mul(2));
      await token0.approve(aPool.address, supplyAmount.mul(2));
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
      await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

      let data = await aaveHandler.getRepayData(token0.address, supplyAmount);

      let tx = {
        from: deployer.address,
        to: data.target,
        value: 0,
        gasLimit: ethers.utils.hexlify(1000000),
        data: data.encodedData,
      };

      await deployer.sendTransaction(tx);

      let reserveData = await aPool.getReserveData(token0.address);
      let vToken0 = await ethers.getContractAt(
        "VariableDebtToken",
        reserveData.variableDebtTokenAddress
      );
      let routerVToken0Balance = await vToken0.balanceOf(deployer.address);
      expect(routerVToken0Balance).to.equal(0);
    });

    it("should call supplyOf properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(aPool.address, supplyAmount);
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);

      let token0Supply = await aaveHandler.supplyOf(
        token0.address,
        deployer.address
      );

      expect(token0Supply).to.equal(supplyAmount);
    });

    it("should call debtOf properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(aPool.address, supplyAmount);
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
      await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

      let token0Debt = await aaveHandler.debtOf(
        token0.address,
        deployer.address
      );

      expect(token0Debt).to.equal(borrowAmount);
    });

    it("should calculate totalColletralAndBorrow properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let usdt = deploys.usdt;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowToken0Amount = ethers.BigNumber.from("100000000000000000");
      let supplyToken0Amount = borrowToken0Amount.mul(2);

      await token0.mint(deployer.address, supplyToken0Amount);
      await token0.approve(aPool.address, supplyToken0Amount);
      await aPool.supply(
        token0.address,
        supplyToken0Amount,
        deployer.address,
        0
      );

      let borrowUSDTAmount = ethers.BigNumber.from("10000000");
      let supplyUSDTAmount = borrowUSDTAmount.mul(2);

      await usdt.mint(deployer.address, supplyUSDTAmount);
      await usdt.approve(aPool.address, supplyUSDTAmount);
      await aPool.supply(usdt.address, supplyUSDTAmount, deployer.address, 0);

      await aPool.borrow(
        token0.address,
        borrowToken0Amount,
        2,
        0,
        deployer.address
      );

      await aPool.borrow(
        usdt.address,
        borrowUSDTAmount,
        2,
        0,
        deployer.address
      );

      let [totalColletral, totalBorrow] =
        await aaveHandler.totalColletralAndBorrow(
          deployer.address,
          usdt.address
        );

      expect(totalColletral).to.equal(40000000);
      expect(totalBorrow).to.equal(20000000);
    });

    it("should get currentSupplyRate properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let usdt = deploys.usdt;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(aPool.address, supplyAmount);
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
      await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

      let supplyRate = await aaveHandler.getCurrentSupplyRate(token0.address);
      expect(supplyRate).to.equal(9999);
    });

    it("should get getCurrentBorrowRate properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let usdt = deploys.usdt;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(aPool.address, supplyAmount);
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
      await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

      let borrowRate = await aaveHandler.getCurrentBorrowRate(token0.address);
      expect(borrowRate).to.equal(22222);
    });

    it("should calculate supplyToTargetSupplyRate properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let usdt = deploys.usdt;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount.mul(2));
      await token0.approve(aPool.address, supplyAmount.mul(2));
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
      await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

      let targetRate = 5000; // 0.5%
      let params = await aaveHandler.getUsageParams(token0.address, 0);
      let amountToSupply = await aaveHandler.supplyToTargetSupplyRate(
        targetRate,
        params
      );

      await aPool.supply(token0.address, amountToSupply, deployer.address, 0);
      let supplyRate = await aaveHandler.getCurrentSupplyRate(token0.address);

      expect(supplyRate).to.equal(targetRate);
    });

    it("should calculate borrowToTargetBorrowRate properly", async () => {
      const deploys = await loadFixture(aaveInterfaceTestFixture);

      let aaveHandler = deploys.aaveHandler;
      let token0 = deploys.token0;
      let usdt = deploys.usdt;
      let deployer = deploys.deployer;
      let aPool = deploys.aPool;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(3);

      await token0.mint(deployer.address, supplyAmount.mul(2));
      await token0.approve(aPool.address, supplyAmount.mul(2));
      await aPool.supply(token0.address, supplyAmount, deployer.address, 0);
      await aPool.borrow(token0.address, borrowAmount, 2, 0, deployer.address);

      let targetRate = 20000; // 2%
      let params = await aaveHandler.getUsageParams(token0.address, 0);
      let amountToBorrow = await aaveHandler.borrowToTargetBorrowRate(
        targetRate,
        params
      );

      await aPool.borrow(
        token0.address,
        amountToBorrow,
        2,
        0,
        deployer.address
      );

      let borrwoRate = await aaveHandler.getCurrentBorrowRate(token0.address);
      expect(borrwoRate).to.equal(targetRate);
    });
  });
});
