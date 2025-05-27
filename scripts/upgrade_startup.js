const { ethers, upgrades } = require("hardhat");

async function main() {
    // 这里使用第一次部署得到的代理合约地址，而不是重新部署代理合约
    //const proxyAddress = 'YOUR_PROXY_CONTRACT_ADDRESS';
    const proxyAddress = '0x0341d6e0770aec333271a16044cdaf69ade40dad';

    const [deployer] = await ethers.getSigners();
    console.log("upgrade with contracts using account:", deployer.address);

    // 假设新写的合约 还是原来的Startup，但实际上可以改名
    const newContract = await ethers.getContractFactory('Startup');

    const upgraded = await upgrades.upgradeProxy(proxyAddress, newContract, { gasLimit: 5000000 });

    await upgraded.deployed();
    console.log('Contract upgraded');

    // 获取升级后的逻辑合约地址
    const newImplementationAddress = await upgraded.getImplementation();
    console.log("Startup upgraded, proxy address is:", proxyAddress);
    console.log('startup upgraded, logic address is', newImplementationAddress);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 