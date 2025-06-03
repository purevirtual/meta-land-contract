const { ethers, upgrades } = require("hardhat");

async function main() {
    // 这里使用第一次部署得到的代理合约地址，而不是重新部署代理合约
    //const proxyAddress = 'YOUR_PROXY_CONTRACT_ADDRESS';
    const proxyAddress = '0xe6cd99223e209bd04de48c083746717c6519a56d';

    const [deployer] = await ethers.getSigners();
    console.log("upgrade with contracts using account:", deployer.address);

    // 假设新写的合约 还是原来的Startup，但实际上可以改名
    const newContract = await ethers.getContractFactory('BountyFactory');

    // 这里必须调一个函数，否则会有问题
    const upgraded = await upgrades.upgradeProxy(proxyAddress, newContract, { call:"owner"});

    await upgraded.deployed();
    console.log('Contract upgraded');
    console.log("BountyFactory upgraded, proxy address is:", proxyAddress);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 