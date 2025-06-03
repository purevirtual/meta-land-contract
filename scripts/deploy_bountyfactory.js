const { ethers, upgrades } = require("hardhat");

// bounty factory也是uups，基本和bountyFactory一样
async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    const BountyFactory = await ethers.getContractFactory("BountyFactory");
    // 假设你已经有一个合适的bountyBeaconAddress, 就是BountyBeacon 的部署地址
    const bountyBeaconAddress = '0x1234567890123456789012345678901234567890';
    // 部署BountyFactory可升级合约
    const bountyFactory = await upgrades.deployProxy(BountyFactory, [bountyBeaconAddress], {
        initializer: 'initialize',
        kind: 'uups'
    });
    await bountyFactory.deployed();
    console.log("BountyFactory deployed to(proxy contract):", await bountyFactory.address);
    // 底层逻辑地址，升级时候使用 可以不用，直接去链上查 就是麻烦点
    // console.log("BountyFactory logic contract is:", await bountyFactory.getImplementation());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 