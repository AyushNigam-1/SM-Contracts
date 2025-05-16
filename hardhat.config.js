require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-ignition");
require("dotenv").config();

module.exports = {
  solidity: "0.8.20",
  networks: {
    xdc: {
      url: "https://rpc.apothem.network", // Apothem Testnet
      chainId: 51,
      accounts: ["YOUR_PRIVATE_KEY"],
    },
  },
};
