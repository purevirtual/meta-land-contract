const { ethers } = require('hardhat')

async function main() {
    const contractAddress = '0xA7806431c8ce39381Df44C2Fb385218585F3e3Aa'    
    const StartUp = await ethers.getContractAt('Startup', contractAddress)

    const name = 'Test Startup'

    const tx = await StartUp.newStartup({
        name: name,
        mode: 2,
        logo: 'https://www.naiveui.com/assets/naivelogo-BdDVTUmz.svg',

        mission: 'https://ipfs.io/ipfs/QmYx6GsYAKnNzZ9A6NvEKV9nf1VaDzJrqDR23Y8YSkebLU',
        overview: 'https://ipfs.io/ipfs/QmYx6GsYAKnNzZ9A6NvEKV9nf1VaDzJrqDR23Y8YSkebLUhttps://ipfs.io/ipfs/QmYx6GsYAKnNzZ9A6NvEKV9nf1VaDzJrqDR23Y8YSkebLUhttps://ipfs.io/ipfs/QmYx6GsYAKnNzZ9A6NvEKV9nf1VaDzJrqDR23Y8YSkebLU'

    }, {
        value: ethers.utils.parseEther('0.01')
    })

    console.log(tx);
    
    const s = await StartUp.startups(name)

    console.log(s);
    
}

main()