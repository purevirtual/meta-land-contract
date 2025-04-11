require("@nomicfoundation/hardhat-toolbox");

const infuraKey = "d8ed0bd1de8242d998a1405b6932ab33";

module.exports = {
  solidity: {
    version: "0.8.20",

    settings: {
      evmVersion: "shanghai",
      optimizer: {
        enabled: true,
        runs: 200, // 增加 runs 值以提高优化效果
      },
    },
  },
  networks: {
    sepolia: {
      allowUnlimitedContractSize: true,
      url: "https://sepolia.infura.io/v3/" + infuraKey,
      accounts: [
        "c251e3b9822005f6ba00b228568d046e0d11f21b7ea69aa2d87475aaaf2aa515",
      ],
    },
  },
};
