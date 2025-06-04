const { ethers } = require("hardhat");
async function main() {
    const address = '0x44946827bd47F4D8ad974Ce0CAF195D3835c61A3'
    const CrowdfundingFactory = await ethers.getContractAt("CrowdfundingFactory", address);

    const tx = await CrowdfundingFactory.createCrowdfundingContract(
        {
            
        }
    )
}

main();
