const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const compound = require("./compound/deploy");
const m = require("mocha-logger");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Protocol Interfaces tests", function () {
  const provider = waffle.provider;
  const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  async function compoundInterfaceTestFixture() {
    const ERC20Token = await ethers.getContractFactory(`MockERC20`);
    let token0 = await ERC20Token.deploy("Mock token0", "Token0", 18);
    let usdt = await ERC20Token.deploy("Mock USDT", "USDT", 6);

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

    let CompoundHandler = await ethers.getContractFactory("CompoundLogic");
    let compoundHandler = await CompoundHandler.deploy(
      comptroller.address,
      cETH.address,
      comp.address,
      { gasLimit: 5000000 }
    );

    await compoundHandler.updateCTokenList(cToken0.address);
    await compoundHandler.updateCTokenList(cUSDT.address);

    return {
      deployer: compoundContracts.deployer,
      comptroller: comptroller,
      token0: token0,
      usdt: usdt,
      cToken0: cToken0,
      cUSDT: cUSDT,
      cETH: cETH,
      comp: comp,
      compoundHandler: compoundHandler,
    };
  }

  describe("Compound interface tests", function () {
    it("should read data properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let compoundHandler = deploys.compoundHandler;
      let comptroller = deploys.comptroller;
      let comp = deploys.comp;

      expect(await compoundHandler.BASE()).to.equal("1000000000000");
      expect(await compoundHandler.BLOCK_PER_YEAR()).to.equal("2102400");
      expect((await compoundHandler.comptroller()).toLowerCase()).to.equal(
        comptroller.address.toLowerCase()
      );
      expect((await compoundHandler.rewardToken()).toLowerCase()).to.equal(
        comp.address.toLowerCase()
      );
    });

    it("should updateSupplyShare properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;

      let simulateSupplyData = await compoundHandler.lastSimulatedSupply(
        token0.address,
        deployer.address
      );

      expect(simulateSupplyData.amount).to.equal(0);
      expect(simulateSupplyData.index).to.equal(0);

      await compoundHandler.updateSupplyShare(token0.address, 1234567);

      simulateSupplyData = await compoundHandler.lastSimulatedSupply(
        token0.address,
        deployer.address
      );

      expect(simulateSupplyData.amount).to.equal(1234567);
      expect(simulateSupplyData.index).to.equal("1000000000000000000");
    });

    it("should updateBorrowShare properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;

      let simulateBorrowData = await compoundHandler.lastSimulatedBorrow(
        token0.address,
        deployer.address
      );

      expect(simulateBorrowData.amount).to.equal(0);
      expect(simulateBorrowData.index).to.equal(0);

      await compoundHandler.updateBorrowShare(token0.address, 1234567);

      simulateBorrowData = await compoundHandler.lastSimulatedBorrow(
        token0.address,
        deployer.address
      );

      expect(simulateBorrowData.amount).to.equal(1234567);
      expect(simulateBorrowData.index).to.equal("1000000000000000000");
    });

    it("should calculate supply Interest properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(cToken0.address, supplyAmount);
      await cToken0.mint(supplyAmount);
      await compoundHandler.updateSupplyShare(token0.address, supplyAmount);
      await cToken0.borrow(borrowAmount);

      await hre.network.provider.send("hardhat_mine", [
        "0x" + (2102400).toString(16),
      ]);

      let simulateInterest = await compoundHandler.lastSupplyInterest(
        token0.address,
        deployer.address
      );

      let cToken0Interface = await ethers.getContractAt(
        "contracts/Compound/CTokenInterface.sol:CTokenInterface",
        cToken0.address
      );

      let balance = await cToken0Interface.balanceOfUnderlying(
        deployer.address
      );

      expect(simulateInterest).to.equal(balance.sub(supplyAmount));
    });

    it("should calculate borrow interest proerly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(cToken0.address, supplyAmount);
      await cToken0.mint(supplyAmount);
      await compoundHandler.updateBorrowShare(token0.address, borrowAmount);
      await cToken0.borrow(borrowAmount);

      await hre.network.provider.send("hardhat_mine", [
        "0x" + (2102400).toString(16),
      ]);

      let simulateInterest = await compoundHandler.lastBorrowInterest(
        token0.address,
        deployer.address
      );

      let cToken0Interface = await ethers.getContractAt(
        "contracts/Compound/CTokenInterface.sol:CTokenInterface",
        cToken0.address
      );

      let balance = await cToken0Interface.balanceOfUnderlying(
        deployer.address
      );

      expect(simulateInterest).to.equal(balance.sub(supplyAmount));
    });

    it("should getSupplyData correctly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(cToken0.address, supplyAmount);

      let data = await compoundHandler.getSupplyData(
        token0.address,
        supplyAmount
      );

      let tx = {
        from: deployer.address,
        to: data.target,
        value: 0,
        gasLimit: ethers.utils.hexlify(1000000),
        data: data.encodedData,
      };

      await deployer.sendTransaction(tx);

      let cToken0Interface = await ethers.getContractAt(
        "contracts/Compound/CTokenInterface.sol:CTokenInterface",
        cToken0.address
      );

      let balance = await cToken0Interface.balanceOfUnderlying(
        deployer.address
      );

      expect(balance).to.equal(supplyAmount);
    });

    it("should getRedeemData correctly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(cToken0.address, supplyAmount);
      await cToken0.mint(supplyAmount);

      let data = await compoundHandler.getRedeemData(
        token0.address,
        supplyAmount
      );

      let tx = {
        from: deployer.address,
        to: data.target,
        value: 0,
        gasLimit: ethers.utils.hexlify(1000000),
        data: data.encodedData,
      };

      await deployer.sendTransaction(tx);
      let cToken0Interface = await ethers.getContractAt(
        "contracts/Compound/CTokenInterface.sol:CTokenInterface",
        cToken0.address
      );

      let balance = await cToken0Interface.balanceOfUnderlying(
        deployer.address
      );

      expect(balance).to.equal(0);
    });

    it("should getBorrowData correctly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(cToken0.address, supplyAmount);
      await cToken0.mint(supplyAmount);

      let data = await compoundHandler.getBorrowData(
        token0.address,
        borrowAmount
      );

      let tx = {
        from: deployer.address,
        to: data.target,
        value: 0,
        gasLimit: ethers.utils.hexlify(1000000),
        data: data.encodedData,
      };

      await deployer.sendTransaction(tx);

      let balanceLeft = await token0.balanceOf(cToken0.address);

      expect(supplyAmount.sub(balanceLeft)).to.equal(borrowAmount);
    });

    it("should getRepayData correctly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount.mul(2));
      await token0.approve(cToken0.address, supplyAmount.mul(2));
      await cToken0.mint(supplyAmount);
      await cToken0.borrow(borrowAmount);

      let data = await compoundHandler.getRepayData(
        token0.address,
        borrowAmount
      );

      let tx = {
        from: deployer.address,
        to: data.target,
        value: 0,
        gasLimit: ethers.utils.hexlify(1000000),
        data: data.encodedData,
      };

      await deployer.sendTransaction(tx);

      let balanceLeft = await token0.balanceOf(cToken0.address);

      expect(balanceLeft).to.equal(supplyAmount);
    });

    it("should call supplyOf properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(cToken0.address, supplyAmount);
      await cToken0.mint(supplyAmount);

      let token0Supply = await compoundHandler.supplyOf(
        token0.address,
        deployer.address
      );

      expect(token0Supply).to.equal(supplyAmount);
    });

    it("should call debtOf properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(cToken0.address, supplyAmount);
      await cToken0.mint(supplyAmount);
      await cToken0.borrow(borrowAmount);

      let token0Debt = await compoundHandler.debtOf(
        token0.address,
        deployer.address
      );

      expect(token0Debt).to.equal(borrowAmount);
    });

    it("should calculate totalColletralAndBorrow properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;
      let usdt = deploys.usdt;
      let cUSDT = deploys.cUSDT;

      let borrowToken0Amount = ethers.BigNumber.from("100000000000000000");
      let supplyToken0Amount = borrowToken0Amount.mul(2);

      await token0.mint(deployer.address, supplyToken0Amount);
      await token0.approve(cToken0.address, supplyToken0Amount);
      await cToken0.mint(supplyToken0Amount);

      let borrowUSDTAmount = ethers.BigNumber.from("10000000");
      let supplyUSDTAmount = borrowUSDTAmount.mul(2);

      await usdt.mint(deployer.address, supplyUSDTAmount);
      await usdt.approve(cUSDT.address, supplyUSDTAmount);
      await cUSDT.mint(supplyUSDTAmount);

      await cToken0.borrow(borrowToken0Amount);
      await cUSDT.borrow(borrowUSDTAmount);

      let [totalColletral, totalBorrow] =
        await compoundHandler.totalColletralAndBorrow(
          deployer.address,
          usdt.address
        );

      expect(totalColletral).to.equal(40000000);
      expect(totalBorrow).to.equal(20000000);
    });

    it("should get currentSupplyRate properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(cToken0.address, supplyAmount);
      await cToken0.mint(supplyAmount);
      await cToken0.borrow(borrowAmount);

      let supplyRate = await compoundHandler.getCurrentSupplyRate(
        token0.address
      );
      expect(supplyRate).to.equal(12499);
    });

    it("should get getCurrentBorrowRate properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount);
      await token0.approve(cToken0.address, supplyAmount);
      await cToken0.mint(supplyAmount);
      await cToken0.borrow(borrowAmount);

      let borrowRate = await compoundHandler.getCurrentBorrowRate(
        token0.address
      );
      expect(borrowRate).to.equal(24999);
    });

    it("should calculate supplyToTargetSupplyRate properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount.mul(2));
      await token0.approve(cToken0.address, supplyAmount.mul(2));
      await cToken0.mint(supplyAmount);
      await cToken0.borrow(borrowAmount);

      let targetRate = 5000; // 0.5%
      let params = await compoundHandler.getUsageParams(token0.address, 0);
      let amountToSupply = await compoundHandler.supplyToTargetSupplyRate(
        targetRate,
        params
      );

      await cToken0.mint(amountToSupply);
      let supplyRate = await compoundHandler.getCurrentSupplyRate(
        token0.address
      );

      expect(supplyRate).to.equal(targetRate);
    });

    it("should calculate borrowToTargetBorrowRate properly", async () => {
      const deploys = await loadFixture(compoundInterfaceTestFixture);

      let deployer = deploys.deployer;
      let comptroller = deploys.comptroller;
      let compoundHandler = deploys.compoundHandler;
      let token0 = deploys.token0;
      let cToken0 = deploys.cToken0;

      let borrowAmount = ethers.BigNumber.from("100000000000000000");
      let supplyAmount = borrowAmount.mul(2);

      await token0.mint(deployer.address, supplyAmount.mul(2));
      await token0.approve(cToken0.address, supplyAmount.mul(2));
      await cToken0.mint(supplyAmount);
      await cToken0.borrow(borrowAmount);

      let targetRate = 30000; // 3%
      let params = await compoundHandler.getUsageParams(token0.address, 0);
      let amountToBorrow = await compoundHandler.borrowToTargetBorrowRate(
        targetRate,
        params
      );

      await cToken0.borrow(amountToBorrow);

      let borrwoRate = await compoundHandler.getCurrentBorrowRate(
        token0.address
      );
      expect(borrwoRate).to.equal(targetRate);
    });
  });
});
