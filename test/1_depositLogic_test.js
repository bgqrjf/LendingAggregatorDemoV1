const { expect } = require("chai");
const { ethers } = require("hardhat");


describe("DepositLogic Tests", function () {
  let USDT;
  let router;
  let pool;
  let supplier;
  let payee;

  beforeEach(async () =>{
    [supplier, payee] = await ethers.getSigners();

    let MockERC20 = await ethers.getContractFactory("MockERC20");
    let Router = await ethers.getContractFactory("Router");
    let Config = await ethers.getContractFactory("Config")
    let Pool = await ethers.getContractFactory("Pool");

    USDT = await MockERC20.deploy("USDT", 6);

    await USDT.mint(supplier.address, 10);

    router = await Router.deploy();
    let config =  await Config.deploy();
    pool = await Pool.deploy(config.address, router.address);
  })

  describe("deposit test", function(){

    it("should deposit ERC20 properly", async() =>{
      await USDT.approve(pool.address, 1000000);
      await pool.deposit(USDT.address, supplier.address, 1000000);
      let routerBalance = await USDT.balanceOf(router.address);
      expect(routerBalance).to.equal(1000000);
    })

    it("should deposit ETH properly", async() =>{
      await pool.depositETH(supplier.address,{value: ethers.utils.parseEther("1.0")});
      let routerBalance = await waffle.provider.getBalance(router.address);
      expect(routerBalance).to.equal(ethers.utils.parseEther("1.0"));
    })
  })
  
  describe("withdraw test", function(){
    it("should withdraw ERC20 properly", async() => {
      await USDT.approve(pool.address, 1000000);
      await pool.deposit(USDT.address, supplier.address, 1000000);
      await pool.withdraw(USDT.address, payee.address, 1000000);

      let routerBalance = await USDT.balanceOf(router.address);
      let payeeBalance = await USDT.balanceOf(payee.address);

      expect(routerBalance).to.equal(0);
      expect(payeeBalance).to.equal(1000000);
    })

    it("should withdraw ETH properly", async() => {
      let payeeBalanceInit = await waffle.provider.getBalance(payee.address);

      await pool.depositETH(supplier.address,{value: ethers.utils.parseEther("1.0")});
      await pool.withdrawETH(payee.address, ethers.utils.parseEther("1.0"));

      let routerBalance = await waffle.provider.getBalance(router.address);
      let payeeBalance = await waffle.provider.getBalance(payee.address);

      expect(routerBalance).to.equal(ethers.utils.parseEther("0.0"));
      expect(payeeBalance).to.equal(payeeBalanceInit.add(ethers.utils.parseEther("1.0")));

    })

  })
});
