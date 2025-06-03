const { ethers, upgrades } = require('hardhat');

// beacon这个比较复杂，所以把deploy和upgrade合二为一, 实际使用的时候自己增减
async function main() {
    // 部署逻辑合约
    const MyImplementation = await ethers.getContractFactory('Bounty');
    const myImplementation = await MyImplementation.deploy();
    await myImplementation.deployed();
    console.log('MyImplementation[Bounty] deployed to:', myImplementation.address);

    // 部署信标合约
    const MyBeacon = await ethers.getContractFactory('BountyBeacon');
    // 合约 MyBeacon 中，没有定义传统的构造函数（即与合约同名的函数），而是使用了 initialize 函数进行初始化，这是在可升级合约模式中常见的做法（使用 OpenZeppelin 的 Initializable 等相关库）。
    // const myBeacon = await BountyBeacon.deploy(myImplementation.address);
    const myBeacon = await upgrades.deployProxy(MyBeacon, [myImplementation.address]);

    await myBeacon.deployed();
    console.log('MyBeacon[BountyBeacon] deployed to:', myBeacon.address);

    // 部署代理合约
    const MyBeaconProxy = await ethers.getContractFactory('BeaconProxy');
    // 使用ethers.getContractAt获取合约接口
    // 这里 ethers.getContractAt 的第二个参数是一个虚拟地址（因为我们只关心获取接口，不实际调用合约），通过获取到的合约对象的 interface 属性，同样可以方便地编码函数调用数据。这种方法避免了手动引入 ABI 文件的步骤，在 Hardhat 项目中使用起来更简洁。
    const yourContract = await ethers.getContractAt('Bounty', '0x0000000000000000000000000000000000000000');
    const data = yourContract.interface.encodeFunctionData('owner()', []);
    // 错误原因同上
    // const myBeaconProxy = await MyBeaconProxy.deploy(myBeacon.address, ethers.utils.id('owner()'));
    const myBeaconProxy = await MyBeaconProxy.deploy(myBeacon.address, data);
    await myBeaconProxy.deployed();
    console.log('MyBeaconProxy[BeaconProxy] deployed to:', myBeaconProxy.address);

    // 通过代理合约调用逻辑合约函数
    const proxyContract = await ethers.getContractAt('Bounty', myBeaconProxy.address);
    await proxyContract.incrementValue();
    const value = await proxyContract.value();
    console.log('Incremented value:', value.toString());

//// !!!!
    // 升级逻辑合约
    const newImplementation = await MyImplementation.deploy();
    await newImplementation.deployed();
    console.log('New MyImplementation[Bounty] deployed to:', newImplementation.address);
    const beaconContract = await ethers.getContractAt('BountyBeacon', myBeacon.address);
    await beaconContract.upgradeTo(newImplementation.address);
    console.log('Upgraded to new implementation:', newImplementation.address);

    // 通过代理合约调用升级后的逻辑合约函数
    await proxyContract.incrementValue();
    const newValue = await proxyContract.value();
    console.log('Incremented value after upgrade:', newValue.toString());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });