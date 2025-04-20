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
        "e6277f1f6d301bd3faf38e02f27f068b15abd3dc9f40a898112df9a287fbaef7",
      ],
    },
  },
};
